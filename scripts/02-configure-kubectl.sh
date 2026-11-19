#!/usr/bin/env bash
# Points your local kubectl at the cluster Terraform just created.
#
# The EKS API endpoint is private-only by default (see
# terraform/variables.tf enable_public_eks_access). You must run this, and
# every later script, from somewhere with network access to the VPC: a VPN,
# a Systems Manager port-forwarding session through a bastion/SSM-managed
# instance in a private subnet, or a Cloud9/EC2 box inside the VPC. See
# README.md "Accessing the private API endpoint".
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require aws
require kubectl

CLUSTER_NAME="$(tf_output cluster_name)"
REGION="$(tf_output aws_region)"

echo "==> aws eks update-kubeconfig --name ${CLUSTER_NAME}"
aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${REGION}"

echo "==> nodes:"
kubectl get nodes -o wide
