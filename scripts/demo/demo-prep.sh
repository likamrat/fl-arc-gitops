#!/bin/bash

################################################################################
# Demo Preparation Script
# 
# This script prepares the environment for the GitOps demo by:
# 1. Suspending GitOps on ROG-FL-02
# 2. Deleting v2.0.0 from ACR
# 3. Rolling back Git to v1.0.0
# 4. Waiting for ROG-FL-01 to rollback
# 5. Verifying final demo state
#
# Prerequisites:
# - Both clusters (rog-fl-01, rog-fl-02) are at v2.0.0
# - kubectx is installed and configured
# - Azure CLI is installed and authenticated
# - ORAS CLI is installed
################################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ACR_NAME="foundryoci"
ACR_REPO="byo-models-gpu/llama-3.2-1b-cuda"
NAMESPACE="foundry-system"
HELMRELEASE_FILE="apps/foundry-gpu-oras/helmrelease.yaml"

echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}   GitOps Demo Preparation${NC}"
echo -e "${BLUE}================================${NC}"
echo ""

# Prerequisites check
echo -e "${YELLOW}Checking prerequisites...${NC}"

# Check if kubectx is installed
if ! command -v kubectx &> /dev/null; then
  echo -e "${RED}✗ Error: kubectx is not installed${NC}"
  exit 1
fi

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
  echo -e "${RED}✗ Error: kubectl is not installed${NC}"
  exit 1
fi

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
  echo -e "${RED}✗ Error: Azure CLI is not installed${NC}"
  echo -e "${YELLOW}  Install: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli${NC}"
  exit 1
fi

# Check if Azure CLI is authenticated
if ! az account show &> /dev/null; then
  echo -e "${RED}✗ Error: Azure CLI is not authenticated${NC}"
  echo -e "${YELLOW}  Run: az login${NC}"
  exit 1
fi

# Check if ORAS CLI is installed
if ! command -v oras &> /dev/null; then
  echo -e "${RED}✗ Error: ORAS CLI is not installed${NC}"
  echo -e "${YELLOW}  Install: https://oras.land/docs/installation${NC}"
  exit 1
fi

# Check if ORAS is authenticated to ACR
if ! oras repo tags ${ACR_NAME}.azurecr.io/${ACR_REPO} &> /dev/null; then
  echo -e "${RED}✗ Error: ORAS is not authenticated to ${ACR_NAME}.azurecr.io${NC}"
  echo -e "${YELLOW}  Run: oras login ${ACR_NAME}.azurecr.io${NC}"
  exit 1
fi

# Check if git is installed
if ! command -v git &> /dev/null; then
  echo -e "${RED}✗ Error: git is not installed${NC}"
  exit 1
fi

# Check if we're in a git repository
if ! git rev-parse --is-inside-work-tree &> /dev/null; then
  echo -e "${RED}✗ Error: Not in a git repository${NC}"
  exit 1
fi

echo -e "${GREEN}✓ All prerequisites met${NC}"
echo ""

# Step 1: Suspend GitOps on ROG-FL-02
echo -e "${YELLOW}[1/6] Suspending GitOps on ROG-FL-02...${NC}"
kubectx rog-fl-02
kubectl patch kustomization foundry-gitops-apps -n ${NAMESPACE} \
  -p '{"spec":{"suspend":true}}' --type=merge
echo -e "${GREEN}✓ GitOps suspended on ROG-FL-02${NC}"
echo ""

# Step 2: Verify both clusters are at v2.0.0 before rollback
echo -e "${YELLOW}[2/6] Verifying both clusters are at v2.0.0...${NC}"

kubectx rog-fl-01
FL01_TAG=$(kubectl logs -n ${NAMESPACE} \
  $(kubectl get pod -n ${NAMESPACE} -l app.kubernetes.io/component=foundry -o jsonpath='{.items[0].metadata.name}') 2>/dev/null \
  | grep "Tag:" | grep -v "UserAgent" | awk '{print $NF}')
echo -e "  ROG-FL-01: ${FL01_TAG}"

kubectx rog-fl-02
FL02_TAG=$(kubectl logs -n ${NAMESPACE} \
  $(kubectl get pod -n ${NAMESPACE} -l app.kubernetes.io/component=foundry -o jsonpath='{.items[0].metadata.name}') 2>/dev/null \
  | grep "Tag:" | grep -v "UserAgent" | awk '{print $NF}')
echo -e "  ROG-FL-02: ${FL02_TAG}"

if [[ "$FL01_TAG" != "v2.0.0" ]] || [[ "$FL02_TAG" != "v2.0.0" ]]; then
  echo -e "${RED}✗ Error: Both clusters must be at v2.0.0 before running this script${NC}"
  echo -e "${RED}  Current state: ROG-FL-01=${FL01_TAG}, ROG-FL-02=${FL02_TAG}${NC}"
  exit 1
fi
echo -e "${GREEN}✓ Both clusters verified at v2.0.0${NC}"
echo ""

