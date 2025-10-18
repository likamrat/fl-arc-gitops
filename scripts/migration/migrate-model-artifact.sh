#!/bin/bash

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║       Migrate Model Artifact Between Registries          ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Source registry (original)
SOURCE_REGISTRY="jumpstartdev.azurecr.io"
SOURCE_REPO="foundry-local-olive-models"
SOURCE_TAG="latest"

# Destination registry (new GitOps target)
DEST_REGISTRY="foundryoci.azurecr.io"
DEST_REPO="byo-models-gpu/llama-3.2-1b-cuda"
DEST_TAG="v1.0.0"  # Semantic version for GitOps ImagePolicy

SOURCE_IMAGE="${SOURCE_REGISTRY}/${SOURCE_REPO}:${SOURCE_TAG}"
DEST_IMAGE="${DEST_REGISTRY}/${DEST_REPO}:${DEST_TAG}"

echo -e "${BLUE}Step 1: Verifying ORAS CLI...${NC}"
if ! oras version; then
    echo -e "${RED}❌ ORAS CLI not found. Please install ORAS first.${NC}"
    exit 1
fi
echo -e "${GREEN}✓ ORAS CLI ready${NC}"
echo ""

echo -e "${BLUE}Step 2: Creating temp directory for artifact...${NC}"
WORK_DIR=$(mktemp -d)
echo -e "${GREEN}✓ Working directory: ${WORK_DIR}${NC}"
echo ""

echo -e "${BLUE}Step 3: Pulling artifact from source registry...${NC}"
echo -e "${YELLOW}Source: ${SOURCE_IMAGE}${NC}"
cd "${WORK_DIR}"

if oras pull --allow-path-traversal "${SOURCE_IMAGE}"; then
    echo -e "${GREEN}✓ Successfully pulled from source registry${NC}"
else
    echo -e "${RED}❌ Failed to pull from source registry${NC}"
    echo -e "${YELLOW}Note: jumpstartdev.azurecr.io is a public registry, no auth should be needed${NC}"
    rm -rf "${WORK_DIR}"
    exit 1
fi
echo ""

echo -e "${BLUE}Step 4: Listing downloaded files...${NC}"
ls -lh "${WORK_DIR}"
echo ""

echo -e "${BLUE}Step 5: Ensuring destination repository exists...${NC}"
# ORAS will create the repo on first push, but let's verify credentials
if oras repo tags "${DEST_REGISTRY}/${DEST_REPO}" 2>/dev/null; then
    echo -e "${GREEN}✓ Can access destination repository${NC}"
else
    echo -e "${YELLOW}⚠️  Repository may not exist yet (will be created on first push)${NC}"
fi
echo ""

echo -e "${BLUE}Step 6: Pushing artifact to destination registry...${NC}"
echo -e "${YELLOW}Destination: ${DEST_IMAGE}${NC}"

# Push all files in the working directory
if oras push "${DEST_IMAGE}" ./:application/vnd.oci.image.layer.v1.tar+gzip; then
    echo -e "${GREEN}✓ Successfully pushed to destination registry${NC}"
else
    echo -e "${RED}❌ Failed to push to destination registry${NC}"
    rm -rf "${WORK_DIR}"
    exit 1
fi
echo ""

echo -e "${BLUE}Step 7: Verifying the pushed artifact...${NC}"
if oras manifest fetch "${DEST_IMAGE}" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Artifact verified in destination registry${NC}"
    echo ""
    echo -e "${YELLOW}Manifest details:${NC}"
    oras manifest fetch "${DEST_IMAGE}" | head -20
else
    echo -e "${RED}❌ Failed to verify artifact${NC}"
fi
echo ""

echo -e "${BLUE}Step 8: Listing tags in destination repository...${NC}"
oras repo tags "${DEST_REGISTRY}/${DEST_REPO}" || echo "Could not list tags"
echo ""

echo -e "${BLUE}Step 9: Cleaning up temp directory...${NC}"
rm -rf "${WORK_DIR}"
echo -e "${GREEN}✓ Cleanup complete${NC}"
echo ""

echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║            Migration Completed Successfully!             ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Artifact Details:${NC}"
echo -e "  Source:      ${SOURCE_IMAGE}"
echo -e "  Destination: ${DEST_IMAGE}"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo -e "  1. Flux ImageRepository will detect the new artifact within 10 seconds"
echo -e "  2. Monitor with: kubectl get imagerepository -n flux-system -w"
echo -e "  3. Check detected image: kubectl get imagerepository -n flux-system foundry-local-olive-models -o jsonpath='{.status.lastScanResult.latestImage}'"
echo ""
