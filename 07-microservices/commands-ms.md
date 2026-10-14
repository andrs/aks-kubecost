# Microservices — Deploy & Test Commands

All commands assume you are in the repo root: `/home/ubuntu/aks-kubecost/`

---

## 1. Prerequisites

```bash
# Confirm AKS context is active
kubectl config current-context

# Confirm ACR exists
az acr show --name uniquenameregistry1 --query loginServer -o tsv

# Confirm Azure CLI is logged in
az account show --query "{subscription:id, name:name}" -o table
```

---

## 2. Build and Deploy (automated)

```bash
# Full pipeline: attach ACR → build images → deploy to AKS
chmod +x 07-microservices/build-and-deploy.sh
./07-microservices/build-and-deploy.sh
```

---

## 3. Build and Deploy (step by step)

### 3.1 Attach ACR to AKS (one-time)

```bash
az aks update \
  --resource-group aks-cluster-andres \
  --name aks \
  --attach-acr uniquenameregistry1
```

### 3.2 Build service-orders image

```bash
az acr build \
  --registry uniquenameregistry1 \
  --image service-orders:v1.0.0 \
  --file 07-microservices/service-orders/Dockerfile \
  07-microservices/service-orders/
```

### 3.3 Build service-payments image

```bash
az acr build \
  --registry uniquenameregistry1 \
  --image service-payments:v1.0.0 \
  --file 07-microservices/service-payments/Dockerfile \
  07-microservices/service-payments/
```

### 3.4 Verify images in ACR

```bash
az acr repository list --name uniquenameregistry1 --output table

az acr repository show-tags --name uniquenameregistry1 --repository service-orders --output table
az acr repository show-tags --name uniquenameregistry1 --repository service-payments --output table
```

### 3.5 Apply Kubernetes manifests

```bash
# Namespace
kubectl apply -f 07-microservices/k8s/00-namespace.yaml

# Deployments + Services
kubectl apply -f 07-microservices/k8s/01-service-orders.yaml
kubectl apply -f 07-microservices/k8s/02-service-payments.yaml
```

### 3.6 Wait for rollout

```bash
kubectl rollout status deployment/service-orders -n ecommerce-demo --timeout=120s
kubectl rollout status deployment/service-payments -n ecommerce-demo --timeout=120s
```

---

## 4. Verify Deployment

```bash
# Pod status
kubectl get pods -n ecommerce-demo -o wide

# Services
kubectl get svc -n ecommerce-demo

# Labels (FinOps cost attribution)
kubectl get pods -n ecommerce-demo --show-labels

# Describe a pod (check image, resources, probes)
kubectl describe pod -n ecommerce-demo -l app=service-orders
kubectl describe pod -n ecommerce-demo -l app=service-payments
```

---

## 5. Port-Forward for Local Testing

```bash
# Kill any existing port-forwards
lsof -ti:8081 | xargs kill -9 2>/dev/null || true
lsof -ti:8082 | xargs kill -9 2>/dev/null || true

# Start port-forwards
kubectl port-forward -n ecommerce-demo svc/service-orders   8081:80 &
kubectl port-forward -n ecommerce-demo svc/service-payments 8082:80 &

sleep 2
```

---

## 6. Test service-orders

```bash
# Health check
curl http://localhost:8081/health

# List orders
curl http://localhost:8081/orders

# Stress test — burn CPU 30s, 2 threads, 50MB RAM
curl "http://localhost:8081/stress?duration=30&threads=2&mem_mb=50"

# Stress test — maximum load (120s, 4 threads, 256MB)
curl "http://localhost:8081/stress?duration=120&threads=4&mem_mb=256"
```

Expected `/health` response:
```json
{
  "service": "service-orders",
  "version": "1.0.0",
  "status": "healthy",
  "timestamp": 1718000000.0
}
```

---

## 7. Test service-payments

```bash
# Health check
curl http://localhost:8082/health

# List payments
curl http://localhost:8082/payments
```

Expected `/payments` response:
```json
{
  "service": "service-payments",
  "count": 3,
  "payments": [
    {"id": "PAY-5001", "order_id": "ORD-1001", "amount": 149.99, ...},
    ...
  ]
}
```

