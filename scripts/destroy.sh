#!/usr/bin/env bash
# Tears down everything: the app, Knative/Kourier, monitoring, and finally
# the AWS infrastructure via `terraform destroy`. Run this as soon as you're
# done with the demo — the EKS cluster, NAT gateways and any Karpenter nodes
# bill continuously while they exist.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require kubectl
require helm
require terraform

read -r -p "This will destroy the EKS cluster and all AWS infrastructure in this project. Continue? [y/N] " CONFIRM
[[ "${CONFIRM}" =~ ^[Yy]$ ]] || { echo "aborted"; exit 1; }

echo "==> deleting the app (lets Karpenter start consolidating nodes)"
kubectl delete -f "${ROOT_DIR}/k8s_manifests/knative-service-demo.yaml" --ignore-not-found
kubectl delete -f "${ROOT_DIR}/k8s_manifests/knative-service-production.yaml" --ignore-not-found
kubectl delete -f "${ROOT_DIR}/k8s_manifests/servicemonitor-inference.yaml" --ignore-not-found
kubectl delete -f "${ROOT_DIR}/k8s_manifests/network-policy.yaml" --ignore-not-found
kubectl delete -f "${ROOT_DIR}/k8s_manifests/namespace.yaml" --ignore-not-found

echo "==> uninstalling monitoring"
helm uninstall kube-prometheus-stack -n monitoring --ignore-not-found 2>/dev/null || true

echo "==> uninstalling Kourier and Knative Serving"
kubectl delete -f "https://github.com/knative/net-kourier/releases/download/knative-v1.16.0/kourier.yaml" --ignore-not-found
kubectl delete -f "https://github.com/knative/serving/releases/download/knative-v1.16.0/serving-core.yaml" --ignore-not-found
kubectl delete -f "https://github.com/knative/serving/releases/download/knative-v1.16.0/serving-crds.yaml" --ignore-not-found

echo "==> terraform destroy (this also removes any live Karpenter-provisioned nodes)"
terraform -chdir="${TERRAFORM_DIR}" destroy

echo "==> done. Double-check the AWS console for any resources left behind"
echo "    (ECR repository and its images are not managed by Terraform — see README)."
