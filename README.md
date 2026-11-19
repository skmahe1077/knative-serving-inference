# knative-serving-demo

A small FastAPI inference app, served by Knative Serving on a production-grade
Amazon EKS cluster, that scales from zero to demand. Built for a meetup talk:
the infrastructure is provisioned ahead of time, and the 25-minute demo is
just steps 5-7 below.

## Architecture

```
Internet (optional) ──▶ ALB (AWS LB Controller) ──▶ Kourier Gateway ──▶ Knative Revision pod
                                                                              │
                          VPC — 3 AZs, private subnets                      │
                          ┌─────────────────────────────────────────────────┤
                          │  System node group (EKS managed, tainted)       │
                          │    Knative control plane, Kourier, Karpenter,   │
                          │    AWS LB Controller, Prometheus/Grafana        │
                          │                                                 │
                          │  Application nodes (Karpenter, on-demand)      ◀┘
                          │    iris-classifier pods only — scale to 0 when idle
                          └─────────────────────────────────────────────────┘
```

The system node group carries a `node-role=system:NoSchedule` taint, so
application pods can never land there — they can only run on nodes Karpenter
provisions, and Karpenter itself always runs on the stable system pool, never
on nodes it manages.

## Repository layout

```
terraform/          AWS infrastructure (VPC, EKS, IAM, Karpenter, AWS LB Controller)
app/                 FastAPI inference service (Dockerfile, tests)
k8s_manifests/       Namespace, NetworkPolicy, Knative Service profiles, ServiceMonitor
monitoring/          kube-prometheus-stack Helm values + the demo Grafana dashboard
scripts/             One step per file: provision, configure, build, install, deploy, demo, destroy
```

## Prerequisites

- Terraform >= 1.9, AWS CLI v2, kubectl, helm, docker
- An AWS account and credentials with permission to create the resources below
- An S3 bucket for Terraform state (see "Bootstrap the state backend")

## Bootstrap the state backend

Terraform can't create its own remote backend on the first run, so create it
once, out of band:

```bash
aws s3api create-bucket --bucket <your-state-bucket> --region <your-region> \
  --create-bucket-configuration LocationConstraint=<your-region>
aws s3api put-bucket-versioning --bucket <your-state-bucket> \
  --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket <your-state-bucket> \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"aws:kms"}}]}'
aws s3api put-public-access-block --bucket <your-state-bucket> \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

Terraform >= 1.10 can lock state natively on S3 (pass `use_lockfile=true` as a
backend config); on older Terraform, create a DynamoDB table with a `LockID`
string partition key and pass it as `TF_LOCK_TABLE` below instead.

## Deployment workflow

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars   # fill in your values

export TF_STATE_BUCKET=<your-state-bucket>
export TF_STATE_REGION=<your-region>

scripts/01-provision-infra.sh                  # VPC, EKS, Karpenter, LB controller IAM
scripts/02-configure-kubectl.sh                # point kubectl at the new cluster
scripts/03-build-push-image.sh                 # build + push the app image to ECR
scripts/04-install-knative-and-monitoring.sh   # Knative, Kourier, Prometheus, Grafana
scripts/05-deploy-app.sh demo                   # or: scripts/05-deploy-app.sh production
scripts/06-demo-scale-to-zero.sh                # the actual demo
scripts/07-view-dashboards.sh                   # Grafana, port-forwarded

scripts/destroy.sh                              # tear down everything when done
```

Run 01-04 well before the talk — infrastructure must already exist going in;
nothing here is fast enough to provision live on stage.

## Accessing the private API endpoint

`enable_public_eks_access` defaults to `false`: the EKS API server is only
reachable from inside the VPC. Recommended ways to reach it:

- An AWS Client VPN or Site-to-Site VPN terminating into the VPC.
- An SSM-managed bastion in a private subnet, reached with
  `aws ssm start-session` and local port forwarding to the API endpoint — no
  open inbound ports, no SSH key to manage.

If neither is available, set `enable_public_eks_access = true` and scope
`public_access_cidrs` to your own IP only; this is not the default for a
reason.

## Workload profiles

- **`knative-service-demo.yaml`** — `minScale: 0`. Built to show scale-to-zero
  and a real cold start.
- **`knative-service-production.yaml`** — `minScale: 2`, higher resource
  limits. A starting point, not a universal answer: pick `min-scale` and
  `target` from your own latency and availability requirements. Scale-to-zero
  trades cold-start latency for cost, and that trade is wrong for workloads
  that can't tolerate a cold start on the first request after idle — this
  demo does not claim otherwise.