# Step 3: Delete v2.0.0 from ACR
echo -e "${YELLOW}[3/6] Deleting v2.0.0 from ACR...${NC}"
az acr repository delete --name ${ACR_NAME} --image ${ACR_REPO}:v2.0.0 --yes
echo -e "${GREEN}✓ v2.0.0 deleted from ACR${NC}"
echo ""

# Step 4: Rollback Git to v1.0.0
echo -e "${YELLOW}[4/6] Rolling back Git to v1.0.0...${NC}"
cd "$(git rev-parse --show-toplevel)"
sed -i 's/tag: v2.0.0/tag: v1.0.0/' ${HELMRELEASE_FILE}

if git diff --quiet ${HELMRELEASE_FILE}; then
  echo -e "${YELLOW}  Warning: No changes detected in ${HELMRELEASE_FILE}${NC}"
  echo -e "${YELLOW}  File may already be at v1.0.0${NC}"
else
  git add ${HELMRELEASE_FILE}
  git commit -m "Rollback to v1.0.0 for demo"
  git push origin main
  echo -e "${GREEN}✓ Git rolled back to v1.0.0 and pushed${NC}"
fi
echo ""

# Step 5: Wait for ROG-FL-01 to rollback to v1.0.0
echo -e "${YELLOW}[5/6] Waiting for ROG-FL-01 to rollback to v1.0.0...${NC}"
echo -e "${BLUE}  This may take up to 5 minutes...${NC}"
kubectx rog-fl-01

# Wait for the old pod to start terminating
echo -e "${BLUE}  Waiting for pod rollback to start...${NC}"
sleep 30

# Wait for new pod to become ready
echo -e "${BLUE}  Waiting for new pod to become ready...${NC}"
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/component=foundry \
  -n ${NAMESPACE} \
  --timeout=5m

echo -e "${GREEN}✓ ROG-FL-01 rollback complete${NC}"
echo ""

# Step 6: Verify final demo state
echo -e "${YELLOW}[6/6] Verifying final demo state...${NC}"

# Check ROG-FL-01 tag
kubectx rog-fl-01
FL01_TAG=$(kubectl logs -n ${NAMESPACE} \
  $(kubectl get pod -n ${NAMESPACE} -l app.kubernetes.io/component=foundry -o jsonpath='{.items[0].metadata.name}') 2>/dev/null \
  | grep "Tag:" | grep -v "UserAgent" | awk '{print $NF}')
echo -e "  ROG-FL-01: ${FL01_TAG}"

# Check ROG-FL-02 tag
kubectx rog-fl-02
FL02_TAG=$(kubectl logs -n ${NAMESPACE} \
  $(kubectl get pod -n ${NAMESPACE} -l app.kubernetes.io/component=foundry -o jsonpath='{.items[0].metadata.name}') 2>/dev/null \
  | grep "Tag:" | grep -v "UserAgent" | awk '{print $NF}')
echo -e "  ROG-FL-02: ${FL02_TAG}"

# Check ACR tags
ACR_TAGS=$(oras repo tags ${ACR_NAME}.azurecr.io/${ACR_REPO})
echo -e "  ACR tags: ${ACR_TAGS}"

# Verify expectations
ERRORS=0
if [[ "$FL01_TAG" != "v1.0.0" ]]; then
  echo -e "${RED}✗ Error: ROG-FL-01 should be at v1.0.0, found ${FL01_TAG}${NC}"
  ERRORS=$((ERRORS + 1))
fi

if [[ "$FL02_TAG" != "v2.0.0" ]]; then
  echo -e "${RED}✗ Error: ROG-FL-02 should be at v2.0.0, found ${FL02_TAG}${NC}"
  ERRORS=$((ERRORS + 1))
fi

if echo "$ACR_TAGS" | grep -q "v2.0.0"; then
  echo -e "${RED}✗ Error: ACR should only have v1.0.0, found v2.0.0${NC}"
  ERRORS=$((ERRORS + 1))
fi

if [[ $ERRORS -eq 0 ]]; then
  echo -e "${GREEN}✓ Demo environment verified successfully${NC}"
  echo ""
  echo -e "${GREEN}================================${NC}"
  echo -e "${GREEN}  Demo Ready! 🎬${NC}"
  echo -e "${GREEN}================================${NC}"
  echo ""
  echo -e "Environment state:"
  echo -e "  • ROG-FL-01: v1.0.0 (GitOps active)"
  echo -e "  • ROG-FL-02: v2.0.0 (GitOps suspended)"
  echo -e "  • ACR: v1.0.0 only"
  echo -e "  • Git: v1.0.0"
  echo ""
  echo -e "${YELLOW}Post-demo cleanup:${NC}"
  echo -e "  Run: ${BLUE}./scripts/demo/demo-cleanup.sh${NC}"
else
  echo -e "${RED}✗ Demo environment verification failed with ${ERRORS} error(s)${NC}"
  exit 1
fi
