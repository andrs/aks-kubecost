#!/usr/bin/env bash
#
# Deploys the Gateway resource for Kubecost.
# The HTTPRoute is managed by the Helm chart's httpRoute section.
#
# Prerequisites:
#   - Envoy Gateway (GatewayClass 'eg') installed in the cluster
#   - Kubecost namespace exists
#
set -euo pipefail

SCRIPT_DIR="$(dirname "$0")"

echo "==> Checking for Envoy Gateway GatewayClass..."
if ! kubectl get gatewayclass eg &>/dev/null; then
  echo "    WARNING: GatewayClass 'eg' not found."
  echo "    Install Envoy Gateway first, or update gateway.yaml with your GatewayClass name."
fi

echo "==> Applying Gateway resource..."
kubectl apply -f "${SCRIPT_DIR}/gateway.yaml"

echo ""
echo "==> Gateway status:"
kubectl get gateway -n kubecost

echo ""
echo "==> HTTPRoute status (created by Helm chart):"
kubectl get httproute -n kubecost 2>/dev/null || echo "    (HTTPRoute will appear after Helm install)"

echo ""
echo "==> To get the external IP/hostname:"
echo "    kubectl get gateway kubecost-gateway -n kubecost -o jsonpath='{.status.addresses[0].value}'"
echo ""
echo "    Then point kubecost.aks.mydomain.com DNS to that address."
