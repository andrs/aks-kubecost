#!/usr/bin/env bash
#
# Tests the Kubecost Allocation API by:
#   1. Detecting the correct service and port
#   2. Starting a port-forward in the background
#   3. Querying /model/allocation for strimzi namespace costs
#   4. Displaying the results as formatted JSON
#
# Usage:
#   chmod +x test-kubecost-api.sh
#   ./test-kubecost-api.sh
#
set -euo pipefail

NAMESPACE="kubecost"
LOCAL_PORT=9090
TARGET_NS="strimzi"
PF_PID=""

cleanup() {
  if [[ -n "${PF_PID}" ]]; then
    kill "${PF_PID}" 2>/dev/null || true
    wait "${PF_PID}" 2>/dev/null || true
    echo ""
    echo "==> Port-forward terminated."
  fi
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Step 1: Find the Kubecost frontend service
# ---------------------------------------------------------------------------
echo "==> Discovering Kubecost services in namespace '${NAMESPACE}'..."
kubectl get svc -n "${NAMESPACE}" -o wide

SVC_NAME=$(kubectl get svc -n "${NAMESPACE}" -l app.kubernetes.io/name=kubecost -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

if [[ -z "${SVC_NAME}" ]]; then
  SVC_NAME=$(kubectl get svc -n "${NAMESPACE}" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | grep -E "frontend|cost-analyzer" | head -1)
fi

if [[ -z "${SVC_NAME}" ]]; then
  echo "ERROR: Could not find Kubecost frontend service in namespace '${NAMESPACE}'."
  echo "Available services:"
  kubectl get svc -n "${NAMESPACE}"
  exit 1
fi

SVC_PORT=$(kubectl get svc "${SVC_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.ports[0].port}')
echo ""
echo "==> Found service: ${SVC_NAME} (port ${SVC_PORT})"

# ---------------------------------------------------------------------------
# Step 2: Start port-forward
# ---------------------------------------------------------------------------
echo "==> Starting port-forward: localhost:${LOCAL_PORT} → ${SVC_NAME}:${SVC_PORT}..."
kubectl port-forward "svc/${SVC_NAME}" "${LOCAL_PORT}:${SVC_PORT}" -n "${NAMESPACE}" &>/dev/null &
PF_PID=$!

echo "    Waiting for port-forward to be ready..."
for i in $(seq 1 30); do
  if curl -s -o /dev/null -w '' "http://localhost:${LOCAL_PORT}/" 2>/dev/null; then
    echo "    Port-forward ready (attempt ${i})."
    break
  fi
  if [[ ${i} -eq 30 ]]; then
    echo "    ERROR: Port-forward did not become ready in 30 seconds."
    echo "    Check that Kubecost pods are running:"
    kubectl get pods -n "${NAMESPACE}"
    exit 1
  fi
  sleep 1
done

BASE_URL="http://localhost:${LOCAL_PORT}"

# ---------------------------------------------------------------------------
# Step 3: Health check
# ---------------------------------------------------------------------------
echo ""
echo "==> Kubecost health check..."
HEALTH=$(curl -s "${BASE_URL}/healthz" 2>/dev/null || echo "endpoint not available")
echo "    /healthz: ${HEALTH}"

# ---------------------------------------------------------------------------
# Step 4: Query Allocation API — strimzi namespace (last 24h)
# ---------------------------------------------------------------------------
echo ""
echo "=============================================="
echo "  Allocation: strimzi namespace (last 24h)"
echo "=============================================="
echo ""

ALLOC_URL="${BASE_URL}/model/allocation?window=1d&aggregate=namespace&filterNamespaces=${TARGET_NS}&accumulate=true"
echo "  GET ${ALLOC_URL}"
echo ""

ALLOC_RESPONSE=$(curl -s "${ALLOC_URL}")

if echo "${ALLOC_RESPONSE}" | jq . &>/dev/null; then
  echo "${ALLOC_RESPONSE}" | jq '.'
  echo ""

  # Extract key cost metrics
  echo "----------------------------------------------"
  echo "  Cost Breakdown Summary"
  echo "----------------------------------------------"
  echo "${ALLOC_RESPONSE}" | jq -r '
    .data[0] // {} | to_entries[] | select(.key != "__idle__") |
    "  Namespace:     \(.key)",
    "  CPU Cost:      $\(.value.cpuCost // 0 | . * 100 | round / 100)",
    "  RAM Cost:      $\(.value.ramCost // 0 | . * 100 | round / 100)",
    "  PV Cost:       $\(.value.pvCost // 0 | . * 100 | round / 100)",
    "  Network Cost:  $\(.value.networkCost // 0 | . * 100 | round / 100)",
    "  LB Cost:       $\(.value.loadBalancerCost // 0 | . * 100 | round / 100)",
    "  Total Cost:    $\(.value.totalCost // 0 | . * 100 | round / 100)",
    "----------------------------------------------"
  ' 2>/dev/null || echo "  (Kubecost is still collecting data — costs will appear after ~15 minutes)"
else
  echo "  Response (raw): ${ALLOC_RESPONSE}"
fi

# ---------------------------------------------------------------------------
# Step 5: Query all namespaces for comparison
# ---------------------------------------------------------------------------
echo ""
echo "=============================================="
echo "  All Namespace Costs (last 24h)"
echo "=============================================="
echo ""

ALL_NS_URL="${BASE_URL}/model/allocation?window=1d&aggregate=namespace&accumulate=true"
ALL_RESPONSE=$(curl -s "${ALL_NS_URL}")

if echo "${ALL_RESPONSE}" | jq . &>/dev/null; then
  echo "${ALL_RESPONSE}" | jq -r '
    .data[0] // {} | to_entries | sort_by(-.value.totalCost) |
    .[] |
    "  \(.key): $\(.value.totalCost // 0 | . * 100 | round / 100)"
  ' 2>/dev/null || echo "  (Still collecting data...)"
else
  echo "  Response (raw): ${ALL_RESPONSE}"
fi

# ---------------------------------------------------------------------------
# Step 6: Query Assets API — show node costs
# ---------------------------------------------------------------------------
echo ""
echo "=============================================="
echo "  Assets: Node Costs (last 24h)"
echo "=============================================="
echo ""

ASSETS_URL="${BASE_URL}/model/assets?window=1d&aggregate=type&accumulate=true"
ASSETS_RESPONSE=$(curl -s "${ASSETS_URL}")

if echo "${ASSETS_RESPONSE}" | jq . &>/dev/null; then
  echo "${ASSETS_RESPONSE}" | jq -r '
    .data[0] // {} | to_entries | sort_by(-.value.totalCost) |
    .[] |
    "  \(.key): $\(.value.totalCost // 0 | . * 100 | round / 100)"
  ' 2>/dev/null || echo "  (Still collecting data...)"
else
  echo "  Response (raw): ${ASSETS_RESPONSE}"
fi

echo ""
echo "=============================================="
echo "  Test complete!"
echo "=============================================="
echo ""
echo "  Useful API endpoints:"
echo "    ${BASE_URL}/model/allocation?window=7d&aggregate=namespace"
echo "    ${BASE_URL}/model/allocation?window=7d&aggregate=label:app"
echo "    ${BASE_URL}/model/allocation?window=7d&aggregate=namespace&filterNamespaces=strimzi"
echo "    ${BASE_URL}/model/assets?window=7d&aggregate=type"
echo "    ${BASE_URL}/model/cloudCost?window=7d&aggregate=service"
echo ""
