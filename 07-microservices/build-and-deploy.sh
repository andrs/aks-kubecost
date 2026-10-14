#!/usr/bin/env bash
#
# Builds container images via ACR, attaches ACR to AKS, and deploys both services.
#
set -euo pipefail

ACR_NAME="uniquenameregistry1"
ACR_LOGIN_SERVER="${ACR_NAME}.azurecr.io"
RESOURCE_GROUP="aks-cluster-andres"
AKS_CLUSTER="aks"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=============================================="
echo "  Step 1: Attach ACR to AKS"
echo "=============================================="
echo "==> Attaching ${ACR_NAME} to AKS cluster ${AKS_CLUSTER}..."
az aks update \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${AKS_CLUSTER}" \
  --attach-acr "${ACR_NAME}" \
  --output none 2>/dev/null || echo "    (ACR may already be attached or permissions insufficient — continuing)"

echo ""
echo "=============================================="
echo "  Step 2: Build and Push Images via ACR"
echo "=============================================="

echo "==> Building service-orders..."
az acr build \
  --registry "${ACR_NAME}" \
  --image "service-orders:v1.0.0" \
  --file "${SCRIPT_DIR}/service-orders/Dockerfile" \
  "${SCRIPT_DIR}/service-orders/"

echo ""
echo "==> Building service-payments..."
az acr build \
  --registry "${ACR_NAME}" \
  --image "service-payments:v1.0.0" \
  --file "${SCRIPT_DIR}/service-payments/Dockerfile" \
  "${SCRIPT_DIR}/service-payments/"

echo ""
echo "==> Verify images in ACR:"
az acr repository list --name "${ACR_NAME}" --output table
echo ""
az acr repository show-tags --name "${ACR_NAME}" --repository service-orders --output table
az acr repository show-tags --name "${ACR_NAME}" --repository service-payments --output table

echo ""
echo "=============================================="
echo "  Step 3: Deploy to AKS"
echo "=============================================="

echo "==> Creating namespace..."
kubectl apply -f "${SCRIPT_DIR}/k8s/00-namespace.yaml"

echo "==> Deploying service-orders..."
kubectl apply -f "${SCRIPT_DIR}/k8s/01-service-orders.yaml"

echo "==> Deploying service-payments..."
kubectl apply -f "${SCRIPT_DIR}/k8s/02-service-payments.yaml"

echo ""
echo "==> Waiting for rollouts..."
kubectl rollout status deployment/service-orders -n ecommerce-demo --timeout=120s
kubectl rollout status deployment/service-payments -n ecommerce-demo --timeout=120s

echo ""
echo "==> Final status:"
kubectl get pods -n ecommerce-demo -o wide
echo ""
kubectl get svc -n ecommerce-demo

echo ""
echo "=============================================="
echo "  Deployment complete!"
echo "=============================================="
echo ""
echo "  Test endpoints:"
echo "    kubectl port-forward -n ecommerce-demo svc/service-orders 8081:80 &"
echo "    curl http://localhost:8081/health"
echo "    curl http://localhost:8081/orders"
echo "    curl -X POST 'http://localhost:8081/stress?duration=30&threads=2'"
echo ""
echo "    kubectl port-forward -n ecommerce-demo svc/service-payments 8082:80 &"
echo "    curl http://localhost:8082/health"
echo "    curl http://localhost:8082/payments"
