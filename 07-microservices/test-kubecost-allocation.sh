#!/usr/bin/env bash
#
# Tests Kubecost cost allocation and right-sizing for the ecommerce-demo namespace.
#
# This script:
#   1. Stress-tests service-orders to generate measurable CPU/RAM usage
#   2. Queries Kubecost Allocation API for the ecommerce-demo namespace
#   3. Queries Kubecost Right-Sizing API for service-payments recommendations
#   4. Compares efficiency between the two services
#
set -euo pipefail

KUBECOST_NS="kubecost"
KUBECOST_SVC="kubecost-frontend"
KUBECOST_PORT=9090
ORDERS_NS="ecommerce-demo"
ORDERS_SVC="service-orders"
ORDERS_PORT=8081
PIDS=()

cleanup() {
  for pid in "${PIDS[@]}"; do
    kill "${pid}" 2>/dev/null || true
  done
  wait 2>/dev/null || true
  echo ""
  echo "==> Port-forwards terminated."
}
trap cleanup EXIT

echo "=============================================="
echo "  Kubecost FinOps Allocation Test"
echo "  $(date -Iseconds)"
echo "=============================================="

# ------------------------------------------------------------------
# Step 0: Port-forwards
# ------------------------------------------------------------------
echo ""
echo "==> Setting up port-forwards..."

# Kill any existing port-forwards on these ports
lsof -ti:${KUBECOST_PORT} 2>/dev/null | xargs kill -9 2>/dev/null || true
lsof -ti:${ORDERS_PORT} 2>/dev/null | xargs kill -9 2>/dev/null || true
sleep 1

kubectl port-forward -n "${KUBECOST_NS}" "svc/${KUBECOST_SVC}" ${KUBECOST_PORT}:9090 &>/dev/null &
PIDS+=($!)

kubectl port-forward -n "${ORDERS_NS}" "svc/${ORDERS_SVC}" ${ORDERS_PORT}:80 &>/dev/null &
PIDS+=($!)

echo "    Waiting for port-forwards..."
sleep 5

# Verify connectivity
for url in "http://localhost:${KUBECOST_PORT}/healthz" "http://localhost:${ORDERS_PORT}/health"; do
  if curl -sf -o /dev/null "${url}" 2>/dev/null; then
    echo "    OK: ${url}"
  else
    echo "    FAIL: ${url} — check that pods are running"
  fi
done

# ------------------------------------------------------------------
# Step 1: Generate CPU/RAM load on service-orders
# ------------------------------------------------------------------
echo ""
echo "=============================================="
echo "  Step 1: Stress Test — service-orders"
echo "=============================================="
echo ""
echo "  Triggering /stress?duration=30&threads=2&mem_mb=50"
echo "  This burns CPU for 30s across 2 threads and allocates 50MB RAM."
echo ""

STRESS_RESULT=$(curl -sf "http://localhost:${ORDERS_PORT}/stress?duration=30&threads=2&mem_mb=50" 2>/dev/null || echo '{"error": "stress endpoint unreachable"}')
echo "  Result: ${STRESS_RESULT}" | jq . 2>/dev/null || echo "  ${STRESS_RESULT}"

echo ""
echo "  Waiting 30s for Kubecost to pick up the usage spike..."
sleep 30

# ------------------------------------------------------------------
# Step 2: Kubecost Allocation — by namespace
# ------------------------------------------------------------------
echo ""
echo "=============================================="
echo "  Step 2: Cost Allocation — ecommerce-demo"
echo "=============================================="
echo ""

ALLOC_NS=$(curl -sf "http://localhost:${KUBECOST_PORT}/model/allocation?window=1d&aggregate=namespace&filterNamespaces=ecommerce-demo&accumulate=true" 2>/dev/null)

if echo "${ALLOC_NS}" | jq -e '.data[0]' &>/dev/null; then
  echo "${ALLOC_NS}" | jq -r '
    .data[0] | to_entries[] |
    "  Namespace:      \(.key)",
    "  CPU Cost:       $\(.value.cpuCost // 0 | . * 100 | round / 100)",
    "  RAM Cost:       $\(.value.ramCost // 0 | . * 100 | round / 100)",
    "  PV Cost:        $\(.value.pvCost // 0 | . * 100 | round / 100)",
    "  Network Cost:   $\(.value.networkCost // 0 | . * 100 | round / 100)",
    "  Total Cost:     $\(.value.totalCost // 0 | . * 100 | round / 100)",
    "  Efficiency:     \(.value.totalEfficiency // 0 | . * 10000 | round / 100)%",
    ""
  '
else
  echo "  (Kubecost is still collecting data — try again in 15 minutes)"
  echo "  Raw response:"
  echo "${ALLOC_NS}" | jq . 2>/dev/null || echo "  ${ALLOC_NS}"
fi

# ------------------------------------------------------------------
# Step 3: Kubecost Allocation — by cost-center label
# ------------------------------------------------------------------
echo ""
echo "=============================================="
echo "  Step 3: Cost Allocation — by cost-center label"
echo "=============================================="
echo ""

ALLOC_LABEL=$(curl -sf "http://localhost:${KUBECOST_PORT}/model/allocation?window=1d&aggregate=label:cost-center&accumulate=true" 2>/dev/null)

