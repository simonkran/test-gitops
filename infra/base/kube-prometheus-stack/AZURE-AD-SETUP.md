# Grafana Azure AD Setup Guide

## Prerequisites
- Azure AD tenant with admin access
- Azure Key Vault configured
- External Secrets Operator deployed
- kube-prometheus-stack deployed

## Step 1: Register Azure AD Application

### Using Azure Portal:
1. Navigate to Azure Active Directory → App registrations
2. Click "New registration"
3. Configure application:
   - **Name**: `Grafana-Monitoring`
   - **Supported account types**: Accounts in this organizational directory only
   - **Redirect URI**: `https://grafana.asia.example.com/login/azuread` (replace with your domain)

### Using Azure CLI:
```bash
# Set variables
GRAFANA_DOMAIN="grafana.asia.example.com"  # Replace with your domain
REDIRECT_URI="https://${GRAFANA_DOMAIN}/login/azuread"

# Create app registration
az ad app create \
  --display-name "Grafana-Monitoring" \
  --web-redirect-uris "$REDIRECT_URI" \
  --web-home-page-url "https://${GRAFANA_DOMAIN}"

# Get application details
APP_ID=$(az ad app list --display-name "Grafana-Monitoring" --query '[0].appId' -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)

echo "Application ID: $APP_ID"
echo "Tenant ID: $TENANT_ID"
```

## Step 2: Configure API Permissions

```bash
# Add Microsoft Graph permissions
az ad app permission add \
  --id $APP_ID \
  --api 00000003-0000-0000-c000-000000000000 \
  --api-permissions e1fe6dd8-ba31-4d61-89e7-88639da4683d=Scope  # User.Read

# Add Group.Read.All permission for role mapping
az ad app permission add \
  --id $APP_ID \
  --api 00000003-0000-0000-c000-000000000000 \
  --api-permissions 5f8c59db-677d-491f-a6b8-5f174b11ec1d=Scope  # Group.Read.All

# Grant admin consent
az ad app permission admin-consent --id $APP_ID
```

## Step 3: Create Client Secret

```bash
# Create client secret
CLIENT_SECRET=$(az ad app credential reset --id $APP_ID --display-name "grafana-secret" --query password -o tsv)

echo "Client Secret: $CLIENT_SECRET"
# ⚠️ Save this secret securely - it won't be shown again!
```

## Step 4: Create Azure AD Groups (Optional but Recommended)

```bash
# Create groups for role-based access
az ad group create --display-name "Grafana-Admins" --mail-nickname "grafana-admins"
az ad group create --display-name "Grafana-Editors" --mail-nickname "grafana-editors" 
az ad group create --display-name "Grafana-Viewers" --mail-nickname "grafana-viewers"

# Get group object IDs
ADMIN_GROUP_ID=$(az ad group show --group "Grafana-Admins" --query id -o tsv)
EDITOR_GROUP_ID=$(az ad group show --group "Grafana-Editors" --query id -o tsv)
VIEWER_GROUP_ID=$(az ad group show --group "Grafana-Viewers" --query id -o tsv)

echo "Admin Group ID: $ADMIN_GROUP_ID"
echo "Editor Group ID: $EDITOR_GROUP_ID"
echo "Viewer Group ID: $VIEWER_GROUP_ID"
```

## Step 5: Add Users to Groups

```bash
# Add users to appropriate groups
az ad group member add --group "Grafana-Admins" --member-id "user-object-id"
az ad group member add --group "Grafana-Editors" --member-id "user-object-id"
az ad group member add --group "Grafana-Viewers" --member-id "user-object-id"

# Or via Azure Portal: Azure AD → Groups → [Group Name] → Members → Add members
```

## Step 6: Store Secrets in Azure Key Vault

```bash
# Set Key Vault name
KEYVAULT_NAME="your-keyvault-name"  # Replace with your Key Vault

# Store Azure AD configuration
az keyvault secret set --vault-name $KEYVAULT_NAME --name "grafana-azure-tenant-id" --value "$TENANT_ID"
az keyvault secret set --vault-name $KEYVAULT_NAME --name "grafana-azure-client-id" --value "$APP_ID"
az keyvault secret set --vault-name $KEYVAULT_NAME --name "grafana-azure-client-secret" --value "$CLIENT_SECRET"

# Store group IDs (if using groups)
az keyvault secret set --vault-name $KEYVAULT_NAME --name "grafana-admin-group-id" --value "$ADMIN_GROUP_ID"
az keyvault secret set --vault-name $KEYVAULT_NAME --name "grafana-editor-group-id" --value "$EDITOR_GROUP_ID"
az keyvault secret set --vault-name $KEYVAULT_NAME --name "grafana-viewer-group-id" --value "$VIEWER_GROUP_ID"
```

