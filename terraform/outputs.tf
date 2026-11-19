output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "aws_region" {
  description = "AWS region the cluster was deployed into"
  value       = var.aws_region
}

output "cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  value     = module.eks.cluster_certificate_authority_data
  sensitive = true
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "private_subnet_ids" {
  value = module.vpc.private_subnets
}

output "public_subnet_ids" {
  value = module.vpc.public_subnets
}

output "configure_kubectl" {
  description = "Command to point local kubectl at this cluster (also run by scripts/02-configure-kubectl.sh)"
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}"
}

output "eks_kms_key_arn" {
  description = "KMS key used for EKS secrets envelope encryption"
  value       = aws_kms_key.eks.arn
}

output "karpenter_queue_name" {
  description = "SQS queue Karpenter uses for spot interruption / rebalance notifications"
  value       = module.karpenter.queue_name
}

output "waf_web_acl_arn" {
  description = "WAFv2 web ACL ARN to reference from the Ingress annotation, when enabled"
  value       = var.enable_public_ingress && var.enable_waf ? aws_wafv2_web_acl.app[0].arn : null
}

output "acm_certificate_arn" {
  description = "ACM certificate ARN to use for the ALB HTTPS listener, when a domain is configured"
  value       = var.domain_name != "" ? (var.acm_certificate_arn != "" ? var.acm_certificate_arn : aws_acm_certificate.app[0].arn) : null
}
