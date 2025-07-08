#!/bin/bash
# Azure Key Vault Registry Credentials Validation Script

set -e

echo "🔐 Validating Azure Key Vault Registry Credentials Setup..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to check if command exists
check_command() {
    if command -v $1 &> /dev/null; then
        echo -e "${GREEN}✓${NC} $1 is installed"
    else
        echo -e "${RED}✗${NC} $1 is not installed"
        exit 1
    fi
}

# Function to check Kubernetes resource
check_k8s_resource() {
    local resource_type=$1
    local resource_name=$2
    local namespace=${3:-default}
    
    if kubectl get $resource_type $resource_name -n $namespace &> /dev/null; then
        echo -e "${GREEN}✓${NC} $resource_type/$resource_name exists in namespace $namespace"
    else
        echo -e "${RED}✗${NC} $resource_type/$resource_name not found in namespace $namespace"
    fi
}

# Check prerequisites
echo -e "\n${YELLOW}Checking Prerequisites...${NC}"
check_command kubectl
check_command az

# Check if connected to cluster
if kubectl cluster-info &> /dev/null; then
    echo -e "${GREEN}✓${NC} Connected to Kubernetes cluster"
    CLUSTER_NAME=$(kubectl config current-context)
    echo -e "  Current cluster: $CLUSTER_NAME"
else
    echo -e "${RED}✗${NC} Not connected to Kubernetes cluster"
    exit 1
fi

# Check External Secrets Operator
echo -e "\n${YELLOW}Checking External Secrets Operator...${NC}"
if kubectl get namespace external-secrets-system &> /dev/null; then
    echo -e "${GREEN}✓${NC} external-secrets-system namespace exists"
    
    # Check if ESO is running
    ESO_PODS=$(kubectl get pods -n external-secrets-system -l app.kubernetes.io/name=external-secrets --no-headers 2>/dev/null | wc -l)
    if [ $ESO_PODS -gt 0 ]; then
        echo -e "${GREEN}✓${NC} External Secrets Operator is running ($ESO_PODS pods)"
    else
        echo -e "${RED}✗${NC} External Secrets Operator pods not found"
    fi
else
    echo -e "${RED}✗${NC} External Secrets Operator not installed"
fi

# Check Workload Identity
echo -e "\n${YELLOW}Checking Workload Identity...${NC}"
check_k8s_resource "serviceaccount" "workload-identity-sa" "default"

# Check if workload identity annotation exists
WI_ANNOTATION=$(kubectl get serviceaccount workload-identity-sa -n default -o jsonpath='{.metadata.annotations.azure\.workload\.identity/client-id}' 2>/dev/null || echo "")
if [ -n "$WI_ANNOTATION" ]; then
    echo -e "${GREEN}✓${NC} Workload Identity annotation found: $WI_ANNOTATION"
else
    echo -e "${YELLOW}⚠${NC} Workload Identity annotation not found - remember to update YOUR_MANAGED_IDENTITY_CLIENT_ID"
fi

# Check Key Vault resources
echo -e "\n${YELLOW}Checking Key Vault Integration...${NC}"
check_k8s_resource "secretstore" "azure-keyvault-store" "default"
check_k8s_resource "externalsecret" "acr-registry-secret" "default"

# Check if secrets are created
echo -e "\n${YELLOW}Checking Generated Secrets...${NC}"
check_k8s_resource "secret" "acr-credentials" "default"

# Check secret content
if kubectl get secret acr-credentials -n default &> /dev/null; then
    SECRET_DATA=$(kubectl get secret acr-credentials -n default -o jsonpath='{.data.\.dockerconfigjson}' 2>/dev/null)
    if [ -n "$SECRET_DATA" ] && [ "$SECRET_DATA" != "e30K" ]; then
        echo -e "${GREEN}✓${NC} acr-credentials secret contains data"
        
        # Decode and validate JSON structure
        if echo "$SECRET_DATA" | base64 -d | jq . &> /dev/null; then
            echo -e "${GREEN}✓${NC} Secret data is valid JSON"
        else
            echo -e "${RED}✗${NC} Secret data is not valid JSON"
        fi
    else
        echo -e "${YELLOW}⚠${NC} acr-credentials secret exists but appears empty"
        echo -e "  This usually means External Secrets hasn't synced yet or Key Vault access is not configured"
    fi
fi

# Check External Secret status
if kubectl get externalsecret acr-registry-secret -n default &> /dev/null; then
    ES_STATUS=$(kubectl get externalsecret acr-registry-secret -n default -o jsonpath='{.status.conditions[0].status}' 2>/dev/null || echo "Unknown")
    ES_REASON=$(kubectl get externalsecret acr-registry-secret -n default -o jsonpath='{.status.conditions[0].reason}' 2>/dev/null || echo "Unknown")
    
    if [ "$ES_STATUS" = "True" ]; then
        echo -e "${GREEN}✓${NC} External Secret is syncing successfully"
    else
        echo -e "${RED}✗${NC} External Secret sync failed: $ES_REASON"
        echo -e "  Check: kubectl describe externalsecret acr-registry-secret -n default"
    fi
fi

# Configuration checklist
echo -e "\n${YELLOW}Configuration Checklist:${NC}"
echo -e "□ Update workload-identity.yaml with your Managed Identity Client ID"
echo -e "□ Update external-secrets.yaml with your Key Vault name"
echo -e "□ Store secrets in Azure Key Vault (acr-server, acr-username, acr-password)"
echo -e "□ Configure federated credential for workload identity"
echo -e "□ Grant Key Vault access to managed identity"

echo -e "\n${GREEN}Validation complete!${NC}"
echo -e "\nFor troubleshooting, check:"
echo -e "  kubectl logs -n external-secrets-system -l app.kubernetes.io/name=external-secrets"
echo -e "  kubectl describe externalsecret acr-registry-secret -n default"