if echo "${ALLOC_LABEL}" | jq -e '.data[0]' &>/dev/null; then
  echo "${ALLOC_LABEL}" | jq -r '
    .data[0] | to_entries | sort_by(-.value.totalCost) | .[] |
    "  Cost Center:    \(.key)",
    "  Total Cost:     $\(.value.totalCost // 0 | . * 100 | round / 100)",
    "  CPU Cost:       $\(.value.cpuCost // 0 | . * 100 | round / 100)",
    "  RAM Cost:       $\(.value.ramCost // 0 | . * 100 | round / 100)",
    "  Efficiency:     \(.value.totalEfficiency // 0 | . * 10000 | round / 100)%",
    ""
  '
else
  echo "  (Still collecting data...)"
fi

# ------------------------------------------------------------------
# Step 4: Per-controller breakdown (orders vs payments)
# ------------------------------------------------------------------
echo ""
echo "=============================================="
echo "  Step 4: Per-Controller Cost Comparison"
echo "=============================================="
echo ""

ALLOC_CTRL=$(curl -sf "http://localhost:${KUBECOST_PORT}/model/allocation?window=1d&aggregate=controller&filterNamespaces=ecommerce-demo&accumulate=true" 2>/dev/null)

if echo "${ALLOC_CTRL}" | jq -e '.data[0]' &>/dev/null; then
  echo "  Controller              | Total Cost | CPU Cost  | RAM Cost  | Efficiency"
  echo "  ------------------------|------------|-----------|-----------|----------"
  echo "${ALLOC_CTRL}" | jq -r '
    .data[0] | to_entries | sort_by(.key) | .[] |
    "  \(.key | .[0:24] | . + " " * (24 - length))| $\(.value.totalCost // 0 | . * 100 | round / 100 | tostring | . + " " * (9 - length))| $\(.value.cpuCost // 0 | . * 100 | round / 100 | tostring | . + " " * (8 - length))| $\(.value.ramCost // 0 | . * 100 | round / 100 | tostring | . + " " * (8 - length))| \(.value.totalEfficiency // 0 | . * 10000 | round / 100)%"
  ' 2>/dev/null || echo "  (jq formatting issue — raw data follows)"
  echo ""
  echo "  NOTE: service-payments should show LOWER efficiency than service-orders"
  echo "  because it has higher resource requests but near-zero actual usage."
else
  echo "  (Still collecting data...)"
fi

# ------------------------------------------------------------------
# Step 5: Right-Sizing Recommendations
# ------------------------------------------------------------------
echo ""
echo "=============================================="
echo "  Step 5: Right-Sizing Recommendations"
echo "=============================================="
echo ""

RIGHTSIZING=$(curl -sf "http://localhost:${KUBECOST_PORT}/model/savings/requestSizingV2?window=1d&filterNamespaces=ecommerce-demo&targetCPUUtilization=0.7&targetRAMUtilization=0.7" 2>/dev/null)

if echo "${RIGHTSIZING}" | jq -e '.' &>/dev/null; then
  echo "${RIGHTSIZING}" | jq -r '
    if type == "array" then .[]
    elif .data then .data[]
    else .
    end |
    if .containerName then
      "  Container:              \(.controllerName // "unknown")/\(.containerName)",
      "  Current CPU Request:    \(.currentCPURequest // "n/a")",
      "  Recommended CPU:        \(.recommendedCPURequest // "n/a")",
      "  Current RAM Request:    \(.currentRAMRequest // "n/a")",
      "  Recommended RAM:        \(.recommendedRAMRequest // "n/a")",
      "  Monthly Savings:        $\(.monthlySavings // 0 | . * 100 | round / 100)",
      ""
    else
      "  (Unexpected response format — showing raw)"
    end
  ' 2>/dev/null || echo "${RIGHTSIZING}" | jq '.' 2>/dev/null || echo "  ${RIGHTSIZING}"
  echo ""
  echo "  service-payments SHOULD show recommendations to reduce CPU and RAM"
  echo "  since it requests 150m CPU / 200Mi RAM but uses almost nothing."
else
  echo "  (Right-sizing data not yet available — needs ~1 hour of metrics)"
  echo "  Raw: ${RIGHTSIZING}"
fi

# ------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------
echo ""
echo "=============================================="
echo "  Test Complete — Dashboard Validation Steps"
echo "=============================================="
echo ""
echo "  Open Kubecost UI: http://localhost:${KUBECOST_PORT}"
echo ""
echo "  1. COST ALLOCATION"
echo "     → Allocations → Aggregate by 'Namespace'"
echo "     → Find 'ecommerce-demo' → Click to drill down"
echo "     → Switch aggregate to 'Controller' to see orders vs payments"
echo ""
echo "  2. COST CENTER VIEW"
echo "     → Allocations → Aggregate by 'Label' → Select 'cost-center'"
echo "     → Find 'digital-storefront' → See combined ecommerce costs"
echo ""
echo "  3. EFFICIENCY COMPARISON"
echo "     → Allocations → Aggregate by 'Controller'"
echo "     → Filter: namespace = ecommerce-demo"
echo "     → Compare the 'Efficiency' column:"
echo "        service-orders  → HIGH efficiency (tight requests, real usage)"
echo "        service-payments → LOW efficiency (overprovisioned, idle)"
echo ""
echo "  4. RIGHT-SIZING RECOMMENDATIONS"
echo "     → Savings → Request Right-Sizing"
echo "     → Look for service-payments containers"
echo "     → Kubecost recommends reducing CPU from 150m and RAM from 200Mi"
echo ""
echo "  5. IDLE COST"
echo "     → Allocations → Toggle 'Show Idle' ON"
echo "     → service-payments will show high idle cost (requested but unused)"
echo "     → service-orders will show lower idle cost (requests match usage)"
echo ""
