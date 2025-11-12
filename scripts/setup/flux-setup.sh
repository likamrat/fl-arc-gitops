#!/bin/bash

################################################################################
# Flux v2 GitOps Setup for Azure Arc-enabled Kubernetes
# 
# This script installs and configures Flux v2 on an Azure Arc-enabled cluster
# with support for:
# - Git repository syncing
# - Image automation (OCI artifact detection)
# - Kustomizations with dependencies
# - GPU-ORAS BYO model deployments
#
# Prerequisites:
# - Azure Arc-enabled Kubernetes cluster
# - Azure CLI installed and logged in
# - kubectl configured to access the cluster
#
# Usage:
#   ./scripts/flux-setup.sh
################################################################################

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
RESOURCE_GROUP="Foundry-Arc"
CLUSTER_NAME="ROG-FL-02"
CLUSTER_TYPE="connectedClusters"  # For Arc-enabled K8s (use "managedClusters" for AKS)
FLUX_NAMESPACE="flux-system"
EXTENSION_NAME="flux"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Flux v2 GitOps Setup for Azure Arc-enabled Kubernetes     ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Step 1: Verify Prerequisites
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 1: Verifying Prerequisites${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Check Azure CLI
if ! command -v az &> /dev/null; then
    echo -e "${RED}✗ Azure CLI not found${NC}"
    echo -e "${YELLOW}  Please install Azure CLI: https://docs.microsoft.com/cli/azure/install-azure-cli${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Azure CLI found: $(az version --query '\"azure-cli\"' -o tsv)${NC}"

# Check kubectl
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}✗ kubectl not found${NC}"
    echo -e "${YELLOW}  Please install kubectl${NC}"
    exit 1
fi
echo -e "${GREEN}✓ kubectl found: $(kubectl version --client -o json | jq -r '.clientVersion.gitVersion')${NC}"

# Check cluster connectivity
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}✗ Cannot connect to Kubernetes cluster${NC}"
    echo -e "${YELLOW}  Please configure kubectl to access your cluster${NC}"
    exit 1
fi
CLUSTER_VERSION=$(kubectl version -o json | jq -r '.serverVersion.gitVersion')
echo -e "${GREEN}✓ Connected to Kubernetes cluster (${CLUSTER_VERSION})${NC}"

# Check Azure login
if ! az account show &> /dev/null; then
    echo -e "${RED}✗ Not logged into Azure${NC}"
    echo -e "${YELLOW}  Please run 'az login'${NC}"
    exit 1
fi
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
echo -e "${GREEN}✓ Logged into Azure${NC}"
echo -e "  Subscription: ${SUBSCRIPTION_NAME}"
echo -e "  ID: ${SUBSCRIPTION_ID}"

echo ""

