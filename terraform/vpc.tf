module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.19.0"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr

  azs             = var.availability_zones
  public_subnets  = [for i, az in var.availability_zones : cidrsubnet(var.vpc_cidr, 4, i)]
  private_subnets = [for i, az in var.availability_zones : cidrsubnet(var.vpc_cidr, 4, i + 3)]

  enable_nat_gateway     = true
  one_nat_gateway_per_az = true
  single_nat_gateway     = false

  enable_dns_hostnames = true
  enable_dns_support   = true

  # Worker nodes never get a public IP; they reach the internet only via NAT.
  map_public_ip_on_launch = false

  # Required for AWS-managed load balancers (ALB/NLB) and Karpenter to discover subnets.
  public_subnet_tags = {
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "karpenter.sh/discovery"                    = var.cluster_name
  }

  enable_flow_log                                 = true
  create_flow_log_cloudwatch_log_group            = true
  create_flow_log_cloudwatch_iam_role             = true
  flow_log_cloudwatch_log_group_retention_in_days = var.cluster_log_retention_days
}

# Gateway endpoint for S3 — ECR image layers and Terraform state traffic stay off the
# public internet and incur no hourly/data charge.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = concat(module.vpc.private_route_table_ids, module.vpc.public_route_table_ids)
}

resource "aws_security_group" "vpc_endpoints" {
  name_prefix = "${var.cluster_name}-vpce-"
  description = "Allow in-VPC traffic to interface VPC endpoints"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTPS from inside the VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # No egress rule: interface endpoint ENIs only ever receive connections,
  # they never initiate outbound traffic themselves.

  tags = { Name = "${var.cluster_name}-vpce" }
}

# Interface endpoints so nodes in private subnets can reach ECR, STS, CloudWatch Logs
# and the EC2/ELB APIs (used by Karpenter and the AWS Load Balancer Controller) without
# going through the NAT gateways.
locals {
  interface_endpoint_services = [
    "ecr.api",
    "ecr.dkr",
    "sts",
    "logs",
    "ec2",
    "elasticloadbalancing",
  ]
}

resource "aws_vpc_endpoint" "interface" {
  for_each = toset(local.interface_endpoint_services)

  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
}
