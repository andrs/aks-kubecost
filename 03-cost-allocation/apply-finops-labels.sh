#!/usr/bin/env bash
#
# Applies FinOps cost-allocation labels to the Strimzi Kafka resources.
#
# Kubecost uses Kubernetes labels on namespaces, pods, and controllers
# for cost aggregation. The labelMappingConfigs in values.yaml maps these
# labels to Kubecost's allocation dimensions (owner, team, product, etc.).
#
# With these labels:
#   - The Kubecost UI groups costs under "data-platform" cost center
#   - Allocation reports can filter by app=kafka, environment=production
#   - Chargeback reports attribute Kafka costs to the correct business unit
#
# Usage:
#   chmod +x apply-finops-labels.sh
#   ./apply-finops-labels.sh
#
set -euo pipefail

STRIMZI_NS="strimzi"

echo "=============================================="
echo "  FinOps Cost Allocation Labeling"
echo "=============================================="

# ---------------------------------------------------------------------------
# Step 1: Label the strimzi namespace
# ---------------------------------------------------------------------------
echo ""
echo "==> Labeling namespace '${STRIMZI_NS}'..."

kubectl label namespace "${STRIMZI_NS}" \
  cost-center=data-platform \
  environment=production \
  app=kafka \
  team=data-engineering \
  owner=platform-team \
  department=engineering \
  --overwrite

echo "    Namespace labels applied:"
kubectl get namespace "${STRIMZI_NS}" --show-labels

# ---------------------------------------------------------------------------
# Step 2: Label Kafka broker StatefulSets
# ---------------------------------------------------------------------------
echo ""
echo "==> Labeling Kafka broker StatefulSets..."

for sts in $(kubectl get statefulsets -n "${STRIMZI_NS}" -l strimzi.io/kind=Kafka -o name 2>/dev/null); do
  echo "    Labeling ${sts}..."
  kubectl label "${sts}" -n "${STRIMZI_NS}" \
    cost-center=data-platform \
    environment=production \
    app=kafka \
    component=broker \
    team=data-engineering \
    owner=platform-team \
    --overwrite
done

# Also label by component name pattern (pools, nodepools)
for sts in $(kubectl get statefulsets -n "${STRIMZI_NS}" -o name 2>/dev/null); do
  echo "    Labeling ${sts}..."
  kubectl label "${sts}" -n "${STRIMZI_NS}" \
    cost-center=data-platform \
    environment=production \
    app=kafka \
    team=data-engineering \
    owner=platform-team \
    --overwrite
done

# ---------------------------------------------------------------------------
# Step 3: Label ZooKeeper StatefulSets (if present)
# ---------------------------------------------------------------------------
echo ""
echo "==> Labeling ZooKeeper StatefulSets (if present)..."

for sts in $(kubectl get statefulsets -n "${STRIMZI_NS}" -l strimzi.io/kind=Kafka -o name 2>/dev/null | grep -i zookeeper || true); do
  echo "    Labeling ${sts}..."
  kubectl label "${sts}" -n "${STRIMZI_NS}" \
    cost-center=data-platform \
    environment=production \
    app=kafka \
    component=zookeeper \
    team=data-engineering \
    owner=platform-team \
    --overwrite
done

# ---------------------------------------------------------------------------
# Step 4: Label Kafka Connect, MirrorMaker, Bridge deployments (if present)
# ---------------------------------------------------------------------------
echo ""
echo "==> Labeling additional Strimzi components..."

for deploy in $(kubectl get deployments -n "${STRIMZI_NS}" -o name 2>/dev/null); do
  echo "    Labeling ${deploy}..."
  kubectl label "${deploy}" -n "${STRIMZI_NS}" \
    cost-center=data-platform \
    environment=production \
    app=kafka \
    team=data-engineering \
    owner=platform-team \
    --overwrite
done

# ---------------------------------------------------------------------------
# Step 5: Label PVCs for storage cost attribution
# ---------------------------------------------------------------------------
echo ""
echo "==> Labeling PersistentVolumeClaims..."

for pvc in $(kubectl get pvc -n "${STRIMZI_NS}" -o name 2>/dev/null); do
  echo "    Labeling ${pvc}..."
  kubectl label "${pvc}" -n "${STRIMZI_NS}" \
    cost-center=data-platform \
    environment=production \
    app=kafka \
    team=data-engineering \
    --overwrite
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "=============================================="
echo "  Labels Applied — Summary"
echo "=============================================="
echo ""
echo "Namespace labels:"
kubectl get namespace "${STRIMZI_NS}" -o jsonpath='{.metadata.labels}' | jq .
echo ""
echo ""
echo "StatefulSet labels:"
kubectl get statefulsets -n "${STRIMZI_NS}" --show-labels 2>/dev/null || echo "  (no statefulsets found yet)"
echo ""
echo "How Kubecost uses these labels:"
echo "  - cost-center  → maps to 'department_label' → chargeback grouping"
echo "  - app          → maps to 'product_label' → product/service allocation"
echo "  - environment  → maps to 'environment_label' → prod vs dev filtering"
echo "  - team         → maps to 'team_label' → team cost attribution"
echo "  - owner        → maps to 'owner_label' → ownership for alerts/reports"
echo ""
echo "In the Kubecost UI:"
echo "  Allocations → Aggregate by 'Label' → Select 'app' → See Kafka costs"
echo "  Allocations → Aggregate by 'Namespace' → Filter 'strimzi'"
