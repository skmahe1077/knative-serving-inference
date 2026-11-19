# AWS Load Balancer Controller — provisions the ALB in front of Kourier from
# Kubernetes Ingress/Service objects (see k8s_manifests/).
resource "helm_release" "aws_load_balancer_controller" {
  name      = "aws-load-balancer-controller"
  namespace = "kube-system"

  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.11.0"

  values = [
    yamlencode({
      clusterName = module.eks.cluster_name
      vpcId       = module.vpc.vpc_id
      region      = var.aws_region
      serviceAccount = {
        create = true
        name   = "aws-load-balancer-controller"
      }
      replicaCount = 2
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

  depends_on = [module.eks, aws_eks_pod_identity_association.lb_controller]
}

# --- Optional public TLS exposure (controlled by var.domain_name) ---
#
# Requesting this certificate does not make it usable: DNS validation records
# must be created and to propagate before ACM issues it. Leave domain_name
# empty for the internal-only demo path.
resource "aws_acm_certificate" "app" {
  count = var.domain_name != "" && var.acm_certificate_arn == "" ? 1 : 0

  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# --- Optional WAF in front of a publicly exposed ALB ---
#
# Attaching this to the ALB is a manual step: the ALB is created by the AWS
# Load Balancer Controller from a Kubernetes Ingress, so its ARN only exists
# after that Ingress is applied. Associate it with:
#   aws wafv2 associate-web-acl --web-acl-arn <waf_web_acl_arn output> --resource-arn <alb-arn>
resource "aws_wafv2_web_acl" "app" {
  count = var.enable_public_ingress && var.enable_waf ? 1 : 0

  name  = "${var.cluster_name}-app"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "aws-common-rule-set"
    priority = 0

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "common-rule-set"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "rate-limit"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "rate-limit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.cluster_name}-app"
    sampled_requests_enabled   = true
  }
}
