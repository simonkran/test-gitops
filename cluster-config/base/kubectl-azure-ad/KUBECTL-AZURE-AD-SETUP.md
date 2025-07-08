# kubectl Azure AD Authentication Setup Guide

## Overview
This guide configures kubectl to authenticate against AKS clusters using Azure AD, providing enterprise-grade authentication and RBAC.

## Prerequisites
- Azure AD tenant with admin access
- AKS clusters with Azure AD integration enabled
- Azure CLI and kubectl installed locally

## Step 1: Enable Azure AD Integration on AKS Clusters

### For New AKS Clusters:
```bash
# Set variables
RESOURCE_GROUP="your-resource-group"
CLUSTER_NAME="your-cluster-name"
LOCATION="eastasia"  # or westeurope

# Create AKS cluster with Azure AD integration
az aks create \
  --resource-group $RESOURCE_GROUP \
  --name $CLUSTER_NAME \
  --location $LOCATION \
  --enable-aad \
  --enable-azure-rbac \
  --generate-ssh-keys
```

### For Existing AKS Clusters:
```bash
# Enable Azure AD integration on existing cluster
az aks update \
  --resource-group $RESOURCE_GROUP \
  --name $CLUSTER_NAME \
  --enable-aad \
  --enable-azure-rbac
```

## Step 2: Create Azure AD Groups

```bash
# Create Azure AD groups for different access levels
az ad group create --display-name "k8s-cluster-admins" --mail-nickname "k8s-cluster-admins"
az ad group create --display-name "k8s-developers" --mail-nickname "k8s-developers"
az ad group create --display-name "k8s-operators" --mail-nickname "k8s-operators"
az ad group create --display-name "k8s-viewers" --mail-nickname "k8s-viewers"

# Get group object IDs
CLUSTER_ADMIN_GROUP_ID=$(az ad group show --group "k8s-cluster-admins" --query id -o tsv)
DEVELOPER_GROUP_ID=$(az ad group show --group "k8s-developers" --query id -o tsv)
OPERATOR_GROUP_ID=$(az ad group show --group "k8s-operators" --query id -o tsv)
VIEWER_GROUP_ID=$(az ad group show --group "k8s-viewers" --query id -o tsv)

echo "Cluster Admin Group ID: $CLUSTER_ADMIN_GROUP_ID"
echo "Developer Group ID: $DEVELOPER_GROUP_ID"
echo "Operator Group ID: $OPERATOR_GROUP_ID"
echo "Viewer Group ID: $VIEWER_GROUP_ID"
```

## Step 3: Add Users to Azure AD Groups

```bash
# Get user object IDs
USER1_ID=$(az ad user show --id "user1@yourcompany.com" --query id -o tsv)
USER2_ID=$(az ad user show --id "user2@yourcompany.com" --query id -o tsv)

# Add users to appropriate groups
az ad group member add --group "k8s-cluster-admins" --member-id $USER1_ID
az ad group member add --group "k8s-developers" --member-id $USER2_ID
az ad group member add --group "k8s-operators" --member-id $USER1_ID
```

## Step 4: Update RBAC Configuration Files

### Update Group IDs in RBAC files:
Replace the placeholder group IDs in the following files:
- `azure-ad-rbac.yaml`
- `namespace-rbac.yaml`
- Environment-specific patches

```bash
# Example replacements needed:
# CLUSTER_ADMIN_GROUP_ID → $CLUSTER_ADMIN_GROUP_ID
# DEVELOPER_GROUP_ID → $DEVELOPER_GROUP_ID
# OPERATOR_GROUP_ID → $OPERATOR_GROUP_ID
# VIEWER_GROUP_ID → $VIEWER_GROUP_ID
```

