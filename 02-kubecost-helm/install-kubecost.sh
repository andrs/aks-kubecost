#!/usr/bin/env bash
#
# Deploys Kubecost 3.x to AKS via Helm.
#
# Prerequisites:
#   - kubectl configured and pointing to the target AKS cluster
#   - Namespace 'kubecost' exists
#   - Secret 'cloud-integration' created in kubecost namespace (for Azure billing)
#
# Usage:
#   chmod +x install-kubecost.sh
#   ./install-kubecost.sh
#
set -euo pipefail

NAMESPACE="kubecost"
RELEASE_NAME="kubecost"
CHART_REPO_NAME="kubecost"
CHART_REPO_URL="https://kubecost.github.io/kubecost/"
CHART="${CHART_REPO_NAME}/kubecost"
VALUES_FILE="$(dirname "$0")/values-aks-production.yaml"

echo "==> Adding Kubecost 3.x Helm repository..."
helm repo add "${CHART_REPO_NAME}" "${CHART_REPO_URL}" 2>/dev/null || true
helm repo update "${CHART_REPO_NAME}"

echo ""
echo "==> Available chart versions:"
helm search repo "${CHART}" --versions | head -5

echo ""
echo "==> Pre-flight checks..."

if ! kubectl get namespace "${NAMESPACE}" &>/dev/null; then
  echo "    ERROR: Namespace '${NAMESPACE}' does not exist."
  echo "    Run: kubectl apply -f ../01-prerequisites/00-namespace.yaml"
  exit 1
fi

if ! kubectl get secret cloud-integration -n "${NAMESPACE}" &>/dev/null; then
  echo "    WARNING: Secret 'cloud-integration' not found in '${NAMESPACE}'."
  echo "    Azure out-of-cluster cost data will not be available."
  echo "    Continuing with deployment..."
fi

echo ""
echo "==> Installing Kubecost 3.x..."
helm upgrade --install "${RELEASE_NAME}" "${CHART}" \
  --namespace "${NAMESPACE}" \
  --values "${VALUES_FILE}" \
  --wait \
  --timeout 10m

echo ""
echo "==> Verifying deployment..."
echo "Pods:"
kubectl get pods -n "${NAMESPACE}" -o wide
echo ""
echo "Services:"
kubectl get svc -n "${NAMESPACE}"
echo ""
echo "PVCs:"
kubectl get pvc -n "${NAMESPACE}"

echo ""
echo "================================================================"
echo "  Kubecost 3.x deployed successfully!"
echo "================================================================"
echo ""
echo "  Architecture:"
echo "    - Frontend:     UI on port 9090"
echo "    - Aggregator:   ClickHouse analytics engine"
echo "    - LocalStore:   Agent ↔ Aggregator buffer"
echo "    - CloudCost:    Azure billing processor"
echo "    - NetworkCosts: DaemonSet for traffic attribution"
echo "    - FinOps Agent: Direct metrics collector (no Prometheus)"
echo ""
echo "  Quick access (port-forward):"
echo "    kubectl port-forward -n kubecost svc/kubecost-frontend 9090:9090"
echo "    Open: http://localhost:9090"
echo ""
echo "  API:"
echo "    curl http://localhost:9090/model/allocation?window=1d&aggregate=namespace"
echo "================================================================"
