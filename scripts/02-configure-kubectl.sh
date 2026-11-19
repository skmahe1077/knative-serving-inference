#!/usr/bin/env bash
# Points kubectl at the cluster. Needs network access to the private
# endpoint (VPN or SSM bastion) unless enable_public_eks_access is set.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require aws
require kubectl

CLUSTER_NAME="$(tf_output cluster_name)"
REGION="$(tf_output aws_region)"

echo "==> aws eks update-kubeconfig --name ${CLUSTER_NAME}"
aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${REGION}"

echo "==> nodes:"
kubectl get nodes -o wide