## Step 7: Update Configuration Files

### Update Key Vault name:
```bash
# In cluster-config/registry-credentials/external-secrets.yaml
# Replace: YOUR-KEYVAULT-NAME with your actual Key Vault name
```

### Update domains:
```bash
# In infrastructure/kube-prometheus-stack/release.yaml
# Replace: grafana.example.com with your actual domain

# In infrastructure/overlays/dev/kube-prometheus-stack-dev-patch.yaml  
# Replace: grafana-dev.asia.example.com with your dev domain

# In infrastructure/overlays/prod/kube-prometheus-stack-prod-patch.yaml
# Replace: grafana.asia.example.com with your prod domain
```

### Update company domain:
```bash
# In all Grafana configurations
# Replace: your-company.com with your actual company domain
```

## Step 8: Deploy and Verify

### Check External Secrets:
```bash
# Verify external secret is created
kubectl get externalsecret grafana-azure-ad-secret -n monitoring

# Check if secret is populated
kubectl get secret grafana-azure-ad -n monitoring
kubectl describe secret grafana-azure-ad -n monitoring
```

### Check Grafana Pod:
```bash
# Check Grafana pods are running
kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana

# Check Grafana logs for Azure AD configuration
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana | grep -i azuread
```

### Test Authentication:
1. Navigate to your Grafana URL (e.g., `https://grafana.asia.example.com`)
2. Click "Sign in with Azure AD"
3. Authenticate with your corporate credentials
4. Verify your role based on group membership

## Step 9: Role Mapping Verification

### Check user roles in Grafana:
1. Login as admin user
2. Go to Configuration → Users
3. Verify users have correct roles based on Azure AD group membership

### Role mapping logic:
- **Admin Group Member** → Grafana Admin role
- **Editor Group Member** → Grafana Editor role  
- **All others** → Grafana Viewer role (default)

## Troubleshooting

### Common Issues:

1. **"Invalid redirect URI"**
   - Verify redirect URI in Azure AD matches Grafana domain exactly
   - Check for HTTP vs HTTPS mismatch

2. **"Insufficient permissions"**
   - Ensure User.Read and Group.Read.All permissions are granted
   - Verify admin consent was provided

3. **"Secret not found"**
   - Check External Secrets Operator is running
   - Verify Key Vault permissions for managed identity
   - Check secret names match exactly

4. **"Role mapping not working"**
   - Verify group IDs are correct
   - Check user is member of expected groups
   - Review Grafana logs for role assignment messages

### Debug Commands:
```bash
# Check External Secrets Operator logs
kubectl logs -n external-secrets-system -l app.kubernetes.io/name=external-secrets

# Check Grafana configuration
kubectl exec -n monitoring deployment/kube-prometheus-stack-grafana -- cat /etc/grafana/grafana.ini

# Check environment variables
kubectl exec -n monitoring deployment/kube-prometheus-stack-grafana -- env | grep GF_AUTH
```

## Security Considerations

1. **Client Secret Rotation**: Azure AD client secrets expire - set up rotation
2. **Group Management**: Regularly review group memberships
3. **Network Security**: Use IP whitelisting for production
4. **Audit Logging**: Enable Grafana audit logs
5. **Session Security**: Configure appropriate session timeouts

## Maintenance

### Rotate Client Secret:
```bash
# Generate new secret
NEW_SECRET=$(az ad app credential reset --id $APP_ID --display-name "grafana-secret-$(date +%Y%m%d)" --query password -o tsv)

# Update Key Vault
az keyvault secret set --vault-name $KEYVAULT_NAME --name "grafana-azure-client-secret" --value "$NEW_SECRET"

# External Secrets will automatically sync the new secret
```

Your Grafana Azure AD integration is now complete! 🎉
