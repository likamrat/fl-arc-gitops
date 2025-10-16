#!/bin/bash

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║        Azure Arc Flux GitOps Configuration Setup         ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Configuration
CLUSTER_NAME="ROG-AI"
RESOURCE_GROUP="Foundry-Arc"
CONFIG_NAME="foundry-gitops"
NAMESPACE="foundry-system"
REPO_URL="https://github.com/likamrat/fl-arc-gitops"
BRANCH="main"

echo -e "${BLUE}Step 1: Creating namespace...${NC}"
kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

echo -e "${GREEN}✓ Namespace ${NAMESPACE} created${NC}"
echo ""

echo -e "${BLUE}Step 2: Creating Flux configuration via Azure Arc...${NC}"
az k8s-configuration flux create \
  --resource-group ${RESOURCE_GROUP} \
  --cluster-name ${CLUSTER_NAME} \
  --cluster-type connectedClusters \
  --name ${CONFIG_NAME} \
  --namespace ${NAMESPACE} \
  --scope cluster \
  --url ${REPO_URL} \
  --branch ${BRANCH} \
  --sync-interval 3s \
  --timeout 600s \
  --kustomization name=infrastructure path=./infrastructure prune=true sync-interval=3s timeout=600s retry-interval=3s \
  --kustomization name=apps path=./apps/foundry-gpu-oras prune=true depends_on=infrastructure sync-interval=3s timeout=600s retry-interval=3s

echo -e "${GREEN}✓ Flux configuration created${NC}"
echo ""

echo -e "${BLUE}Step 3: Creating ImageRepository (5s scan interval)...${NC}"
kubectl apply -f - <<EOF
---
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImageRepository
metadata:
  name: foundry-local-olive-models
  namespace: flux-system
spec:
  image: foundryoci.azurecr.io/foundry-local-olive-models
  interval: 5s
  provider: azure
EOF

echo -e "${GREEN}✓ ImageRepository configured${NC}"
echo ""

echo -e "${BLUE}Step 4: Creating ImagePolicy...${NC}"
kubectl apply -f - <<EOF
---
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImagePolicy
metadata:
  name: foundry-local-olive-models
  namespace: flux-system
spec:
  imageRepositoryRef:
    name: foundry-local-olive-models
  policy:
    semver:
      range: '>=0.1.0'
  filterTags:
    pattern: '^v?[0-9]+\.[0-9]+\.[0-9]+.*$'
    extract: '\$0'
EOF

echo -e "${GREEN}✓ ImagePolicy created${NC}"
echo ""

echo -e "${BLUE}Step 5: Verifying configuration...${NC}"
az k8s-configuration flux show \
  --resource-group ${RESOURCE_GROUP} \
  --cluster-name ${CLUSTER_NAME} \
  --cluster-type connectedClusters \
  --name ${CONFIG_NAME} \
  --output table

echo ""
echo -e "${BLUE}Step 6: Checking resources...${NC}"
kubectl get imagerepository -n flux-system foundry-local-olive-models 2>/dev/null || echo "ImageRepository will be ready shortly..."
kubectl get imagepolicy -n flux-system foundry-local-olive-models 2>/dev/null || echo "ImagePolicy will be ready shortly..."
echo ""

echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              GitOps Configuration Complete!              ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Monitor:${NC}"
echo "  kubectl get imagerepository -n flux-system -w"
echo "  kubectl logs -n flux-system deployment/image-reflector-controller -f"
