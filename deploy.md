# Kubecost 3.x on AKS — Enterprise FinOps Deployment Guide

This guide walks through the complete installation and configuration of **Kubecost 3.3.0** on Azure Kubernetes Service (AKS) to track, allocate, and optimize cloud spending. It specifically targets monitoring the **Strimzi Kafka** cluster deployed in the `strimzi` namespace alongside general cluster overhead.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Prerequisites](#2-prerequisites)
3. [Step 1 — Create Namespace and Azure Cloud Integration](#3-step-1--create-namespace-and-azure-cloud-integration)
4. [Step 2 — Deploy Kubecost via Helm](#4-step-2--deploy-kubecost-via-helm)
5. [Step 3 — Cost Allocation and FinOps Tagging](#5-step-3--cost-allocation-and-finops-tagging)
6. [Step 4 — Expose the Kubecost UI (Gateway API)](#6-step-4--expose-the-kubecost-ui-gateway-api)
7. [Step 5 — Configure Budgets and Alerts](#7-step-5--configure-budgets-and-alerts)
8. [Step 6 — Test and API Query](#8-step-6--test-and-api-query)
9. [Automated Full Deployment](#9-automated-full-deployment)
10. [Troubleshooting](#10-troubleshooting)
11. [References](#11-references)

---

## 1. Architecture Overview

Kubecost 3.x represents a major architecture shift from 2.x. Understanding the components is important before deploying.

### Kubecost 3.x Components

```
┌─────────────────────────────────────────────────────────────────────┐
│                        AKS Cluster                                  │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │                    kubecost namespace                         │   │
│  │                                                              │   │
│  │  ┌──────────────┐   ┌──────────────┐   ┌────────────────┐   │   │
│  │  │   Frontend    │   │  Aggregator   │   │   CloudCost    │   │   │
│  │  │   (UI:9090)   │──▶│ (ClickHouse)  │   │  (Azure CMS)  │   │   │
│  │  └──────────────┘   └──────┬───────┘   └───────┬────────┘   │   │
│  │                            │                    │            │   │
│  │  ┌──────────────┐   ┌─────┴────────┐   ┌──────┴─────────┐  │   │
│  │  │  FinOps Agent │──▶│  LocalStore   │   │ Azure Storage  │  │   │
│  │  │ (Collector)   │   │   (PVC:32Gi)  │   │ (Cost Exports) │  │   │
│  │  └──────────────┘   └──────────────┘   └────────────────┘   │   │
│  │                                                              │   │
│  │  ┌──────────────────────────────────────────────────────┐    │   │
│  │  │         NetworkCosts DaemonSet (per node)            │    │   │
│  │  │  Tracks egress: in-zone / cross-zone / internet      │    │   │
│  │  └──────────────────────────────────────────────────────┘    │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │                    strimzi namespace                          │   │
│  │  Kafka brokers, ZooKeeper, Connect — labeled for FinOps      │   │
│  └──────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

| Component | Role | Persistence |
|-----------|------|-------------|
| **FinOps Agent** | Collects K8s metrics directly (replaces Prometheus) | In-memory with local retention |
| **LocalStore** | Buffers data between Agent and Aggregator | PVC: 32Gi (`managed-csi`) |
| **Aggregator** | ClickHouse-based analytics engine, serves the API | PVC: 64Gi + 1Gi configs (`managed-csi`) |
| **CloudCost** | Processes Azure Cost Management export data | Reads from Azure Storage Account |
| **Frontend** | Nginx-based UI, proxies API calls to Aggregator | Stateless |
| **NetworkCosts** | DaemonSet tracking per-pod network egress | Stateless |

### What changed from Kubecost 2.x

- **No Prometheus dependency** — the FinOps Agent collects metrics directly via the Kubernetes API, eliminating the need for a bundled or external Prometheus server
- **ClickHouse replaces DuckDB** — the Aggregator uses ClickHouse for the analytics database, improving query performance at scale
- **Native Gateway API support** — the Helm chart includes first-class `httpRoute` values, no separate Ingress manifest needed
- **ConfigMap-based budgets** — richer budget system with percentage-based actions, replacing the simpler 2.x alert-only approach
- **Azure cloud integration format changed** — uses an `authorizer` block with `authorizerType: "AzureAccessKey"` instead of flat key-value pairs

---

## 2. Prerequisites

Before starting, verify you have the following:

### Tools

| Tool | Minimum Version | Check Command |
|------|-----------------|---------------|
| `kubectl` | v1.28+ | `kubectl version --client` |
| `helm` | v3.12+ | `helm version` |
| `az` (Azure CLI) | v2.50+ | `az version` |
| `jq` | v1.6+ | `jq --version` |
| `curl` | any | `curl --version` |

### Cluster Access

```bash
# Verify you are connected to the correct AKS cluster
kubectl config current-context
# Expected output: aks (or your cluster context name)

# Verify nodes are ready
kubectl get nodes -o wide
```

### Azure Permissions

The user running `01-create-azure-sp.sh` needs:

- **Azure AD**: permission to create App Registrations and Service Principals (`Application.ReadWrite.All` or `Application Administrator` role)
- **Subscription**: permission to assign roles (`Owner` or `User Access Administrator`)

### Envoy Gateway (for Step 4)

If you plan to expose the UI via Gateway API, Envoy Gateway must be installed with a `GatewayClass` named `eg`. If not installed, Step 4 can be skipped — you can always access Kubecost via `kubectl port-forward`.

### Strimzi Kafka (for Step 3)

The FinOps tagging step expects the `strimzi` namespace and Kafka resources to exist. If Strimzi is not yet deployed, you can run Step 3 later after deploying Kafka.

---

## 3. Step 1 — Create Namespace and Azure Cloud Integration

This step creates the `kubecost` namespace, an Azure Service Principal with the required roles, a Storage Account for Cost Management exports, and the Kubernetes Secret that Kubecost reads.

### 3.1 Create the Namespace

```bash
kubectl apply -f 01-prerequisites/00-namespace.yaml
```

This creates the `kubecost` namespace with FinOps-standard labels:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: kubecost
  labels:
    app.kubernetes.io/managed-by: helm
    cost-center: platform-tools
    environment: production
```

Verify:

```bash
kubectl get namespace kubecost --show-labels
```

### 3.2 Create the Azure Service Principal and Storage Account

The script `01-create-azure-sp.sh` automates the creation of all Azure resources Kubecost needs:

**What it creates:**

1. **Service Principal** (`kubecost-billing-reader`) with three roles:
   - `Cost Management Reader` — read access to Azure Cost Management APIs
   - `Billing Reader` — access to the Azure Retail Prices API for accurate node/VM pricing
   - `Reader` — enumerate resource metadata (VMs, disks, load balancers)

2. **Storage Account** + blob container for Cost Management daily exports:
   - Resource group: `kubecost-exports-rg` (configurable via `KUBECOST_RG` env var)
   - Storage account: `kubecostexports<random>` (globally unique name)
   - Container: `costexports`

3. **Role assignment**: `Storage Blob Data Contributor` on the storage account for the SP

**Run it:**

```bash
# Authenticate to Azure if not already
az login

# Optional: set your subscription explicitly
# export AZURE_SUBSCRIPTION_ID="681fa09a-b1fd-4154-89c8-c04325ca4a9a"

# Optional: customize the region and resource group
# export AZURE_LOCATION="westeurope"
# export KUBECOST_RG="my-custom-rg"

# Run the script
bash 01-prerequisites/01-create-azure-sp.sh
```

**Expected output:**

```
==> Using subscription: 681fa09a-b1fd-4154-89c8-c04325ca4a9a
==> Creating Service Principal 'kubecost-billing-reader'...
==> Assigning 'Billing Reader' role...
==> Assigning 'Reader' role...

================================================================
  Service Principal created successfully
================================================================
  Client ID:       <generated>
  Client Secret:   <generated>
  Tenant ID:       378718bc-21f7-4c9c-be9b-226ff3c5f637
  Subscription ID: 681fa09a-b1fd-4154-89c8-c04325ca4a9a
================================================================

==> Creating resource group 'kubecost-exports-rg'...
==> Creating storage account 'kubecostexports<random>'...
==> Creating blob container 'costexports'...

================================================================
  Storage Account for Cost Exports
================================================================
  Storage Account:  kubecostexports<random>
  Container:        costexports
  Access Key:       <generated>
================================================================

==> Credentials saved to /tmp/kubecost-azure-credentials.env
```

### 3.3 Create the Azure Cost Management Export (Azure Portal)

This is a **manual step** in the Azure Portal. Kubecost reads daily cost exports from the storage account.

1. Navigate to **Cost Management + Billing** > **Cost Management** > **Exports**
2. Click **+ Create**
3. Configure:
   - **Name**: `kubecost-daily-export`
   - **Export type**: `Actual cost (Usage and purchases)`
   - **Frequency**: `Daily export of month-to-date costs`
   - **Storage account**: select the one created by the script (shown in output)
   - **Container**: `costexports`
   - **Format**: CSV
4. Click **Create**
5. Optionally click **Run now** to generate the first export immediately

> **Note**: It can take 24-48 hours for the first export data to appear. Kubecost will show in-cluster costs immediately; out-of-cluster Azure costs (nodes, LBs, disks) will appear once the export data is available.

### 3.4 Create the Kubernetes Secret

The secret provides Kubecost with the Azure Storage Account access key so it can read the cost exports.

```bash
# Source the credentials saved by the SP creation script
source /tmp/kubecost-azure-credentials.env

# Create the secret
bash 01-prerequisites/02-create-secret.sh
```

This creates a secret named `cloud-integration` in the `kubecost` namespace with the Kubecost 3.x JSON format:

```json
{
  "azure": {
    "storage": [
      {
        "subscriptionID": "<subscription-id>",
        "account": "<storage-account-name>",
        "container": "costexports",
        "path": "",
        "cloud": "Azure",
        "authorizer": {
          "accessKey": "<storage-access-key>",
          "account": "<storage-account-name>",
          "authorizerType": "AzureAccessKey"
        }
      }
    ]
  }
}
```

> **Important**: The `authorizerType: "AzureAccessKey"` format is specific to Kubecost 3.x. If you find older documentation referencing `azureStorageAccessKey` as a flat field, that is the 2.x format and will not work.

**Verify the secret:**

```bash
kubectl get secret cloud-integration -n kubecost
kubectl get secret cloud-integration -n kubecost -o jsonpath='{.data.cloud-integration\.json}' | base64 -d | jq .
```

**Alternative — manual template:**

If you prefer to fill in values manually instead of running the script, edit `01-prerequisites/azure-service-key-secret.yaml` with your credentials and apply:

```bash
kubectl apply -f 01-prerequisites/azure-service-key-secret.yaml
```

---

## 4. Step 2 — Deploy Kubecost via Helm

### 4.1 Add the Helm Repository

```bash
# Add the Kubecost 3.x repo (NOT the older cost-analyzer repo)
helm repo add kubecost https://kubecost.github.io/kubecost/
helm repo update kubecost

# Verify the chart is available
helm search repo kubecost/kubecost
# Expected: kubecost/kubecost    3.3.0    3.3.0    Kubecost Helm chart
```

> **Note**: The 3.x chart is at `https://kubecost.github.io/kubecost/` (chart name `kubecost/kubecost`). The older 2.x chart was at `https://kubecost.github.io/cost-analyzer/` (chart name `kubecost/cost-analyzer`). Make sure you use the correct repository.

### 4.2 Review the Values File

The production values file is at `02-kubecost-helm/values-aks-production.yaml`. Here are the key configuration sections and what they do:

**Global cluster identity:**

```yaml
global:
  clusterId: "aks-kubecost-prod"    # Unique identifier for this cluster
```

**Azure cloud cost integration — references the secret from Step 1:**

```yaml
cloudCost:
  enabled: true
  cloudIntegrationSecret: "cloud-integration"   # The K8s secret name
  retention1d: 91                                # Keep 91 days of cloud cost data
  refreshRateHours: "6"                          # Re-process exports every 6 hours
```

**Persistent storage — uses Azure Managed CSI disks:**

```yaml
localStore:
  persistentVolume:
    enabled: true
    size: 32Gi
    storageClass: "managed-csi"    # Azure managed disk CSI driver

aggregator:
  aggregatorDbStorage:
    storageClass: "managed-csi"
    storageRequest: 64Gi           # ClickHouse database
  persistentConfigsStorage:
    storageClass: "managed-csi"
    storageRequest: 1Gi            # Saved reports, settings
```

**Network costs DaemonSet — critical for Kafka traffic attribution:**

```yaml
networkCosts:
  enabled: true
  config:
    destinations:
      # 10.0.0.0/8 is intentionally REMOVED from in-zone.
      # On multi-AZ AKS clusters, pod-to-pod traffic between availability zones
      # uses the 10.x.x.x range. By excluding it from in-zone, Kubecost classifies
      # cross-AZ Kafka inter-broker replication as "in-region" (cross-zone) traffic,
      # which has actual egress costs on Azure (~$0.01/GB).
      in-zone:
        - "127.0.0.0/8"
        - "169.254.0.0/16"
        - "172.16.0.0/12"
        - "192.168.0.0/16"
    services:
      azure-cloud-services: true     # Label traffic to Azure service endpoints
```

**FinOps label mapping — connects K8s labels to Kubecost dimensions:**

```yaml
kubecostProductConfigs:
  labelMappingConfigs:
    owner_label: "owner"             # K8s label → Kubecost "Owner" dimension
    team_label: "team"               # K8s label → Kubecost "Team" dimension
    department_label: "department"    # K8s label → Kubecost "Department" dimension
    product_label: "app"             # K8s label → Kubecost "Product" dimension
    environment_label: "environment" # K8s label → Kubecost "Environment" dimension
```

**Budget definitions (inline in values.yaml):**

```yaml
kubecostProductConfigs:
  budgets:
    budgetsConfig:
      - name: "Strimzi Kafka Weekly Budget"
        budgetType: "allocations"
        interval: "weekly"
        spendLimit: 100              # $100 per week
        values:
          namespace: ["strimzi"]     # Scoped to strimzi namespace
        actions:
          - percentage: 75           # Alert at 75% ($75)
            emails: ["finops-alerts@mydomain.com"]
          - percentage: 100          # Alert at 100% ($100)
            emails: ["finops-alerts@mydomain.com", "data-platform-team@mydomain.com"]
```

### 4.3 Install Kubecost

**Using the install script:**

```bash
bash 02-kubecost-helm/install-kubecost.sh
```

**Or manually:**

```bash
helm upgrade --install kubecost kubecost/kubecost \
  --namespace kubecost \
  --values 02-kubecost-helm/values-aks-production.yaml \
  --wait \
  --timeout 10m
```

### 4.4 Verify the Deployment

```bash
# Check all pods are running
kubectl get pods -n kubecost
```

Expected pods:

```
NAME                                    READY   STATUS    RESTARTS   AGE
kubecost-aggregator-0                   1/1     Running   0          2m
kubecost-cloud-cost-xxxxxxxxx-xxxxx     1/1     Running   0          2m
kubecost-finops-agent-xxxxxxxxx-xxxxx   1/1     Running   0          2m
kubecost-frontend-xxxxxxxxx-xxxxx       1/1     Running   0          2m
kubecost-local-store-0                  1/1     Running   0          2m
kubecost-network-costs-xxxxx            1/1     Running   0          2m  (DaemonSet, one per node)
```

```bash
# Check PVCs are bound
kubectl get pvc -n kubecost
```

Expected:

```
NAME                                     STATUS   VOLUME   CAPACITY   STORAGECLASS   AGE
kubecost-aggregator-db-kubecost-agg...   Bound    ...      64Gi       managed-csi    2m
kubecost-aggregator-configs-kubecost...  Bound    ...      1Gi        managed-csi    2m
kubecost-local-store-kubecost-local...   Bound    ...      32Gi       managed-csi    2m
```

```bash
# Check services
kubectl get svc -n kubecost
```

---

## 5. Step 3 — Cost Allocation and FinOps Tagging

Kubecost uses Kubernetes labels on namespaces, pods, and controllers for cost aggregation. The `labelMappingConfigs` in `values.yaml` maps specific label names to Kubecost's allocation dimensions.

### 5.1 Label Mapping Explained

| K8s Label | Kubecost Config Key | Kubecost Dimension | Purpose |
|-----------|--------------------|--------------------|---------|
| `owner` | `owner_label` | Owner | Who owns the resource (for accountability) |
| `team` | `team_label` | Team | Which team to charge back to |
| `department` | `department_label` | Department | Business unit grouping |
| `app` | `product_label` | Product | Application/service identification |
| `environment` | `environment_label` | Environment | prod/staging/dev filtering |

When you label a namespace or workload with `app=kafka`, Kubecost maps that to the "Product" dimension in allocation reports. This means you can aggregate all costs by "Product" in the UI and see Kafka's total spend.

### 5.2 Apply FinOps Labels

```bash
bash 03-cost-allocation/apply-finops-labels.sh
```

> **Note**: Run this after Strimzi Kafka is deployed. If the `strimzi` namespace does not exist yet, the script will fail. Deploy Kafka first, then run this script.

**What the script labels:**

1. **Namespace** (`strimzi`):
   ```bash
   kubectl label namespace strimzi \
     cost-center=data-platform \
     environment=production \
     app=kafka \
     team=data-engineering \
     owner=platform-team \
     department=engineering \
     --overwrite
   ```

2. **All StatefulSets** in `strimzi` (Kafka brokers, ZooKeeper):
   ```bash
   kubectl label statefulset/<name> -n strimzi \
     cost-center=data-platform \
     environment=production \
     app=kafka \
     component=broker \
     team=data-engineering \
     owner=platform-team \
     --overwrite
   ```

3. **All Deployments** in `strimzi` (Kafka Connect, MirrorMaker, Entity Operator):
   ```bash
   kubectl label deployment/<name> -n strimzi \
     cost-center=data-platform \
     environment=production \
     app=kafka \
     team=data-engineering \
     owner=platform-team \
     --overwrite
   ```

4. **All PVCs** in `strimzi` (broker storage, ZooKeeper data):
   ```bash
   kubectl label pvc/<name> -n strimzi \
     cost-center=data-platform \
     environment=production \
     app=kafka \
     team=data-engineering \
     --overwrite
   ```

### 5.3 Verify Labels

```bash
# Namespace labels
kubectl get namespace strimzi --show-labels

# StatefulSet labels
kubectl get statefulsets -n strimzi --show-labels

# PVC labels
kubectl get pvc -n strimzi --show-labels
```

### 5.4 How Kubecost Uses These Labels

In the Kubecost UI:

- **Allocations > Aggregate by "Namespace"** — shows `strimzi` as a top-level cost center
- **Allocations > Aggregate by "Label" > select `app`** — shows `kafka` with its total cost
- **Allocations > Aggregate by "Label" > select `team`** — shows `data-engineering` spend
- **Filters** — you can filter by `environment=production` to exclude dev/staging costs from reports

For chargeback reports:

- Group by `cost-center` label to see `data-platform` total spend
- This includes all resources in the `strimzi` namespace: CPU, RAM, storage (PVCs), network, and load balancers

---

## 6. Step 4 — Expose the Kubecost UI (Gateway API)

The Kubecost 3.x Helm chart has native Gateway API HTTPRoute support. We need to create the Gateway resource; the chart creates the HTTPRoute automatically.

### 6.1 Architecture

```
Internet → Azure LB → Envoy Gateway → Gateway (kubecost-gateway)
                                           │
                                           ▼
                                      HTTPRoute (created by Helm)
                                           │
                                           ▼
                                   kubecost-frontend:9090
```

### 6.2 Deploy the Gateway

```bash
kubectl apply -f 04-gateway-route/gateway.yaml
```

This creates a Gateway named `kubecost-gateway` in the `kubecost` namespace:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: kubecost-gateway
  namespace: kubecost
spec:
  gatewayClassName: eg              # Envoy Gateway class
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      hostname: kubecost.aks.mydomain.com
      allowedRoutes:
        namespaces:
          from: Same                # Only routes in kubecost namespace
```

The corresponding HTTPRoute is created by the Helm chart based on these values in `values-aks-production.yaml`:

```yaml
httpRoute:
  enabled: true
  parentRefs:
    - name: kubecost-gateway
      namespace: kubecost
  hostnames:
    - kubecost.aks.mydomain.com
  paths: ["/"]
  pathType: PathPrefix
```

### 6.3 Get the External IP and Configure DNS

```bash
# Wait for the Gateway to get an address
kubectl get gateway kubecost-gateway -n kubecost

# Get the external IP/hostname
EXTERNAL_IP=$(kubectl get gateway kubecost-gateway -n kubecost \
  -o jsonpath='{.status.addresses[0].value}')
echo "External IP: ${EXTERNAL_IP}"
```

Then create a DNS record:

- **A record**: `kubecost.aks.mydomain.com` → `<external-ip>`
- Or **CNAME**: if the Gateway provides a hostname instead of an IP

### 6.4 Verify

```bash
# Check the Gateway is programmed
kubectl get gateway -n kubecost

# Check the HTTPRoute is accepted
kubectl get httproute -n kubecost

# Test access (after DNS propagation)
curl -s http://kubecost.aks.mydomain.com/healthz
```

### 6.5 Alternative — Port-Forward (No Gateway Required)

If you don't have Envoy Gateway or prefer not to expose the UI externally:

```bash
kubectl port-forward -n kubecost svc/kubecost-frontend 9090:9090
```

Then open `http://localhost:9090` in your browser.

To disable the HTTPRoute in the Helm chart, set `httpRoute.enabled: false` in the values file.

---

## 7. Step 5 — Configure Budgets and Alerts

Kubecost 3.x supports budget definitions with percentage-based alert actions. Our configuration defines two budgets.

### 7.1 Budgets Defined in values.yaml

The budgets are defined inline in `values-aks-production.yaml` under `kubecostProductConfigs.budgets.budgetsConfig`. They are applied automatically during `helm install`.

**Budget 1 — Strimzi Kafka Weekly ($100/week)**

| Setting | Value | Explanation |
|---------|-------|-------------|
| `budgetType` | `allocations` | Tracks in-cluster resource costs (CPU, RAM, PV, network, LB) |
| `interval` | `weekly` | Budget resets every week |
| `intervalDay` | `1` | Week starts on Monday |
| `spendLimit` | `100` | $100 USD per week |
| `values.namespace` | `["strimzi"]` | Scoped to the strimzi namespace only |
| Action at 75% | Email `finops-alerts@mydomain.com` | Early warning at $75 |
| Action at 100% | Email both `finops-alerts@` and `data-platform-team@` | Budget exceeded alert |

**Budget 2 — Cluster Total Monthly ($1000/month)**

| Setting | Value | Explanation |
|---------|-------|-------------|
| `budgetType` | `allocations` | All in-cluster costs |
| `interval` | `monthly` | Budget resets monthly |
| `spendLimit` | `1000` | $1000 USD per month |
| `values.cluster` | `["aks-kubecost-prod"]` | Entire cluster |
| Action at 80% | Email `finops-alerts@mydomain.com` | Alert at $800 |

### 7.2 Alternative — Standalone ConfigMap

If you prefer to manage budgets independently of Helm releases (e.g., via GitOps), use the ConfigMap approach:

```bash
# Apply the standalone budget ConfigMap
kubectl apply -f 05-budgets-alerts/budget-configmap.yaml
```

Then update `values.yaml` to reference it:

```yaml
kubecostProductConfigs:
  budgets:
    configmapName: "kubecost-budgets"    # Reference the ConfigMap
    budgetsConfig: []                    # Remove inline config
```

And upgrade the Helm release:

```bash
helm upgrade kubecost kubecost/kubecost \
  --namespace kubecost \
  --values 02-kubecost-helm/values-aks-production.yaml
```

### 7.3 Health Alerts

A health alert is configured in `global.notifications.alertConfigs.alerts`:

```yaml
alerts:
  - type: health
    window: 1h
```

This monitors Kubecost's own health via multi-cluster diagnostics and alerts if something is wrong (e.g., the aggregator is down, data ingestion has stopped).

### 7.4 Optional — Prometheus Alert Rules

If you have an external Prometheus + Alertmanager (e.g., `kube-prometheus-stack`), you can deploy additional PrometheusRule CRDs:

```bash
kubectl apply -f 05-budgets-alerts/prometheus-alert-rules.yaml
```

This adds two alerts:
- **StrimziNamespaceCostHigh** — fires when the strimzi namespace daily cost exceeds $14.28 (=$100/7 days)
- **StrimziNetworkEgressHigh** — fires when strimzi network egress is projected above $5/day

> **Note**: These require Prometheus to be scraping Kubecost metrics. In a pure Kubecost 3.x deployment (no Prometheus), rely on the built-in budget alerts instead.

### 7.5 Verify Budgets in the UI

1. Open the Kubecost UI
2. Navigate to **Budgets** in the left sidebar
3. You should see both budgets with their current spend vs. limit
4. The progress bar shows percentage consumed for the current interval

---

## 8. Step 6 — Test and API Query

### 8.1 Run the Test Script

```bash
bash 06-test-query/test-kubecost-api.sh
```

The script:
1. Discovers the Kubecost frontend service automatically
2. Starts a `kubectl port-forward` in the background
3. Runs a health check against `/healthz`
4. Queries `/model/allocation` for the `strimzi` namespace (last 24h)
5. Queries all namespaces for cost comparison
6. Queries `/model/assets` for node costs
7. Cleans up the port-forward on exit

> **Note**: Kubecost needs approximately 15 minutes after deployment to collect initial metrics. If you run the test immediately, you may see empty results. Wait 15 minutes and try again.

### 8.2 Manual API Queries

Start a port-forward:

```bash
kubectl port-forward -n kubecost svc/kubecost-frontend 9090:9090 &
```

**Strimzi namespace cost (last 24h):**

```bash
curl -s 'http://localhost:9090/model/allocation?window=1d&aggregate=namespace&filterNamespaces=strimzi&accumulate=true' | jq .
```

**All namespaces (last 7 days):**

```bash
curl -s 'http://localhost:9090/model/allocation?window=7d&aggregate=namespace&accumulate=true' | jq .
```

**Costs by label `app` (last 7 days):**

```bash
curl -s 'http://localhost:9090/model/allocation?window=7d&aggregate=label:app&accumulate=true' | jq .
```

**Asset costs (nodes, disks, LBs):**

```bash
curl -s 'http://localhost:9090/model/assets?window=7d&aggregate=type&accumulate=true' | jq .
```

**Azure cloud costs (requires Cost Management export data):**

```bash
curl -s 'http://localhost:9090/model/cloudCost?window=7d&aggregate=service' | jq .
```

### 8.3 Expected API Response Format

A typical allocation response:

```json
{
  "code": 200,
  "status": "success",
  "data": [
    {
      "strimzi": {
        "name": "strimzi",
        "properties": { "cluster": "aks-kubecost-prod", "namespace": "strimzi" },
        "window": { "start": "2026-10-13T00:00:00Z", "end": "2026-10-14T00:00:00Z" },
        "start": "2026-10-13T00:00:00Z",
        "end": "2026-10-14T00:00:00Z",
        "cpuCores": 2.5,
        "cpuCoreRequestAverage": 2.0,
        "cpuCost": 3.45,
        "ramBytes": 8589934592,
        "ramByteRequestAverage": 6442450944,
        "ramCost": 1.23,
        "pvBytes": 107374182400,
        "pvCost": 0.55,
        "networkCost": 0.12,
        "loadBalancerCost": 0.00,
        "totalCost": 5.35,
        "totalEfficiency": 0.42
      }
    }
  ]
}
```

---

## 9. Automated Full Deployment

To run all steps in sequence with a single command:

```bash
# Option A: Source Azure credentials and run
source /tmp/kubecost-azure-credentials.env
bash deploy-all.sh

# Option B: Run without Azure integration (in-cluster costs only)
bash deploy-all.sh
```

The `deploy-all.sh` script:
1. Creates the `kubecost` namespace
2. Creates the Azure secret (if environment variables are set)
3. Deploys the Gateway (if Envoy Gateway is installed)
4. Installs Kubecost via Helm
5. Applies FinOps labels (if `strimzi` namespace exists)
6. Prints next steps for testing

---

## 10. Troubleshooting

### Pods not starting

```bash
# Check events
kubectl describe pod -n kubecost <pod-name>

# Check logs
kubectl logs -n kubecost <pod-name>

# Common issue: PVC not binding (wrong StorageClass)
kubectl get pvc -n kubecost
kubectl get storageclass
```

If `managed-csi` StorageClass does not exist, list available classes and update `values.yaml`:

```bash
kubectl get storageclass
# Use the default class, e.g., "default" or "managed"
```

### No cost data appearing

1. **In-cluster costs**: Wait 15 minutes after deployment. The FinOps Agent needs time to collect and process metrics.

2. **Azure out-of-cluster costs**: Check that:
   - The Cost Management export has run at least once (check Azure Portal > Cost Management > Exports)
   - The `cloud-integration` secret has valid credentials
   - The `kubecost-cloud-cost` pod logs show no errors:
     ```bash
     kubectl logs -n kubecost -l app=cloud-cost
     ```

### NetworkCosts DaemonSet not running

The NetworkCosts DaemonSet requires `NET_ADMIN` capability and `hostNetwork: true`. If your cluster has restrictive Pod Security Standards:

```bash
kubectl get pods -n kubecost -l app=network-costs
kubectl describe pod -n kubecost -l app=network-costs
```

### Budget alerts not firing

- Verify budgets are loaded: check the **Budgets** page in the UI
- Email alerts require either Kubecost's built-in SMTP server (internet access needed) or a custom SMTP configuration in `kubecostProductConfigs.smtp`
- For testing, check the Kubecost logs for alert evaluation:
  ```bash
  kubectl logs -n kubecost -l app.kubernetes.io/name=kubecost -c frontend
  ```

### HTTPRoute not working

```bash
# Check Gateway status
kubectl get gateway kubecost-gateway -n kubecost -o yaml

# Check HTTPRoute status
kubectl get httproute -n kubecost -o yaml

# Verify GatewayClass exists
kubectl get gatewayclass eg
```

---

## 11. References

| Resource | URL |
|----------|-----|
| Kubecost GitHub (3.x chart) | https://github.com/kubecost/kubecost |
| FinOps Agent Chart | https://github.com/kubecost/finops-agent-chart |
| Kubecost Cost Prediction Action | https://github.com/marketplace/actions/kubecost-cost-prediction |
| Kubecost API Directory | https://www.ibm.com/docs/en/kubecost/self-hosted/3.x?topic=kubecost-api-directory |
| Azure Cloud Integration | https://www.ibm.com/docs/en/kubecost/self-hosted/3.x?topic=integration-azure-cloud-integration |
| Network Cost Configuration | https://www.ibm.com/docs/en/kubecost/self-hosted/3.x?topic=configuration-network-cost |
| Budgets | https://www.ibm.com/docs/en/kubecost/self-hosted/3.x?topic=ui-budgets |
| Allocation API | https://www.ibm.com/docs/en/kubecost/self-hosted/3.x?topic=apis-allocation-api |

### Project File Reference

```
aks-kubecost/
├── deploy.md                                    ← This guide
├── deploy-all.sh                                ← Master deployment script
├── 01-prerequisites/
│   ├── 00-namespace.yaml                        ← kubecost namespace manifest
│   ├── 01-create-azure-sp.sh                    ← Azure SP + storage account creation
│   ├── 02-create-secret.sh                      ← K8s cloud-integration secret creation
│   └── azure-service-key-secret.yaml            ← Manual secret template
├── 02-kubecost-helm/
│   ├── values-aks-production.yaml               ← Helm values (main configuration)
│   └── install-kubecost.sh                      ← Helm install wrapper
├── 03-cost-allocation/
│   └── apply-finops-labels.sh                   ← FinOps labels for strimzi resources
├── 04-gateway-route/
│   ├── gateway.yaml                             ← Envoy Gateway resource
│   └── apply-gateway.sh                         ← Gateway apply wrapper
├── 05-budgets-alerts/
│   ├── budget-configmap.yaml                    ← Standalone budget ConfigMap (alternative)
│   └── prometheus-alert-rules.yaml              ← PrometheusRule CRDs (optional)
└── 06-test-query/
    └── test-kubecost-api.sh                     ← API test script with port-forward
```
