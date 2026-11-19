#!/usr/bin/env bash
# Builds the FastAPI inference image and pushes it to ECR, creating the
# repository (with image scanning on push) if it doesn't exist yet.
#
# Usage: scripts/03-build-push-image.sh [tag]
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require aws
require docker

TAG="${1:-$(git -C "${ROOT_DIR}" rev-parse --short HEAD 2>/dev/null || date +%Y%m%d%H%M%S)}"
REPO_NAME="knative-serving-demo/iris-classifier"
REGION="$(aws configure get region)"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
IMAGE_URI="${REGISTRY}/${REPO_NAME}:${TAG}"

if ! aws ecr describe-repositories --repository-names "${REPO_NAME}" >/dev/null 2>&1; then
  echo "==> creating ECR repository ${REPO_NAME}"
  aws ecr create-repository \
    --repository-name "${REPO_NAME}" \
    --image-scanning-configuration scanOnPush=true \
    --encryption-configuration encryptionType=KMS \
    >/dev/null
fi

echo "==> docker login to ${REGISTRY}"
aws ecr get-login-password --region "${REGION}" | docker login --username AWS --password-stdin "${REGISTRY}"

echo "==> building ${IMAGE_URI}"
docker build --platform linux/amd64 -t "${IMAGE_URI}" "${ROOT_DIR}/app"

echo "==> pushing ${IMAGE_URI}"
docker push "${IMAGE_URI}"

echo "${IMAGE_URI}" > "${ROOT_DIR}/.last-image-uri"
echo "==> done: ${IMAGE_URI}"
echo "    (saved to .last-image-uri for scripts/05-deploy-app.sh)"