# Step 2: Install Azure CLI Extensions
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 2: Installing/Updating Azure CLI Extensions${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${BLUE}  Installing k8s-configuration extension...${NC}"
az extension add -n k8s-configuration --upgrade -y 2>/dev/null || true
K8S_CONFIG_VERSION=$(az extension show -n k8s-configuration --query version -o tsv)
echo -e "${GREEN}✓ k8s-configuration extension installed (v${K8S_CONFIG_VERSION})${NC}"

echo -e "${BLUE}  Installing k8s-extension extension...${NC}"
az extension add -n k8s-extension --upgrade -y 2>/dev/null || true
K8S_EXT_VERSION=$(az extension show -n k8s-extension --query version -o tsv)
echo -e "${GREEN}✓ k8s-extension extension installed (v${K8S_EXT_VERSION})${NC}"

echo ""

# Step 3: Register Azure Resource Providers
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 3: Registering Azure Resource Providers${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

for provider in "Microsoft.Kubernetes" "Microsoft.KubernetesConfiguration" "Microsoft.ContainerService"; do
    echo -e "${BLUE}  Registering ${provider}...${NC}"
    az provider register --namespace ${provider} --wait 2>/dev/null || true
    STATE=$(az provider show -n ${provider} --query registrationState -o tsv)
    echo -e "${GREEN}✓ ${provider}: ${STATE}${NC}"
done

echo ""

# Step 4: Check if Flux Extension Already Exists
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 4: Checking Existing Flux Extension${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

EXTENSION_EXISTS=$(az k8s-extension list \
    -g ${RESOURCE_GROUP} \
    -c ${CLUSTER_NAME} \
    -t ${CLUSTER_TYPE} \
    --query "[?extensionType=='microsoft.flux'].name" -o tsv 2>/dev/null || echo "")

if [ ! -z "$EXTENSION_EXISTS" ]; then
    echo -e "${YELLOW}⚠ Flux extension already exists: ${EXTENSION_EXISTS}${NC}"
    echo ""
    read -p "Do you want to delete and reinstall? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}  Deleting existing Flux extension...${NC}"
        az k8s-extension delete \
            -g ${RESOURCE_GROUP} \
            -c ${CLUSTER_NAME} \
            -t ${CLUSTER_TYPE} \
            -n ${EXTENSION_EXISTS} \
            --yes
        echo -e "${GREEN}✓ Existing Flux extension deleted${NC}"
        echo ""
        echo -e "${YELLOW}  Waiting 30 seconds for cleanup...${NC}"
        sleep 30
    else
        echo -e "${YELLOW}⚠ Keeping existing extension, will attempt update${NC}"
        EXTENSION_NAME="${EXTENSION_EXISTS}"
    fi
else
    echo -e "${GREEN}✓ No existing Flux extension found${NC}"
fi

echo ""

# Step 5: Install/Update Flux Extension
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 5: Installing Flux v2 Extension${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${BLUE}Configuration:${NC}"
echo -e "  • Resource Group: ${RESOURCE_GROUP}"
echo -e "  • Cluster Name: ${CLUSTER_NAME}"
echo -e "  • Cluster Type: ${CLUSTER_TYPE}"
echo -e "  • Extension Name: ${EXTENSION_NAME}"
echo -e "  • Namespace: ${FLUX_NAMESPACE}"
echo ""
echo -e "${YELLOW}Features:${NC}"
echo -e "  ✓ Source Controller (Git, Helm, Bucket)"
echo -e "  ✓ Kustomize Controller"
echo -e "  ✓ Helm Controller"
echo -e "  ✓ Notification Controller"
echo -e "  ✓ Image Reflector Controller (OCI artifact detection)"
echo -e "  ✓ Image Automation Controller (Git auto-update)"
echo ""

if [ -z "$EXTENSION_EXISTS" ]; then
    echo -e "${BLUE}Creating Flux extension...${NC}"
    az k8s-extension create \
        --resource-group ${RESOURCE_GROUP} \
        --cluster-name ${CLUSTER_NAME} \
        --cluster-type ${CLUSTER_TYPE} \
        --name ${EXTENSION_NAME} \
        --extension-type microsoft.flux \
        --scope cluster \
        --config image-automation-controller.enabled=true \
        --config image-reflector-controller.enabled=true \
        --config source-controller.enabled=true \
        --config kustomize-controller.enabled=true \
        --config helm-controller.enabled=true \
        --config notification-controller.enabled=true
else
    echo -e "${BLUE}Updating Flux extension...${NC}"
    az k8s-extension update \
        --resource-group ${RESOURCE_GROUP} \
        --cluster-name ${CLUSTER_NAME} \
        --cluster-type ${CLUSTER_TYPE} \
        --name ${EXTENSION_NAME} \
        --config image-automation-controller.enabled=true \
        --config image-reflector-controller.enabled=true
fi

echo -e "${GREEN}✓ Flux extension installed/updated${NC}"

echo ""

# Step 6: Verify Flux Installation
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 6: Verifying Flux Installation${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${BLUE}Waiting for Flux pods to be ready...${NC}"
echo -e "${YELLOW}(This may take 2-3 minutes)${NC}"
echo ""

# Wait for namespace
for i in {1..30}; do
    if kubectl get namespace ${FLUX_NAMESPACE} &> /dev/null; then
        break
    fi
    echo -n "."
    sleep 2
done
echo ""

if ! kubectl get namespace ${FLUX_NAMESPACE} &> /dev/null; then
    echo -e "${RED}✗ Flux namespace not created${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Flux namespace created: ${FLUX_NAMESPACE}${NC}"

# Wait for all pods to be ready
echo ""
echo -e "${BLUE}Checking Flux controller pods...${NC}"

kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/part-of=flux \
    -n ${FLUX_NAMESPACE} \
    --timeout=180s 2>/dev/null || true

echo ""
echo -e "${BLUE}Pod Status:${NC}"
kubectl get pods -n ${FLUX_NAMESPACE} -o wide

echo ""

# Check each controller
CONTROLLERS=(
    "source-controller"
    "kustomize-controller"
    "helm-controller"
    "notification-controller"
    "image-reflector-controller"
    "image-automation-controller"
    "fluxconfig-agent"
    "fluxconfig-controller"
)

echo -e "${BLUE}Controller Status:${NC}"
ALL_READY=true
for controller in "${CONTROLLERS[@]}"; do
    READY=$(kubectl get pods -n ${FLUX_NAMESPACE} -l app=${controller} -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
    if [[ "$READY" == *"True"* ]]; then
        echo -e "${GREEN}✓ ${controller}${NC}"
    else
        echo -e "${YELLOW}⚠ ${controller} (not ready yet)${NC}"
        ALL_READY=false
    fi
done

echo ""

# Step 7: Display Flux Extension Info
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 7: Flux Extension Information${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

az k8s-extension show \
    -g ${RESOURCE_GROUP} \
    -c ${CLUSTER_NAME} \
    -t ${CLUSTER_TYPE} \
    -n ${EXTENSION_NAME} \
    -o table

echo ""

# Step 8: Display Next Steps
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              Flux v2 Installation Complete! ✓                  ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${CYAN}Next Steps:${NC}"
echo ""
echo -e "${YELLOW}1. Create Flux Configuration${NC}"
echo -e "   Create a GitRepository source pointing to your Git repo:"
echo -e "   ${BLUE}az k8s-configuration flux create ...${NC}"
echo ""
echo -e "${YELLOW}2. Set Up Image Automation${NC}"
echo -e "   Create ImageRepository, ImagePolicy, and ImageUpdateAutomation resources"
echo -e "   to enable OCI artifact-triggered deployments"
echo ""
echo -e "${YELLOW}3. Deploy Foundry Local GPU-ORAS${NC}"
echo -e "   Apply your Kustomizations to deploy Foundry with BYO models"
echo ""
echo -e "${YELLOW}4. Monitor Flux${NC}"
echo -e "   ${BLUE}kubectl get all -n ${FLUX_NAMESPACE}${NC}"
echo -e "   ${BLUE}kubectl logs -n ${FLUX_NAMESPACE} -l app=source-controller -f${NC}"
echo ""

echo -e "${CYAN}Useful Commands:${NC}"
echo ""
echo -e "  ${YELLOW}# List all Flux configurations${NC}"
echo -e "  az k8s-configuration flux list -g ${RESOURCE_GROUP} -c ${CLUSTER_NAME} -t ${CLUSTER_TYPE}"
echo ""
echo -e "  ${YELLOW}# Check Flux extension status${NC}"
echo -e "  az k8s-extension show -g ${RESOURCE_GROUP} -c ${CLUSTER_NAME} -t ${CLUSTER_TYPE} -n ${EXTENSION_NAME}"
echo ""
echo -e "  ${YELLOW}# View Flux pods${NC}"
echo -e "  kubectl get pods -n ${FLUX_NAMESPACE} -w"
echo ""
echo -e "  ${YELLOW}# Check CRDs installed by Flux${NC}"
echo -e "  kubectl get crds | grep -E 'flux|toolkit|kustomize'"
echo ""

if [ "$ALL_READY" = true ]; then
    echo -e "${GREEN}✓ All Flux controllers are ready!${NC}"
else
    echo -e "${YELLOW}⚠ Some controllers are still starting up. Wait a few more minutes.${NC}"
fi

echo ""
