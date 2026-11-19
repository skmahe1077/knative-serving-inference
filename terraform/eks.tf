# Customer-managed KMS key for EKS secrets envelope encryption (Kubernetes Secrets at
# rest). This account owns and rotates the key; EKS only ever sees ciphertext.
resource "aws_kms_key" "eks" {
  description             = "EKS secrets envelope encryption for ${var.cluster_name}"
  deletion_window_in_days = 30
  enable_key_rotation     = true
}

resource "aws_kms_alias" "eks" {
  name          = "alias/${var.cluster_name}-eks"
  target_key_id = aws_kms_key.eks.key_id
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.31.1"

  cluster_name    = var.cluster_name
  cluster_version = var.kubernetes_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Private access is always on. Public access defaults to off; flip
  # enable_public_eks_access only if you have no other way to reach the endpoint
  # (see README "Accessing the private API endpoint" for the recommended alternative).
  cluster_endpoint_private_access      = true
  cluster_endpoint_public_access       = var.enable_public_eks_access
  cluster_endpoint_public_access_cidrs = var.enable_public_eks_access ? var.public_access_cidrs : []

  cluster_enabled_log_types = [
    "api", "audit", "authenticator", "controllerManager", "scheduler"
  ]
  cloudwatch_log_group_retention_in_days = var.cluster_log_retention_days

  create_kms_key = false
  cluster_encryption_config = {
    provider_key_arn = aws_kms_key.eks.arn
    resources        = ["secrets"]
  }

  # EKS access entries (not the legacy aws-auth ConfigMap) drive cluster access.
  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = true

  access_entries = merge(
    {
      for arn in var.eks_admin_role_arns : "admin-${md5(arn)}" => {
        principal_arn = arn
        policy_associations = {
          admin = {
            policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
            access_scope = { type = "cluster" }
          }
        }
      }
    },
    {
      for arn in var.eks_developer_role_arns : "dev-${md5(arn)}" => {
        principal_arn = arn
        policy_associations = {
          edit = {
            policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"
            access_scope = { type = "cluster" }
          }
        }
      }
    }
  )

  cluster_addons = {
    vpc-cni = {
      most_recent    = true
      before_compute = true
    }
    coredns = {
      most_recent = true
      # CoreDNS is a plain Deployment, not a DaemonSet with a blanket
      # toleration like kube-proxy/vpc-cni — without this it can never
      # schedule onto the tainted system node group.
      configuration_values = jsonencode({
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
    }
    kube-proxy = {
      most_recent = true
    }
    eks-pod-identity-agent = {
      most_recent    = true
      before_compute = true
    }
  }

  eks_managed_node_groups = {
    system = {
      name = "${var.cluster_name}-system"

      # Explicit, short IAM role name: the module's default name-prefix
      # ("<node-group-iam-role-name>-") can exceed IAM's 38-character limit
      # for name_prefix once it's built from a longer cluster_name.
      iam_role_name            = "${var.cluster_name}-system-ng"
      iam_role_use_name_prefix = false

      instance_types = var.system_node_instance_types
      ami_type       = "AL2023_x86_64_STANDARD"
      capacity_type  = "ON_DEMAND"

      min_size     = var.system_node_min_size
      max_size     = var.system_node_max_size
      desired_size = var.system_node_desired_size

      subnet_ids = module.vpc.private_subnets

      labels = {
        "node-role" = "system"
      }

      # Keeps application workloads off this stable pool; they land on
      # Karpenter-provisioned nodes instead (see karpenter.tf). Every system
      # component's Helm values/manifests carry a matching toleration.
      taints = {
        system = {
          key    = "node-role"
          value  = "system"
          effect = "NO_SCHEDULE"
        }
      }

      tags = {
        "karpenter.sh/discovery" = var.cluster_name
      }
    }
  }

  node_security_group_tags = {
    "karpenter.sh/discovery" = var.cluster_name
  }
}
