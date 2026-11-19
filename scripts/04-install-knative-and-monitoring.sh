#!/usr/bin/env bash
# Installs Knative Serving, Kourier, and kube-prometheus-stack.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require kubectl
require helm

KNATIVE_VERSION="v1.16.0"
KOURIER_VERSION="v1.16.0"
PROMETHEUS_CHART_VERSION="66.3.1"

SYSTEM_TOLERATION='[{"key":"node-role","operator":"Equal","value":"system","effect":"NoSchedule"}]'
SYSTEM_NODE_SELECTOR='{"node-role":"system"}'

echo "==> installing Knative Serving CRDs + core (${KNATIVE_VERSION})"
kubectl apply -f "https://github.com/knative/serving/releases/download/knative-${KNATIVE_VERSION}/serving-crds.yaml"
kubectl apply -f "https://github.com/knative/serving/releases/download/knative-${KNATIVE_VERSION}/serving-core.yaml"

echo "==> installing Kourier (${KOURIER_VERSION})"
kubectl apply -f "https://github.com/knative/net-kourier/releases/download/knative-${KOURIER_VERSION}/kourier.yaml"

kubectl patch configmap/config-network \
  -n knative-serving \
  --type merge \
  -p '{"data":{"ingress-class":"kourier.ingress.networking.knative.dev"}}'

echo "==> pinning Knative/Kourier control plane to the system node pool"
for ns_deploy in \
  "knative-serving/activator" "knative-serving/autoscaler" "knative-serving/controller" \
  "knative-serving/net-kourier-controller" "knative-serving/webhook" \
  "kourier-system/3scale-kourier-gateway" "kourier-system/3scale-kourier-control"; do
  ns="${ns_deploy%%/*}"; deploy="${ns_deploy##*/}"
  kubectl patch deployment "${deploy}" -n "${ns}" --type merge -p \
    "{\"spec\":{\"template\":{\"spec\":{\"tolerations\":${SYSTEM_TOLERATION},\"nodeSelector\":${SYSTEM_NODE_SELECTOR}}}}}" \
    2>/dev/null || echo "    (skipping ${ns_deploy}, not found in this release)"
done

echo "==> waiting for Knative/Kourier to be ready"
kubectl wait --for=condition=Available --timeout=300s deployment --all -n knative-serving
kubectl wait --for=condition=Available --timeout=300s deployment --all -n kourier-system

echo "==> installing kube-prometheus-stack (${PROMETHEUS_CHART_VERSION})"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
helm repo update prometheus-community >/dev/null
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --version "${PROMETHEUS_CHART_VERSION}" \
  --namespace monitoring --create-namespace \
  -f "${ROOT_DIR}/monitoring/prometheus-values.yaml" \
  --wait --timeout 10m

echo "==> loading the demo Grafana dashboard"
kubectl apply -f "${ROOT_DIR}/k8s_manifests/grafana-dashboard-demo-configmap.yaml"

echo "==> done. Next: scripts/05-deploy-app.sh"