### Automated replacement script:
```bash
#!/bin/bash
# Replace placeholder group IDs with actual values

CLUSTER_ADMIN_GROUP_ID="your-cluster-admin-group-id"
DEVELOPER_GROUP_ID="your-developer-group-id"
OPERATOR_GROUP_ID="your-operator-group-id"
VIEWER_GROUP_ID="your-viewer-group-id"

# Update azure-ad-rbac.yaml
sed -i "s/CLUSTER_ADMIN_GROUP_ID/$CLUSTER_ADMIN_GROUP_ID/g" cluster-config/kubectl-azure-ad/azure-ad-rbac.yaml
sed -i "s/DEVELOPER_GROUP_ID/$DEVELOPER_GROUP_ID/g" cluster-config/kubectl-azure-ad/azure-ad-rbac.yaml
sed -i "s/OPERATOR_GROUP_ID/$OPERATOR_GROUP_ID/g" cluster-config/kubectl-azure-ad/azure-ad-rbac.yaml
sed -i "s/VIEWER_GROUP_ID/$VIEWER_GROUP_ID/g" cluster-config/kubectl-azure-ad/azure-ad-rbac.yaml

# Update namespace-rbac.yaml
sed -i "s/DEVELOPER_GROUP_ID/$DEVELOPER_GROUP_ID/g" cluster-config/kubectl-azure-ad/namespace-rbac.yaml
sed -i "s/OPERATOR_GROUP_ID/$OPERATOR_GROUP_ID/g" cluster-config/kubectl-azure-ad/namespace-rbac.yaml

# Update environment patches
sed -i "s/DEVELOPER_GROUP_ID/$DEVELOPER_GROUP_ID/g" cluster-config/overlays/*/kubectl-rbac-*-patch.yaml
```

## Step 5: Deploy RBAC Configuration

After updating the group IDs, commit and push your changes. Flux will automatically apply the RBAC configurations to your clusters.

```bash
# Verify deployment
kubectl get clusterrole | grep azure-ad
kubectl get clusterrolebinding | grep azure-ad
kubectl get rolebinding -A | grep azure-ad
```

## Step 6: Configure kubectl for Users

### Get Cluster Credentials:
```bash
# Get credentials for the cluster
az aks get-credentials \
  --resource-group $RESOURCE_GROUP \
  --name $CLUSTER_NAME \
  --admin  # Use admin for initial setup
```

### User Authentication Setup:
Each user needs to configure their kubectl:

```bash
# Users get cluster credentials (without --admin flag)
az aks get-credentials \
  --resource-group $RESOURCE_GROUP \
  --name $CLUSTER_NAME \
  --overwrite-existing
```

## Step 7: Install kubelogin Plugin

Users need the kubelogin plugin for Azure AD authentication:

### Install kubelogin:
```bash
# Install kubelogin
curl -LO https://github.com/Azure/kubelogin/releases/latest/download/kubelogin-linux-amd64.zip
unzip kubelogin-linux-amd64.zip
sudo mv bin/linux_amd64/kubelogin /usr/local/bin/

# Convert kubeconfig to use kubelogin
kubelogin convert-kubeconfig -l azurecli
```

### For Windows:
```powershell
# Install via Chocolatey
choco install kubelogin

# Or download directly
Invoke-WebRequest -Uri "https://github.com/Azure/kubelogin/releases/latest/download/kubelogin-win-amd64.zip" -OutFile "kubelogin.zip"
Expand-Archive kubelogin.zip
Move-Item kubelogin/bin/windows_amd64/kubelogin.exe C:/Windows/System32/

# Convert kubeconfig
kubelogin convert-kubeconfig -l azurecli
```

## Step 8: Test Authentication

### Test as different users:
```bash
# Test cluster access
kubectl get nodes
kubectl get pods -A

# Test namespace access based on role
kubectl get pods -n podinfo
kubectl create deployment test-deploy --image=nginx -n podinfo

# Test permissions
kubectl auth can-i create pods
kubectl auth can-i create nodes
kubectl auth can-i get pods --all-namespaces
```

## User Access Matrix

| Azure AD Group | Kubernetes Role | Access Level |
|----------------|-----------------|--------------|
| **k8s-cluster-admins** | cluster-admin | Full cluster access |
| **k8s-developers** | developer | App namespaces + limited cluster |
| **k8s-operators** | operator | Infrastructure + monitoring |
| **k8s-viewers** | viewer | Read-only across cluster |

