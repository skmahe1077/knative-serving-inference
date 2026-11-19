#!/usr/bin/env bash
# Walks through the scale-to-zero demo: shows the revision scale down while
# idle, sends a request to trigger a cold start, then fires a burst of load
# to show scale-out. Reaches the service through a local port-forward to
# Kourier, so it works whether or not a public domain is configured.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require kubectl
require curl

HOST="$(kubectl get ksvc iris-classifier -n inference -o jsonpath='{.status.url}' | sed -E 's#https?://##')"
echo "==> service host: ${HOST}"

# No public domain configured (the internal-only default) means Knative's
# route only has a *.svc.cluster.local vhost, which Kourier only serves on
# its internal listener/Service - the external one 404s on that Host header.
# With a real domain configured, switch to svc/kourier instead.
KOURIER_SVC="kourier-internal"
case "${HOST}" in
  *.svc.cluster.local) KOURIER_SVC="kourier-internal" ;;
  *) KOURIER_SVC="kourier" ;;
esac

echo "==> current pods (expect this to reach 0 after ~30-60s idle):"
kubectl get pods -n inference -l serving.knative.dev/service=iris-classifier

echo "==> port-forwarding to ${KOURIER_SVC} on :8080 (ctrl-C when done)"
kubectl -n kourier-system port-forward "svc/${KOURIER_SVC}" 8080:80 >/tmp/kourier-port-forward.log 2>&1 &
PF_PID=$!
trap 'kill ${PF_PID} 2>/dev/null' EXIT
sleep 2

echo "==> watching pod count drop to zero (auto-continues once it does, or after ~2 min):"
for _ in $(seq 1 60); do
  COUNT="$(kubectl get pods -n inference -l serving.knative.dev/service=iris-classifier --no-headers 2>/dev/null | wc -l | tr -d ' ')"
  echo "  pods: ${COUNT}"
  [ "${COUNT}" = "0" ] && break
  sleep 2
done

echo "==> sending one request (cold start if scaled to zero):"
time curl -s -H "Host: ${HOST}" -X POST http://localhost:8080/predict \
  -H "Content-Type: application/json" \
  -d '{"features": [5.1, 3.5, 1.4, 0.2]}'
echo

echo "==> sending a burst of concurrent requests to trigger scale-out:"
# Kept well under 150: a single kubectl port-forward tunnel starts dropping
# connections above that under this much concurrency.
for _ in $(seq 1 60); do
  curl -s -o /dev/null -w "%{http_code}\n" -H "Host: ${HOST}" -X POST http://localhost:8080/predict \
    -H "Content-Type: application/json" -d '{"features": [6.3, 3.3, 6.0, 2.5]}' &
done
wait

echo "==> pods after the burst (watch Karpenter add nodes in Grafana):"
kubectl get pods -n inference -l serving.knative.dev/service=iris-classifier
