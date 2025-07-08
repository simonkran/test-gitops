# Azure Key Vault Setup Guide

## Prerequisites
1. Azure Key Vault created
2. External Secrets Operator installed in cluster
3. Azure Workload Identity enabled on AKS cluster

## Step 1: Store Secrets in Azure Key Vault

```bash
# Set variables
KEYVAULT_NAME="your-keyvault-name"
ACR_NAME="your-registry-name"

# Store ACR credentials in Key Vault
az keyvault secret set --vault-name $KEYVAULT_NAME --name "acr-server" --value "${ACR_NAME}.azurecr.io"
az keyvault secret set --vault-name $KEYVAULT_NAME --name "acr-username" --value "your-acr-username"
az keyvault secret set --vault-name $KEYVAULT_NAME --name "acr-password" --value "your-acr-password"

# Optional: Store Docker Hub credentials
az keyvault secret set --vault-name $KEYVAULT_NAME --name "dockerhub-username" --value "your-dockerhub-username"
az keyvault secret set --vault-name $KEYVAULT_NAME --name "dockerhub-password" --value "your-dockerhub-password"
```

## Step 2: Create Azure Managed Identity

```bash
# Create managed identity
IDENTITY_NAME="aks-keyvault-identity"
RESOURCE_GROUP="your-resource-group"

az identity create --name $IDENTITY_NAME --resource-group $RESOURCE_GROUP

# Get identity details
IDENTITY_CLIENT_ID=$(az identity show --name $IDENTITY_NAME --resource-group $RESOURCE_GROUP --query clientId -o tsv)
IDENTITY_PRINCIPAL_ID=$(az identity show --name $IDENTITY_NAME --resource-group $RESOURCE_GROUP --query principalId -o tsv)

echo "Client ID: $IDENTITY_CLIENT_ID"
echo "Principal ID: $IDENTITY_PRINCIPAL_ID"
```

## Step 3: Grant Key Vault Access

```bash
# Grant Key Vault access to managed identity
az keyvault set-policy \
  --name $KEYVAULT_NAME \
  --object-id $IDENTITY_PRINCIPAL_ID \
  --secret-permissions get list
```

## Step 4: Configure Workload Identity

```bash
# Create federated credential for workload identity
CLUSTER_NAME="your-aks-cluster"
NAMESPACE="default"
SERVICE_ACCOUNT="workload-identity-sa"

az identity federated-credential create \
  --name "aks-federated-credential" \
  --identity-name $IDENTITY_NAME \
  --resource-group $RESOURCE_GROUP \
  --issuer "https://oidc.prod-aks.azure.com/${CLUSTER_ISSUER_URL}/" \
  --subject "system:serviceaccount:${NAMESPACE}:${SERVICE_ACCOUNT}"
```

## Step 5: Update Configuration Files

Replace placeholders in the following files:
- `workload-identity.yaml`: Update `YOUR_MANAGED_IDENTITY_CLIENT_ID`
- `external-secrets.yaml`: Update `YOUR-KEYVAULT-NAME`

## Step 6: Install External Secrets Operator

```bash
# Add External Secrets Operator Helm repo
helm repo add external-secrets https://charts.external-secrets.io

# Install External Secrets Operator
helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets-system \
  --create-namespace \
  --set installCRDs=true
```

## Verification

```bash
# Check if secrets are created
kubectl get secrets -n default | grep credentials

# Check External Secrets status
kubectl get externalsecrets -n default

# Check secret content (should show base64 encoded .dockerconfigjson)
kubectl get secret acr-credentials -o yaml
```

## Common Issues

1. **Workload Identity not working**: Ensure federated credential is properly configured
2. **Key Vault access denied**: Check that managed identity has proper permissions
3. **External Secrets not syncing**: Verify External Secrets Operator is running
4. **Wrong secret format**: Ensure Key Vault secrets are stored as strings, not JSON

## Environment-Specific Key Vaults

For production, consider using separate Key Vaults per environment:
- `keyvault-dev` for development
- `keyvault-stage` for staging  
- `keyvault-prod` for production

Update the `vaultUrl` in overlays accordingly.
