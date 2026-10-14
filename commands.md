# Kubecost Testing Commands

## 1. Open the Dashboard

```bash
# Start port-forward
kubectl port-forward -n kubecost svc/kubecost-frontend 9090:9090

# Open in browser: http://localhost:9090

# If connecting via SSH, run this on your LOCAL machine first:
# ssh -L 9090:localhost:9090 ubuntu@<server-ip>
```

## 2. Verify All Pods Are Healthy

```bash
# All pods should show Running / 1/1 Ready
kubectl get pods -n kubecost

# Check PVCs are bound
kubectl get pvc -n kubecost

# Check services
kubectl get svc -n kubecost
```

## 3. Check Component Logs

```bash
# Frontend (UI/nginx)
kubectl logs -n kubecost -l app.kubernetes.io/name=frontend --tail=20

# Aggregator (ClickHouse analytics)
kubectl logs -n kubecost kubecost-aggregator-0 --tail=20

# FinOps Agent (metrics collector)
kubectl logs -n kubecost -l app.kubernetes.io/name=finopsagent --tail=20

# Cloud Cost (Azure billing processor)
kubectl logs -n kubecost -l app=cloud-cost --tail=20

# Network Costs (DaemonSet)
kubectl logs -n kubecost -l app=network-costs --tail=20

# Local Store (agent-aggregator buffer)
kubectl logs -n kubecost -l app.kubernetes.io/name=local-store --tail=20
```

## 4. Allocation API — Cost by Namespace

```bash
# Last 24 hours, all namespaces
curl -s 'http://localhost:9090/model/allocation?window=1d&aggregate=namespace&accumulate=true' | jq .

# Last 7 days, all namespaces
curl -s 'http://localhost:9090/model/allocation?window=7d&aggregate=namespace&accumulate=true' | jq .

# Filter: strimzi namespace only (last 24h)
curl -s 'http://localhost:9090/model/allocation?window=1d&aggregate=namespace&filterNamespaces=strimzi&accumulate=true' | jq .

# Filter: kube-system namespace only
curl -s 'http://localhost:9090/model/allocation?window=1d&aggregate=namespace&filterNamespaces=kube-system&accumulate=true' | jq .
```

## 5. Allocation API — Cost by Label

```bash
# By app label (shows kafka, etc.)
curl -s 'http://localhost:9090/model/allocation?window=7d&aggregate=label:app&accumulate=true' | jq .

# By team label
curl -s 'http://localhost:9090/model/allocation?window=7d&aggregate=label:team&accumulate=true' | jq .

# By environment label
curl -s 'http://localhost:9090/model/allocation?window=7d&aggregate=label:environment&accumulate=true' | jq .

# By cost-center label
curl -s 'http://localhost:9090/model/allocation?window=7d&aggregate=label:cost-center&accumulate=true' | jq .
```

## 6. Allocation API — Cost by Controller and Pod

```bash
# By controller (deployments, statefulsets, daemonsets)
curl -s 'http://localhost:9090/model/allocation?window=1d&aggregate=controller&accumulate=true' | jq .

# By pod
curl -s 'http://localhost:9090/model/allocation?window=1d&aggregate=pod&filterNamespaces=strimzi&accumulate=true' | jq .
```

## 7. Assets API — Infrastructure Costs

```bash
# By asset type (Node, Disk, LoadBalancer, etc.)
curl -s 'http://localhost:9090/model/assets?window=1d&aggregate=type&accumulate=true' | jq .

# By node name
curl -s 'http://localhost:9090/model/assets?window=1d&aggregate=name&filterTypes=Node&accumulate=true' | jq .

# By cluster
curl -s 'http://localhost:9090/model/assets?window=7d&aggregate=cluster&accumulate=true' | jq .
```

## 8. Cloud Cost API — Azure Out-of-Cluster

```bash
# By Azure service (requires Cost Management export configured)
curl -s 'http://localhost:9090/model/cloudCost?window=7d&aggregate=service' | jq .

# By provider
curl -s 'http://localhost:9090/model/cloudCost?window=7d&aggregate=provider' | jq .
```

## 9. Health and Diagnostics

```bash
# Health endpoint
curl -s http://localhost:9090/healthz

# Diagnostics
curl -s http://localhost:9090/model/diagnostic | jq .

# Cluster info
curl -s http://localhost:9090/model/clusterInfo | jq .

# Kubecost version
curl -s http://localhost:9090/model/getConfigs | jq '.clusterName, .currencyCode'
```

## 10. Budgets

```bash
# List all budgets
curl -s http://localhost:9090/model/budgets | jq .
```

## 11. Savings / Optimization Recommendations

```bash
# Container right-sizing recommendations
curl -s 'http://localhost:9090/model/savings/requestSizing?window=48h&targetCPUUtilization=0.7&targetRAMUtilization=0.7' | jq .
```

## 12. Network Costs

```bash
# Verify network-costs DaemonSet is collecting data
kubectl logs -n kubecost -l app=network-costs --tail=5

# Network traffic costs by namespace
curl -s 'http://localhost:9090/model/allocation?window=1d&aggregate=namespace&accumulate=true' | jq '.data[0] | to_entries[] | {namespace: .key, networkCost: .value.networkCost}'
```

## 13. Quick Summary — One-Liner

```bash
# Top 5 most expensive namespaces (last 24h)
curl -s 'http://localhost:9090/model/allocation?window=1d&aggregate=namespace&accumulate=true' | \
  jq -r '.data[0] | to_entries | sort_by(-.value.totalCost) | .[:5][] | "\(.key): $\(.value.totalCost | . * 100 | round / 100)"'
```