## Environment-Specific Permissions

### Development Environment:
- **Developers**: Enhanced permissions, can create namespaces
- **Operators**: Full infrastructure access
- **Viewers**: Read-only access

### Production Environment:
- **Developers**: Read-only access only
- **Operators**: Full infrastructure access
- **Cluster Admins**: Full access
- **Viewers**: Read-only access

## Troubleshooting

### Common Issues:

1. **"error: You must be logged in to the server (Unauthorized)"**
   ```bash
   # Re-authenticate with Azure
   az login
   kubelogin convert-kubeconfig -l azurecli
   ```

2. **"User not found in Azure AD"**
   - Verify user exists in Azure AD tenant
   - Check user is member of appropriate group

3. **"Forbidden: User cannot perform action"**
   - Verify Azure AD group membership
   - Check RBAC bindings are applied: `kubectl get clusterrolebinding`
   - Verify group IDs match in RBAC configs

4. **"kubelogin not found"**
   ```bash
   # Install kubelogin plugin
   az aks install-cli
   ```

### Debug Commands:
```bash
# Check current user identity
kubectl auth whoami

# Test permissions
kubectl auth can-i create pods --as=system:serviceaccount:default:default

# Check RBAC
kubectl get clusterrolebinding azure-ad-developers -o yaml

# View effective permissions
kubectl describe clusterrole azure-ad-developer
```

## Security Best Practices

1. **Regular Access Review**: Review Azure AD group memberships quarterly
2. **Principle of Least Privilege**: Start with minimal permissions, add as needed
3. **Environment Separation**: Use different permission levels per environment
4. **Audit Logging**: Enable Kubernetes audit logs for compliance
5. **Multi-Factor Authentication**: Enforce MFA for Azure AD users

## User Onboarding Script:
```bash
#!/bin/bash
# Add new user to Kubernetes access

USER_EMAIL="$1"
ROLE="$2"  # developer, operator, viewer, admin

if [ -z "$USER_EMAIL" ] || [ -z "$ROLE" ]; then
  echo "Usage: $0 <user-email> <role>"
  echo "Roles: developer, operator, viewer, admin"
  exit 1
fi

# Get user object ID
USER_ID=$(az ad user show --id "$USER_EMAIL" --query id -o tsv)

if [ -z "$USER_ID" ]; then
  echo "Error: User $USER_EMAIL not found in Azure AD"
  exit 1
fi

# Add to appropriate group based on role
case $ROLE in
  "admin")
    az ad group member add --group "k8s-cluster-admins" --member-id "$USER_ID"
    echo "Added $USER_EMAIL to k8s-cluster-admins group"
    ;;
  "developer")
    az ad group member add --group "k8s-developers" --member-id "$USER_ID"
    echo "Added $USER_EMAIL to k8s-developers group"
    ;;
  "operator")
    az ad group member add --group "k8s-operators" --member-id "$USER_ID"
    echo "Added $USER_EMAIL to k8s-operators group"
    ;;
  "viewer")
    az ad group member add --group "k8s-viewers" --member-id "$USER_ID"
    echo "Added $USER_EMAIL to k8s-viewers group"
    ;;
  *)
    echo "Error: Invalid role. Use: admin, developer, operator, or viewer"
    exit 1
    ;;
esac

echo "User $USER_EMAIL has been granted $ROLE access to Kubernetes clusters"
echo "User should run: az aks get-credentials --resource-group <rg> --name <cluster>"
```

Your kubectl Azure AD authentication is now fully configured! 🎉

## Quick Start Checklist

- [ ] Create Azure AD groups
- [ ] Add users to groups  
- [ ] Update group IDs in RBAC files
- [ ] Deploy RBAC configuration via Flux
- [ ] Install kubelogin on user machines
- [ ] Test authentication and permissions
- [ ] Document access procedures
- [ ] Set up monitoring and auditing