### Cold start has two very different regimes

Measured directly against the live cluster, not estimated:

- **A warm application node already exists** (e.g. the burst-load test ran
  minutes earlier and Karpenter hasn't consolidated the node away yet): the
  Knative activator only has to wait for a new pod to schedule and pass its
  readiness probe. Measured: **~4 seconds**, correct prediction returned.
- **No application node exists and Karpenter has to launch a new EC2
  instance from scratch**: node launch-to-`Initialized` alone measured
  **~31 seconds** in testing — before the pod even starts. The first request
  after a full scale-down, run back-to-back with the test above, hit
  `activator request timeout` at the Knative default of 30s. A burst of 60
  requests sent seconds later, once the node was actually ready, all
  returned `200`.

`knative-service-demo.yaml`'s `timeoutSeconds` is set to 60 (not Knative's
usual 30) specifically to absorb the slow-path case live on stage. Even that
isn't a hard guarantee — EC2 launch time varies, and this is exactly the
nuance in "explain the difference between removing a pod and terminating a
node" the requirements for this project call out: scale-to-zero cost savings
come from the **node** going away, but that's also precisely what makes the
next cold start slow. A workload that can't tolerate an occasional
30-60+ second first-request latency should run the production profile with
`minScale >= 1` instead.

## Validation

Run from the repo root:

```bash
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform init -backend=false && terraform -chdir=terraform validate
tflint --chdir=terraform                       # if installed
trivy config terraform/ k8s_manifests/ app/Dockerfile
python3 -m venv app/.venv && app/.venv/bin/pip install -r app/requirements-dev.txt
app/.venv/bin/python -m pytest app/tests/ -v
trivy image <your-ecr-image-uri>                # after scripts/03-build-push-image.sh
```

**What has actually been run against this repository:** `terraform fmt`,
`terraform validate`, and a `trivy config` scan against `terraform/`,
`k8s_manifests/`, and `app/Dockerfile` all pass with zero findings. The
pytest suite (5 tests: health, readiness, prediction, input validation,
metrics exposure) passes locally. `terraform apply` has been run for real
against AWS account `038462791702` (eu-west-1) — the VPC, EKS cluster,
system node group, Karpenter, and the AWS Load Balancer Controller are all
up and confirmed healthy (`kubectl get nodes`, Karpenter/LB-controller/CoreDNS
pods all `Running`, `EC2NodeClass`/`NodePool` both `Ready: True`). Three real
bugs surfaced during that run and are now fixed in the committed config —
worth knowing about if you're adapting this elsewhere:

- **CoreDNS vs. the system-node taint**: CoreDNS is a plain Deployment, not a
  DaemonSet with a blanket toleration like kube-proxy/vpc-cni, so it needs an
  explicit `configuration_values` toleration/nodeSelector on the addon
  (`eks.tf`) or it never schedules.
- **ECR Public throttles anonymous pulls**: the Karpenter chart is pulled
  from `oci://public.ecr.aws`; without `aws ecr-public get-login-password |
  helm registry login` first (now in `scripts/01-provision-infra.sh`), the
  pull gets a 403 even though the repo is public.
- **Karpenter Pod Identity namespace mismatch**: the
  `terraform-aws-modules/eks/aws//modules/karpenter` module defaults its pod
  identity association to the `kube-system` namespace; this project installs
  Karpenter into its own `karpenter` namespace instead, so `namespace =
  "karpenter"` has to be passed explicitly (`karpenter.tf`) or the controller
  gets no AWS credentials and crash-loops on a misleading SQS error.
- **Karpenter v1's `EC2NodeClass` requires `amiSelectorTerms` explicitly** —
  `amiFamily` alone no longer triggers automatic AMI discovery; use an alias
  term like `{ alias = "al2023@latest" }`.

**`scripts/03` through `scripts/06` have also been run for real** against
that cluster: the image built and pushed to ECR; Knative Serving, Kourier,
and kube-prometheus-stack all installed and came up healthy; the demo
profile deployed and `kubectl wait --for=condition=Ready` succeeded; a real
`/predict` request returned a correct prediction; the revision scaled to
zero after ~80s idle; a request against a scaled-to-zero revision cold-started
and returned a correct prediction in ~4s; a burst of concurrent requests all
returned `200`. Three more gaps surfaced and are fixed in the committed
config:

