#!/usr/bin/env bash
#
# Creates an Azure Service Principal with the roles required for Kubecost
# to read Azure pricing data and Cost Management exports.
#
# Prerequisites:
#   - Azure CLI authenticated (az login)
#   - Sufficient permissions to create SPs and role assignments on the subscription
#
# Usage:
#   chmod +x 01-create-azure-sp.sh
#   ./01-create-azure-sp.sh
#
set -euo pipefail

SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID:-$(az account show --query id -o tsv)}"
SP_NAME="kubecost-billing-reader"

echo "==> Using subscription: ${SUBSCRIPTION_ID}"

echo "==> Creating Service Principal '${SP_NAME}'..."
SP_OUTPUT=$(az ad sp create-for-rbac \
  --name "${SP_NAME}" \
  --role "Cost Management Reader" \
  --scopes "/subscriptions/${SUBSCRIPTION_ID}" \
  --output json)

CLIENT_ID=$(echo "${SP_OUTPUT}" | jq -r '.appId')
CLIENT_SECRET=$(echo "${SP_OUTPUT}" | jq -r '.password')
TENANT_ID=$(echo "${SP_OUTPUT}" | jq -r '.tenant')

echo "==> Assigning 'Billing Reader' role (for retail pricing API access)..."
az role assignment create \
  --assignee "${CLIENT_ID}" \
  --role "Billing Reader" \
  --scope "/subscriptions/${SUBSCRIPTION_ID}" \
  --output none 2>/dev/null || echo "    (Billing Reader may require elevated permissions — Cost Management Reader is sufficient for most use cases)"

echo "==> Assigning 'Reader' role (for resource metadata enumeration)..."
az role assignment create \
  --assignee "${CLIENT_ID}" \
  --role "Reader" \
  --scope "/subscriptions/${SUBSCRIPTION_ID}" \
  --output none

echo ""
echo "================================================================"
echo "  Service Principal created successfully"
echo "================================================================"
echo "  Client ID:       ${CLIENT_ID}"
echo "  Client Secret:   ${CLIENT_SECRET}"
echo "  Tenant ID:       ${TENANT_ID}"
echo "  Subscription ID: ${SUBSCRIPTION_ID}"
echo "================================================================"
echo ""

STORAGE_ACCOUNT="kubecostexports$(openssl rand -hex 4)"
RESOURCE_GROUP="${KUBECOST_RG:-kubecost-exports-rg}"
CONTAINER_NAME="costexports"
LOCATION="${AZURE_LOCATION:-eastus}"

echo "==> Creating resource group '${RESOURCE_GROUP}' for cost export storage..."
az group create \
  --name "${RESOURCE_GROUP}" \
  --location "${LOCATION}" \
  --output none

echo "==> Creating storage account '${STORAGE_ACCOUNT}'..."
az storage account create \
  --name "${STORAGE_ACCOUNT}" \
  --resource-group "${RESOURCE_GROUP}" \
  --location "${LOCATION}" \
  --sku Standard_LRS \
  --kind StorageV2 \
  --output none

echo "==> Creating blob container '${CONTAINER_NAME}'..."
az storage container create \
  --name "${CONTAINER_NAME}" \
  --account-name "${STORAGE_ACCOUNT}" \
  --output none

STORAGE_ACCESS_KEY=$(az storage account keys list \
  --resource-group "${RESOURCE_GROUP}" \
  --account-name "${STORAGE_ACCOUNT}" \
  --query '[0].value' -o tsv)

echo "==> Granting SP 'Storage Blob Data Contributor' on the storage account..."
STORAGE_ACCOUNT_ID=$(az storage account show \
  --name "${STORAGE_ACCOUNT}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query id -o tsv)

az role assignment create \
  --assignee "${CLIENT_ID}" \
  --role "Storage Blob Data Contributor" \
  --scope "${STORAGE_ACCOUNT_ID}" \
  --output none

echo ""
echo "================================================================"
echo "  Storage Account for Cost Exports"
echo "================================================================"
echo "  Storage Account:  ${STORAGE_ACCOUNT}"
echo "  Container:        ${CONTAINER_NAME}"
echo "  Access Key:       ${STORAGE_ACCESS_KEY}"
echo "================================================================"
echo ""
echo "==> NEXT STEP: Create a Cost Management export in the Azure Portal:"
echo "    1. Go to Cost Management > Exports"
echo "    2. Create a new daily export of 'Actual Cost'"
echo "    3. Set storage account to '${STORAGE_ACCOUNT}', container '${CONTAINER_NAME}'"
echo "    4. Choose 'CSV' format, daily granularity"
echo ""

cat <<EOF > /tmp/kubecost-azure-credentials.env
AZURE_SUBSCRIPTION_ID=${SUBSCRIPTION_ID}
AZURE_TENANT_ID=${TENANT_ID}
AZURE_CLIENT_ID=${CLIENT_ID}
AZURE_CLIENT_SECRET=${CLIENT_SECRET}
AZURE_STORAGE_ACCOUNT=${STORAGE_ACCOUNT}
AZURE_STORAGE_ACCESS_KEY=${STORAGE_ACCESS_KEY}
AZURE_STORAGE_CONTAINER=${CONTAINER_NAME}
EOF

echo "==> Credentials saved to /tmp/kubecost-azure-credentials.env"
echo "    Source this file before running 02-create-secret.sh"
