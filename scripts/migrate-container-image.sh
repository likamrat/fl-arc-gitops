#!/bin/bash

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║    Migrate Foundry Container Image Between Registries    ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Source registry (public)
SOURCE_IMAGE="jumpstartdev.azurecr.io/foundry-local-gpu-oras:latest"

# Destination registry (private)
DEST_IMAGE="foundryoci.azurecr.io/foundry-local-gpu-oras:latest"

echo -e "${BLUE}Step 1: Pulling container image from source registry...${NC}"
echo -e "${YELLOW}Source: ${SOURCE_IMAGE}${NC}"

if docker pull "${SOURCE_IMAGE}"; then
    echo -e "${GREEN}✓ Successfully pulled from source registry${NC}"
else
    echo -e "${RED}❌ Failed to pull from source registry${NC}"
    exit 1
fi
echo ""

echo -e "${BLUE}Step 2: Tagging image for destination registry...${NC}"
docker tag "${SOURCE_IMAGE}" "${DEST_IMAGE}"
echo -e "${GREEN}✓ Image tagged${NC}"
echo ""

echo -e "${BLUE}Step 3: Pushing image to destination registry...${NC}"
echo -e "${YELLOW}Destination: ${DEST_IMAGE}${NC}"

if docker push "${DEST_IMAGE}"; then
    echo -e "${GREEN}✓ Successfully pushed to destination registry${NC}"
else
    echo -e "${RED}❌ Failed to push to destination registry${NC}"
    exit 1
fi
echo ""

echo -e "${BLUE}Step 4: Verifying the pushed image...${NC}"
if docker pull "${DEST_IMAGE}" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Image verified in destination registry${NC}"
else
    echo -e "${RED}❌ Failed to verify image${NC}"
fi
echo ""

echo -e "${BLUE}Step 5: Image details...${NC}"
docker images "${DEST_IMAGE}" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.ID}}"
echo ""

echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║            Migration Completed Successfully!             ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Container Image Migrated:${NC}"
echo -e "  Source:      ${SOURCE_IMAGE}"
echo -e "  Destination: ${DEST_IMAGE}"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo -e "  1. Update Helm values to use foundryoci.azurecr.io/foundry-local-gpu-oras:latest"
echo -e "  2. Commit and push the updated values file"
echo -e "  3. Flux will deploy using the new registry"
echo ""