---

## 8. Watch resource usage in real time

```bash
# CPU and memory usage per pod
kubectl top pods -n ecommerce-demo

# Watch continuously
watch -n 5 kubectl top pods -n ecommerce-demo

# While stress test runs — run this in a second terminal
kubectl port-forward -n ecommerce-demo svc/service-orders 8081:80 &
curl "http://localhost:8081/stress?duration=60&threads=4&mem_mb=100" &
watch -n 2 kubectl top pods -n ecommerce-demo
```

---

## 9. Kubecost Allocation Test (full suite)

```bash
chmod +x 07-microservices/test-kubecost-allocation.sh
./07-microservices/test-kubecost-allocation.sh
```

This script:
- Stress-tests service-orders for 30s
- Queries Kubecost Allocation API by namespace
- Queries by `cost-center` label
- Queries by controller (orders vs payments comparison)
- Queries right-sizing recommendations

---

## 10. Kubecost API — ecommerce-demo queries

First open Kubecost port-forward:
```bash
lsof -ti:9090 | xargs kill -9 2>/dev/null || true
kubectl port-forward -n kubecost svc/kubecost-frontend 9090:9090 &
sleep 3
```

### Cost by namespace
```bash
curl -s "http://localhost:9090/model/allocation?window=1d&aggregate=namespace&filterNamespaces=ecommerce-demo&accumulate=true" | jq '.data[0]'
```

### Cost by controller (orders vs payments)
```bash
curl -s "http://localhost:9090/model/allocation?window=1d&aggregate=controller&filterNamespaces=ecommerce-demo&accumulate=true" | \
  jq -r '.data[0] | to_entries[] | "\(.key): $\(.value.totalCost | . * 1000 | round / 1000) efficiency=\(.value.totalEfficiency | . * 100 | round)%"'
```

### Cost by cost-center label
```bash
curl -s "http://localhost:9090/model/allocation?window=7d&aggregate=label:cost-center&accumulate=true" | \
  jq '.data[0]["digital-storefront"]'
```

### Right-sizing recommendations
```bash
curl -s "http://localhost:9090/model/savings/requestSizingV2?window=1d&filterNamespaces=ecommerce-demo&targetCPUUtilization=0.7&targetRAMUtilization=0.7" | jq '.'
```

### Efficiency per pod
```bash
curl -s "http://localhost:9090/model/allocation?window=1d&aggregate=pod&filterNamespaces=ecommerce-demo&accumulate=true" | \
  jq -r '.data[0] | to_entries[] | "\(.key): CPU_eff=\(.value.cpuEfficiency | . * 100 | round)% RAM_eff=\(.value.ramEfficiency | . * 100 | round)%"'
```

---

## 11. Logs

```bash
# service-orders logs
kubectl logs -n ecommerce-demo -l app=service-orders --tail=50 -f

# service-payments logs
kubectl logs -n ecommerce-demo -l app=service-payments --tail=50 -f

# Both services simultaneously
kubectl logs -n ecommerce-demo -l app.kubernetes.io/part-of=ecommerce --tail=30 --prefix
```

---

## 12. Rebuild and Redeploy (after code change)

```bash
# Bump version tag
NEW_TAG="v1.0.1"

# Rebuild orders
az acr build \
  --registry uniquenameregistry1 \
  --image "service-orders:${NEW_TAG}" \
  --file 07-microservices/service-orders/Dockerfile \
  07-microservices/service-orders/

# Update image in cluster
kubectl set image deployment/service-orders \
  service-orders="uniquenameregistry1.azurecr.io/service-orders:${NEW_TAG}" \
  -n ecommerce-demo

# Verify rollout
kubectl rollout status deployment/service-orders -n ecommerce-demo
```

---

## 13. Cleanup

```bash
# Remove ecommerce-demo namespace (deletes all resources inside)
kubectl delete namespace ecommerce-demo

# Remove images from ACR
az acr repository delete --name uniquenameregistry1 --repository service-orders --yes
az acr repository delete --name uniquenameregistry1 --repository service-payments --yes
```
