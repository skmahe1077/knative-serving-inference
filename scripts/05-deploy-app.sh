#!/usr/bin/env bash
# Deploys the inference app as a Knative Service.
#
# Usage: scripts/05-deploy-app.sh [demo|production] [image-uri]
#   profile defaults to "demo"
#   image-uri defaults to the value saved by scripts/03-build-push-image.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require kubectl

PROFILE="${1:-demo}"
case "${PROFILE}" in
  demo|production) ;;
  *) echo "profile must be 'demo' or 'production', got: ${PROFILE}" >&2; exit 1 ;;
esac

IMAGE_URI="${2:-$(cat "${ROOT_DIR}/.last-image-uri" 2>/dev/null || true)}"
: "${IMAGE_URI:?no image URI given and .last-image-uri not found; run scripts/03-build-push-image.sh first}"

echo "==> applying namespace, network policy and service monitor"
kubectl apply -f "${ROOT_DIR}/k8s_manifests/namespace.yaml"
kubectl apply -f "${ROOT_DIR}/k8s_manifests/network-policy.yaml"
kubectl apply -f "${ROOT_DIR}/k8s_manifests/servicemonitor-inference.yaml"

MANIFEST="${ROOT_DIR}/k8s_manifests/knative-service-${PROFILE}.yaml"
echo "==> deploying ${PROFILE} profile with image ${IMAGE_URI}"
sed "s|IMAGE_URI_PLACEHOLDER|${IMAGE_URI}|" "${MANIFEST}" | kubectl apply -f -

echo "==> waiting for the revision to become ready"
kubectl wait --for=condition=Ready --timeout=180s ksvc/iris-classifier -n inference

kubectl get ksvc iris-classifier -n inference
