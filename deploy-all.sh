#!/usr/bin/env bash
#
# Master deployment script for Kubecost 3.x on AKS.
#
# Runs all steps sequentially:
#   1. Create namespace
#   2. Create Azure billing secret (requires env vars)
#   3. Deploy Gateway resource
#   4. Install Kubecost via Helm
#   5. Apply FinOps labels to Strimzi resources
#   6. Run API test
#
# Prerequisites:
#   - kubectl configured for your AKS cluster
#   - helm installed
#   - Azure credentials set in environment (from 01-create-azure-sp.sh)
#     OR the cloud-integration secret already created manually
#   - Envoy Gateway installed (GatewayClass 'eg')
#   - Strimzi namespace and Kafka resources deployed (for Step 5)
#
# Usage:
#   chmod +x deploy-all.sh
#   ./deploy-all.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "================================================================"
echo "  Kubecost 3.x — Full AKS Deployment"
echo "  $(date -Iseconds)"
echo "================================================================"
echo ""

# -----------------------------------------------------------------------
# Step 1: Namespace
# -----------------------------------------------------------------------
echo ">>> STEP 1: Creating kubecost namespace..."
kubectl apply -f "${SCRIPT_DIR}/01-prerequisites/00-namespace.yaml"
echo ""

# -----------------------------------------------------------------------
# Step 2: Azure billing secret
# -----------------------------------------------------------------------
echo ">>> STEP 2: Azure cloud integration secret..."
if kubectl get secret cloud-integration -n kubecost &>/dev/null; then
  echo "    Secret 'cloud-integration' already exists — skipping."
elif [[ -n "${AZURE_STORAGE_ACCOUNT:-}" ]]; then
  echo "    Creating from environment variables..."
  bash "${SCRIPT_DIR}/01-prerequisites/02-create-secret.sh"
else
  echo "    WARNING: No AZURE_STORAGE_ACCOUNT set and no existing secret found."
  echo "    Kubecost will run but Azure out-of-cluster costs won't be available."
  echo "    To fix later:"
  echo "      1. Run: source /tmp/kubecost-azure-credentials.env"
  echo "      2. Run: bash ${SCRIPT_DIR}/01-prerequisites/02-create-secret.sh"
fi
echo ""

# -----------------------------------------------------------------------
# Step 3: Gateway
# -----------------------------------------------------------------------
echo ">>> STEP 3: Deploying Gateway resource..."
if kubectl get gatewayclass eg &>/dev/null; then
  kubectl apply -f "${SCRIPT_DIR}/04-gateway-route/gateway.yaml"
else
  echo "    WARNING: GatewayClass 'eg' not found — skipping Gateway creation."
  echo "    The Helm chart's HTTPRoute will be created but won't have a parent Gateway."
  echo "    Install Envoy Gateway and apply 04-gateway-route/gateway.yaml later."
fi
echo ""

# -----------------------------------------------------------------------
# Step 4: Helm install
# -----------------------------------------------------------------------
echo ">>> STEP 4: Installing Kubecost 3.x via Helm..."
bash "${SCRIPT_DIR}/02-kubecost-helm/install-kubecost.sh"
echo ""

# -----------------------------------------------------------------------
# Step 5: FinOps labels
# -----------------------------------------------------------------------
echo ">>> STEP 5: Applying FinOps cost-allocation labels..."
if kubectl get namespace strimzi &>/dev/null; then
  bash "${SCRIPT_DIR}/03-cost-allocation/apply-finops-labels.sh"
else
  echo "    WARNING: Namespace 'strimzi' does not exist yet."
  echo "    Run this after deploying Strimzi Kafka:"
  echo "      bash ${SCRIPT_DIR}/03-cost-allocation/apply-finops-labels.sh"
fi
echo ""

# -----------------------------------------------------------------------
# Step 6: Test
# -----------------------------------------------------------------------
echo ">>> STEP 6: Testing Kubecost API..."
echo "    (Kubecost needs ~15 minutes to collect initial data)"
echo "    Run the test manually when ready:"
echo "      bash ${SCRIPT_DIR}/06-test-query/test-kubecost-api.sh"
echo ""

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
echo "================================================================"
echo "  Deployment Complete!"
echo "================================================================"
echo ""
echo "  Kubecost 3.x components:"
kubectl get pods -n kubecost --no-headers 2>/dev/null | awk '{printf "    %-50s %s\n", $1, $3}'
echo ""
echo "  Persistent volumes:"
kubectl get pvc -n kubecost --no-headers 2>/dev/null | awk '{printf "    %-50s %s %s\n", $1, $2, $4}'
echo ""
echo "  Next steps:"
echo "    1. Wait ~15 minutes for Kubecost to ingest initial metrics"
echo "    2. Access UI: kubectl port-forward -n kubecost svc/kubecost-frontend 9090:9090"
echo "    3. Open http://localhost:9090 in your browser"
echo "    4. Run API test: bash 06-test-query/test-kubecost-api.sh"
echo "    5. Check Allocations → Aggregate by 'Namespace' → View strimzi costs"
echo "    6. Check Budgets page to see the $100/week strimzi threshold"
echo ""
echo "  For Azure out-of-cluster costs (if not configured yet):"
echo "    1. Run: bash 01-prerequisites/01-create-azure-sp.sh"
echo "    2. Create a Cost Management daily export in Azure Portal"
echo "    3. Run: source /tmp/kubecost-azure-credentials.env"
echo "    4. Run: bash 01-prerequisites/02-create-secret.sh"
echo "    5. Restart cloudCost: kubectl rollout restart deployment -n kubecost -l app=cloud-cost"
echo "================================================================"
