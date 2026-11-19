#!/usr/bin/env bash
# Provisions VPC, EKS, Karpenter, and the LB controller IAM role.
# Requires TF_STATE_BUCKET, TF_STATE_REGION; optional TF_LOCK_TABLE.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require terraform
require curl
require helm
require aws

: "${TF_STATE_BUCKET:?set TF_STATE_BUCKET to your Terraform state bucket}"
: "${TF_STATE_REGION:?set TF_STATE_REGION to the state bucket region}"

POLICY_FILE="${TERRAFORM_DIR}/policies/aws-load-balancer-controller-iam-policy.json"
LBC_VERSION="v2.11.0" # keep in sync with the chart version in terraform/addons.tf

echo "==> fetching AWS Load Balancer Controller IAM policy (${LBC_VERSION})"
curl -fsSL -o "${POLICY_FILE}" \
  "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/${LBC_VERSION}/docs/install/iam_policy.json"
echo "    review it before continuing: ${POLICY_FILE}"

# anonymous pulls from public.ecr.aws get a 403 without this
echo "==> authenticating helm to public.ecr.aws (karpenter chart)"
aws ecr-public get-login-password --region us-east-1 | helm registry login --username AWS --password-stdin public.ecr.aws

BACKEND_ARGS=(
  -backend-config="bucket=${TF_STATE_BUCKET}"
  -backend-config="key=knative-serving/terraform.tfstate"
  -backend-config="region=${TF_STATE_REGION}"
)
if [[ -n "${TF_LOCK_TABLE:-}" ]]; then
  BACKEND_ARGS+=(-backend-config="dynamodb_table=${TF_LOCK_TABLE}")
else
  BACKEND_ARGS+=(-backend-config="use_lockfile=true") # Terraform >= 1.10 native S3 locking
fi

echo "==> terraform init"
terraform -chdir="${TERRAFORM_DIR}" init "${BACKEND_ARGS[@]}"

echo "==> terraform plan"
terraform -chdir="${TERRAFORM_DIR}" plan -out=tfplan

echo "==> terraform apply"
terraform -chdir="${TERRAFORM_DIR}" apply tfplan
rm -f "${TERRAFORM_DIR}/tfplan"

echo "==> done. Next: scripts/02-configure-kubectl.sh"
