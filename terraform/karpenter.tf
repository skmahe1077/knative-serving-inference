# Karpenter provisions the application node pool on demand. Its own controller
# runs on the system node group (eks.tf), so Karpenter never depends on capacity
# it manages itself — if it crashes or is slow to schedule nodes, it still comes
# back up on stable infrastructure.

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "20.31.1"

  cluster_name = module.eks.cluster_name

  enable_pod_identity             = true
  create_pod_identity_association = true
  # The module defaults the association to kube-system; the helm_release
  # below installs Karpenter into its own "karpenter" namespace instead.
  namespace = "karpenter"

  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }
}

resource "helm_release" "karpenter" {
  name             = "karpenter"
  namespace        = "karpenter"
  create_namespace = true

  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = "1.1.1"

  values = [
    yamlencode({
      serviceAccount = {
        name = "karpenter"
      }
      settings = {
        clusterName       = module.eks.cluster_name
        clusterEndpoint   = module.eks.cluster_endpoint
        interruptionQueue = module.karpenter.queue_name
      }
      replicas = 2
      # Karpenter must run on the stable system pool, not on nodes it provisions.
      tolerations = [
        {
          key      = "node-role"
          operator = "Equal"
          value    = "system"
          effect   = "NoSchedule"
        }
      ]
      nodeSelector = {
        "node-role" = "system"
      }
    })
  ]

  depends_on = [module.eks, module.karpenter]
}

resource "kubectl_manifest" "karpenter_node_class" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata   = { name = "application-default" }
    spec = {
      amiFamily = "AL2023"
      # Karpenter v1's EC2NodeClass requires amiSelectorTerms explicitly —
      # amiFamily alone no longer implies AMI discovery. This alias tracks
      # AWS's latest AL2023 EKS-optimized AMI automatically.
      amiSelectorTerms = [
        { alias = "al2023@latest" }
      ]
      role = module.karpenter.node_iam_role_name
      subnetSelectorTerms = [
        { tags = { "karpenter.sh/discovery" = module.eks.cluster_name } }
      ]
      securityGroupSelectorTerms = [
        { tags = { "karpenter.sh/discovery" = module.eks.cluster_name } }
      ]
      metadataOptions = {
        httpEndpoint            = "enabled"
        httpProtocolIPv6        = "disabled"
        httpPutResponseHopLimit = 2
        httpTokens              = "required"
      }
      blockDeviceMappings = [
        {
          deviceName = "/dev/xvda"
          ebs = {
            volumeSize          = "40Gi"
            volumeType          = "gp3"
            encrypted           = true
            deleteOnTermination = true
          }
        }
      ]
    }
  })

  depends_on = [helm_release.karpenter]
}

resource "kubectl_manifest" "karpenter_node_pool" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata   = { name = "application-default" }
    spec = {
      template = {
        metadata = {
          # Knative Service manifests select this label to force application
          # pods onto Karpenter-managed nodes (see k8s_manifests/).
          labels = { "node-role" = "application" }
        }
        spec = {
          nodeClassRef = {
            group = "karpenter.k8s.aws"
            kind  = "EC2NodeClass"
            name  = "application-default"
          }
          requirements = [
            { key = "kubernetes.io/arch", operator = "In", values = ["amd64"] },
            { key = "karpenter.sh/capacity-type", operator = "In", values = ["on-demand"] },
            { key = "node.kubernetes.io/instance-type", operator = "In", values = var.karpenter_instance_types },
          ]
        }
      }
      limits = {
        cpu = tostring(var.karpenter_cpu_limit)
      }
      disruption = {
        # Lets idle application nodes terminate quickly after the demo's
        # scale-to-zero traffic drops, while a disruption budget keeps
        # consolidation from taking out nodes serving live traffic.
        consolidationPolicy = "WhenEmptyOrUnderutilized"
        consolidateAfter    = "1m"
        budgets = [
          { nodes = "10%" }
        ]
      }
    }
  })

  depends_on = [kubectl_manifest.karpenter_node_class]
}
