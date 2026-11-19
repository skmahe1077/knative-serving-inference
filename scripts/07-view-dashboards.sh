#!/usr/bin/env bash
# Port-forwards Grafana and prints the admin credentials.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require kubectl

echo "==> admin username: admin"
echo "==> admin password:"
kubectl -n monitoring get secret kube-prometheus-stack-grafana \
  -o jsonpath='{.data.admin-password}' | base64 -d
echo

echo "==> port-forwarding Grafana to http://localhost:3000 (Ctrl-C to stop)"
if command -v open >/dev/null 2>&1; then
  ( sleep 2 && open "http://localhost:3000/d/knative-scale-to-zero-demo" ) &
fi
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80
