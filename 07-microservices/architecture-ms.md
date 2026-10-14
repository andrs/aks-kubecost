# Microservices Architecture

---

## Overview

Two Flask microservices deployed to the `ecommerce-demo` namespace on AKS, purpose-built to demonstrate Kubecost cost allocation, efficiency scoring, and right-sizing recommendations.

They are **intentionally asymmetric**: one is well-sized for its workload, the other is overprovisioned — making FinOps inefficiencies visible in the Kubecost dashboard.

---

## Architecture Diagram

```
                        ┌─────────────────────────────────────────────┐
                        │         AKS Cluster — ecommerce-demo         │
                        │                                              │
  User / Test Script    │   ┌────────────────────┐                    │
         │              │   │   service-orders   │                    │
         │ :8081        │   │                    │                    │
         ├─────────────►│   │  GET  /health      │                    │
         │              │   │  GET  /orders      │                    │
         │              │   │  POST /stress      │                    │
         │              │   │                    │                    │
         │              │   │  requests:         │                    │
         │              │   │    cpu: 100m       │                    │
         │              │   │    memory: 128Mi   │                    │
         │              │   │  limits:           │                    │
         │              │   │    cpu: 500m       │                    │
         │              │   │    memory: 512Mi   │                    │
         │              │   └────────────────────┘                    │
         │              │                                              │
         │              │   ┌────────────────────┐                    │
         │ :8082        │   │  service-payments  │                    │
         └─────────────►│   │                    │                    │
                        │   │  GET  /health      │                    │
                        │   │  GET  /payments    │                    │
                        │   │                    │                    │
                        │   │  requests:         │                    │
                        │   │    cpu: 50m        │                    │
                        │   │    memory: 64Mi    │                    │
                        │   │  limits:           │                    │
                        │   │    cpu: 200m       │                    │
                        │   │    memory: 128Mi   │                    │
                        │   └────────────────────┘                    │
                        │                                              │
                        │   FinOps Agent ──► Kubecost Aggregator      │
                        │   (tracks CPU/RAM usage per pod, per minute) │
                        └─────────────────────────────────────────────┘
```

---

## Service: service-orders

### Role
Simulates a high-traffic order processing service. Includes a `/stress` endpoint to generate real CPU and memory load on demand.

### Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/health` | Liveness/readiness probe. Returns service name, version, status, timestamp |
| `GET` | `/orders` | Returns 5 mock orders with id, customer, total, status, items |
| `GET/POST` | `/stress` | Burns CPU and/or allocates memory for a configurable duration |

### Stress endpoint parameters

| Parameter | Default | Max | Description |
|-----------|---------|-----|-------------|
| `duration` | 30 | 120 | Seconds to run the stress test |
| `threads` | 2 | 4 | Number of CPU-burn threads |
| `mem_mb` | 0 | 256 | MB of RAM to allocate and hold |

```bash
# Light load
curl "http://localhost:8081/stress?duration=30&threads=2&mem_mb=50"

# Heavy load
curl "http://localhost:8081/stress?duration=120&threads=4&mem_mb=256"
```

### FinOps profile

```
Resource requests:  100m CPU / 128Mi RAM
Under stress load:  ~400m CPU / ~178Mi RAM
Efficiency:         HIGH — requests match actual usage under load
Kubecost signal:    Well-sized, no right-sizing recommendation expected
```

### Container

```
Image:     uniquenameregistry1.azurecr.io/service-orders:v1.0.0
Runtime:   gunicorn --workers 2 --threads 4 --bind 0.0.0.0:8080
Base:      python:3.12-slim (multi-stage, non-root user)
Port:      8080 (container) → 80 (Service) → 8081 (port-forward)
```

---

## Service: service-payments

### Role
Simulates a payment processor that is overprovisioned relative to its actual idle workload. Deliberately has high resource requests but near-zero real usage — to trigger Kubecost's right-sizing recommendations.

### Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/health` | Liveness/readiness probe |
| `GET` | `/payments` | Returns 3 mock payment records with id, order_id, amount, method, status |

### FinOps profile

```
Resource requests:  50m CPU / 64Mi RAM
Actual usage:       ~0.5m CPU / ~18Mi RAM (near-idle)
Efficiency:         LOW (~1% CPU, ~28% RAM)
Kubecost signal:    OVERPROVISIONED — right-sizing recommendation fires
Expected rec:       Reduce CPU to ~2m, RAM to ~22Mi, save ~$X/month
```

### Container

```
Image:     uniquenameregistry1.azurecr.io/service-payments:v1.0.0
Runtime:   gunicorn --workers 2 --threads 4 --bind 0.0.0.0:8080
Base:      python:3.12-slim (multi-stage, non-root user)
Port:      8080 (container) → 80 (Service) → 8082 (port-forward)
```

---

## Kubernetes Manifests

```
07-microservices/
├── k8s/
│   ├── 00-namespace.yaml        # ecommerce-demo namespace with FinOps labels
│   ├── 01-service-orders.yaml   # Deployment + ClusterIP Service
│   └── 02-service-payments.yaml # Deployment + ClusterIP Service
├── service-orders/
│   ├── app.py                   # Flask application
│   ├── requirements.txt         # flask, gunicorn
│   └── Dockerfile               # multi-stage, python:3.12-slim
├── service-payments/
│   ├── app.py
│   ├── requirements.txt
│   └── Dockerfile
├── build-and-deploy.sh          # Full pipeline: ACR build + kubectl apply
├── test-kubecost-allocation.sh  # Stress + Kubecost API validation
├── commands-ms.md               # This file's companion: all CLI commands
└── architecture-ms.md           # This file
```

---

## FinOps Labels

Both services carry the same labels for Kubecost cost attribution:

```yaml
labels:
  cost-center: digital-storefront    # maps to Kubecost "department"
  environment: staging
  app.kubernetes.io/part-of: ecommerce
  team: storefront-engineering       # maps to Kubecost "team"
  owner: ecommerce-team              # maps to Kubecost "owner"
```

This allows Kubecost to answer:
- **How much did `digital-storefront` spend this week?**
- **What is the combined cost of the `ecommerce` workload?**
- **Which environment (staging vs production) is cheaper?**

---

## Efficiency Comparison in Kubecost

After deploying and waiting ~15 minutes for Kubecost to collect data:

```
Kubecost → Allocations → Aggregate by Controller → Filter: ecommerce-demo

Controller          | Efficiency | Expected signal
--------------------|------------|--------------------------------
service-orders      | ~80-90%    | Green — well-sized
service-payments    | ~1-5%      | Red — right-sizing recommended
```

To view right-sizing recommendations:
```
Kubecost → Savings → Request Right-Sizing → Filter: namespace = ecommerce-demo
```

---

## Image Build Flow

```
Local source code
      │
      ▼
az acr build (cloud-side build, no local Docker needed)
      │
      ▼
uniquenameregistry1.azurecr.io
  ├── service-orders:v1.0.0
  └── service-payments:v1.0.0
      │
      ▼
AKS pulls image via managed identity (az aks update --attach-acr)
      │
      ▼
Pod running in ecommerce-demo namespace
```

---

## Resource Summary

| Resource | service-orders | service-payments |
|----------|---------------|-----------------|
| CPU request | 100m | 50m |
| CPU limit | 500m | 200m |
| RAM request | 128Mi | 64Mi |
| RAM limit | 512Mi | 128Mi |
| Replicas | 1 | 1 |
| Service type | ClusterIP | ClusterIP |
| Port (container) | 8080 | 8080 |
| Port (service) | 80 | 80 |
| Port (port-forward) | 8081 | 8082 |
| Has stress endpoint | Yes | No |
| Expected efficiency | HIGH | LOW |
