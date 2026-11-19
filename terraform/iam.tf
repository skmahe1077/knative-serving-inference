# IAM for cluster add-ons that need AWS permissions, granted via EKS Pod Identity
# (no IRSA OIDC trust juggling, no static credentials on pods).

data "aws_iam_policy_document" "pod_identity_assume" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

# --- AWS Load Balancer Controller ---
#
# The IAM policy JSON is fetched by scripts/01-provision-infra.sh from the
# aws-load-balancer-controller repo, pinned to the chart version deployed in
# addons.tf, and committed to terraform/policies/. Review it before applying —
# it is a broad policy over ELB/EC2 resources, scoped at the resource-tag level
# by the controller itself at runtime, not by this IAM policy.
resource "aws_iam_role" "lb_controller" {
  name               = "${var.cluster_name}-lb-controller"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json
}

resource "aws_iam_role_policy" "lb_controller" {
  name   = "${var.cluster_name}-lb-controller"
  role   = aws_iam_role.lb_controller.id
  policy = file("${path.module}/policies/aws-load-balancer-controller-iam-policy.json")
}

resource "aws_eks_pod_identity_association" "lb_controller" {
  cluster_name    = module.eks.cluster_name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.lb_controller.arn

  depends_on = [module.eks]
}