- **No EBS CSI driver is installed**, so Prometheus's PVC (`storageSpec` in
  the original `prometheus-values.yaml`) could never bind and the pod stuck
  `Pending`. Fixed by dropping persistent storage — Prometheus runs on
  `emptyDir` (metrics history lost on pod restart, an acceptable trade for a
  demo cluster). Add the addon and a `volumeClaimTemplate` back for durable
  retention.
- **Two one-off Helm hook Jobs land on Karpenter nodes unnecessarily**: the
  Knative deployments briefly exist without their system-node toleration in
  the gap between `kubectl apply` and the follow-up `kubectl patch` in
  `scripts/04`, and kube-prometheus-stack's webhook-cert `patch` Job
  (`prometheusOperator.admissionWebhooks.patch`) had no toleration/nodeSelector
  at all. Both are harmless and self-correcting (Karpenter consolidates the
  unneeded node within ~1 minute), and the second is now fixed in
  `monitoring/prometheus-values.yaml`.
- **`scripts/06`'s Host header only works against `svc/kourier`'s external
  listener** if a real domain is configured. With the internal-only default
  (no `domain_name` set), Knative's route only has a `*.svc.cluster.local`
  vhost, which Kourier only serves on `svc/kourier-internal` — the external
  listener 404s on that Host header. Fixed with a host-suffix check that
  picks the right service either way. Also swapped `watch` (not installed on
  macOS by default) for a plain polling loop.

**This cluster is live and billing right now, with the demo app deployed.**
Run `scripts/destroy.sh` when you're done with it — see "Cleaning up" below.

### Verifying specific properties, once deployed

- **High availability**: `kubectl get nodes -L topology.kubernetes.io/zone`
  should show the system node group spread across all three AZs; cordon one
  system node and confirm Knative/Kourier pods reschedule onto the others.
- **IAM permissions**: `aws eks list-access-entries --cluster-name <name>`
  for who has access; `kubectl get pods -n kube-system aws-load-balancer-controller-xxx -o jsonpath='{.spec.serviceAccountName}'`
  then check its Pod Identity association, rather than assuming the role is
  attached correctly.
- **Private networking**: from outside the VPC, `aws eks describe-cluster`
  should show the public endpoint disabled (or CIDR-restricted); `curl` to
  the API endpoint from outside should time out.
- **Node recovery**: `kubectl delete node <a-system-node>` (or terminate the
  instance in the EC2 console) and watch the managed node group replace it;
  `kubectl delete pod` on an app pod and watch Knative/Karpenter recreate it.
- **Autoscaling**: `scripts/06-demo-scale-to-zero.sh` exercises both the
  Knative autoscaler (pod count) and Karpenter (node count) in one pass —
  watch both in the Grafana dashboard while it runs.

## Cost, sustainability and what scale-to-zero actually saves

Removing an idle inference **pod** (Knative scaling to zero) frees CPU/memory
on a node that is still running and still billing. It does not reduce AWS
spend unless the node it was running on also becomes empty **and** Karpenter
consolidates it away — which is the application node pool's job here. The
system node group never scales to zero; it is the floor cost of this
architecture (3 nodes, by default), independent of inference traffic.

To measure rather than assume:

- Pod runtime and resource requests/limits: `kubectl describe pod` in the
  `inference` namespace, or the "Inference pod CPU/memory usage" panels in
  the demo dashboard.
- Karpenter node count and idle capacity: the "Karpenter application nodes"
  panel, plus `kubectl get nodes -l node-role=application`.
- Cold-start latency: timed directly by `scripts/06-demo-scale-to-zero.sh`.
- AWS cost: tag-filtered Cost Explorer on `Project=<cluster_name>`, or
  `infracost breakdown --path terraform/` for an estimate before you apply.

This project does not report carbon savings — doing so credibly needs
region-specific grid carbon-intensity data and per-instance power figures
that aren't collected here. Treat any such claim from a demo like this one
with real skepticism.

## Cleaning up

`scripts/destroy.sh` removes the app, Knative/Kourier, monitoring, and then
runs `terraform destroy`. The ECR repository and its images are created by
the build script, not Terraform, so they survive `destroy.sh` — remove them
separately with `aws ecr delete-repository --force` if you want them gone
too. The Terraform state bucket is also untouched; it was created out of
band and Terraform never owns it.
