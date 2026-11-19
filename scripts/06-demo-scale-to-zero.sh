#!/usr/bin/env bash
# Scale-to-zero demo. Prints each command before running it, and pauses for
# enter, so the audience sees exactly what's happening against Knative.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require kubectl
require curl

show() {
  echo
  echo "\$ $1"
  read -r -p "press enter to run this..." _
}

HOST="$(kubectl get ksvc iris-classifier -n inference -o jsonpath='{.status.url}' | sed -E 's#https?://##')"

# No public domain -> cluster-local host -> use kourier-internal, not kourier.
KOURIER_SVC="kourier-internal"
case "${HOST}" in
  *.svc.cluster.local) KOURIER_SVC="kourier-internal" ;;
  *) KOURIER_SVC="kourier" ;;
esac

show "kubectl -n kourier-system port-forward svc/${KOURIER_SVC} 8080:80"
kubectl -n kourier-system port-forward "svc/${KOURIER_SVC}" 8080:80 >/tmp/kourier-port-forward.log 2>&1 &
PF_PID=$!
trap 'kill ${PF_PID} 2>/dev/null' EXIT
sleep 2

# Make sure a pod is running first so the audience can watch it scale down.
COUNT="$(kubectl get pods -n inference -l serving.knative.dev/service=iris-classifier --no-headers 2>/dev/null | wc -l | tr -d ' ')"
if [ "${COUNT}" = "0" ]; then
  show "curl -H 'Host: ${HOST}' -X POST http://localhost:8080/predict -d '{\"features\": [5.1, 3.5, 1.4, 0.2]}'"
  curl -s -o /dev/null -H "Host: ${HOST}" -X POST http://localhost:8080/predict \
    -H "Content-Type: application/json" -d '{"features": [5.1, 3.5, 1.4, 0.2]}'
fi

show "kubectl get pods -n inference -l serving.knative.dev/service=iris-classifier"
kubectl get pods -n inference -l serving.knative.dev/service=iris-classifier

POD="$(kubectl get pods -n inference -l serving.knative.dev/service=iris-classifier -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)"
if [ -n "${POD}" ]; then
  show "kubectl describe pod -n inference ${POD}"
  kubectl describe pod -n inference "${POD}"
fi

show "watch -n2 kubectl get pods -n inference -l serving.knative.dev/service=iris-classifier   # until it scales to zero"
for _ in $(seq 1 60); do
  OUT="$(kubectl get pods -n inference -l serving.knative.dev/service=iris-classifier --no-headers 2>/dev/null)"
  if [ -z "${OUT}" ]; then
    echo "pods: 0"
    break
  fi
  echo "${OUT}"
  sleep 2
done

show "curl -H 'Host: ${HOST}' -X POST http://localhost:8080/predict -d '{\"features\": [5.1, 3.5, 1.4, 0.2]}'   # cold start"
time curl -s -H "Host: ${HOST}" -X POST http://localhost:8080/predict \
  -H "Content-Type: application/json" \
  -d '{"features": [5.1, 3.5, 1.4, 0.2]}'
echo

show "kubectl get pods -n inference -l serving.knative.dev/service=iris-classifier"
kubectl get pods -n inference -l serving.knative.dev/service=iris-classifier

show "for i in {1..60}; do curl -H 'Host: ${HOST}' ... & done; wait   # burst to trigger scale-out"
for _ in $(seq 1 60); do
  curl -s -o /dev/null -w "%{http_code}\n" -H "Host: ${HOST}" -X POST http://localhost:8080/predict \
    -H "Content-Type: application/json" -d '{"features": [6.3, 3.3, 6.0, 2.5]}' &
done
wait

show "kubectl get pods -n inference -l serving.knative.dev/service=iris-classifier"
kubectl get pods -n inference -l serving.knative.dev/service=iris-classifier
