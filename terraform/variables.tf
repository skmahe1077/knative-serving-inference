variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-west-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster and prefix for related resources"
  type        = string
  default     = "knative-serving-demo"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version. Must be compatible with the Knative Serving release installed by scripts/04-install-knative-and-monitoring.sh."
  type        = string
  default     = "1.31"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.42.0.0/16"
}

variable "availability_zones" {
  description = "Exactly three Availability Zones to spread the VPC and cluster across"
  type        = list(string)
  default     = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]

  validation {
    condition     = length(var.availability_zones) == 3
    error_message = "This architecture is designed for exactly three Availability Zones."
  }
}

variable "enable_public_eks_access" {
  description = "Whether the EKS API server is also reachable from the public internet. The private endpoint is always enabled regardless of this setting. Keep false unless you have a specific reason."
  type        = bool
  default     = false
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to reach the public EKS API endpoint. Only used when enable_public_eks_access is true."
  type        = list(string)
  default     = []
}

variable "cluster_log_retention_days" {
  description = "CloudWatch Logs retention, in days, for EKS control plane logs"
  type        = number
  default     = 30
}

variable "eks_admin_role_arns" {
  description = "IAM role ARNs granted cluster-admin access via EKS access entries. The caller applying Terraform is already granted admin automatically."
  type        = list(string)
  default     = []
}

variable "eks_developer_role_arns" {
  description = "IAM role ARNs granted namespaced edit access via EKS access entries"
  type        = list(string)
  default     = []
}

variable "system_node_instance_types" {
  description = "Instance types for the system managed node group (Knative/ingress controllers, monitoring, Karpenter itself)"
  type        = list(string)
  default     = ["m6i.large"]
}

variable "system_node_min_size" {
  description = "Minimum size of the system node group, kept at or above the AZ count for availability"
  type        = number
  default     = 3
}

variable "system_node_max_size" {
  description = "Maximum size of the system node group"
  type        = number
  default     = 6
}

variable "system_node_desired_size" {
  description = "Desired size of the system node group"
  type        = number
  default     = 3
}

variable "karpenter_instance_types" {
  description = "CPU-based EC2 instance types Karpenter is allowed to launch for application workloads"
  type        = list(string)
  default     = ["m6i.large", "m6i.xlarge", "m6a.large", "m6a.xlarge", "c6i.large", "c6i.xlarge"]
}

variable "karpenter_cpu_limit" {
  description = "Total vCPU ceiling across all nodes Karpenter provisions, to bound uncontrolled scale-out"
  type        = number
  default     = 64
}

variable "domain_name" {
  description = "Public domain name to expose the inference app on. Leave empty to keep the demo internal-only (no ACM cert, no public ALB)."
  type        = string
  default     = ""
}

variable "acm_certificate_arn" {
  description = "Existing ACM certificate ARN for the ALB listener. If empty and domain_name is set, a certificate is requested and must be validated manually before it is usable."
  type        = string
  default     = ""
}

variable "enable_public_ingress" {
  description = "Whether the ALB in front of Kourier/Knative gets an internet-facing scheme. False keeps the demo reachable only from inside the VPC (e.g. via port-forward or a bastion)."
  type        = bool
  default     = false
}

variable "enable_waf" {
  description = "Attach an AWS WAFv2 web ACL to the ALB. Only meaningful when enable_public_ingress is true."
  type        = bool
  default     = true
}
