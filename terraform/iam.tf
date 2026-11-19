data "aws_iam_policy_document" "pod_identity_assume" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

# Policy JSON is fetched by scripts/01-provision-infra.sh and committed to
# terraform/policies/ - review it before applying.
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
