#!/bin/bash

################################################################################
# ORAS Login Script for Azure Container Registry
# 
# This script logs into Azure Container Registry using ORAS CLI by reusing
# Docker credentials that are already configured.
#
# Usage:
#   ./scripts/utils/oras-login.sh
################################################################################

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║          ORAS Login to Azure Container Registry          ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Registry configuration
REGISTRY="foundryoci.azurecr.io"

# Check if Docker config exists
if [ ! -f ~/.docker/config.json ]; then
    echo -e "${RED}✗ Docker config not found at ~/.docker/config.json${NC}"
    echo -e "${YELLOW}  Please run 'docker login ${REGISTRY}' first${NC}"
    exit 1
fi

# Check if already logged into registry with Docker
if ! cat ~/.docker/config.json | jq -e ".auths[\"${REGISTRY}\"]" > /dev/null 2>&1; then
    echo -e "${RED}✗ Not logged into ${REGISTRY} with Docker${NC}"
    echo -e "${YELLOW}  Please run 'docker login ${REGISTRY}' first${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Found Docker credentials for ${REGISTRY}${NC}"
echo ""

# Extract credentials from Docker config
echo -e "${BLUE}Step 1: Extracting credentials from Docker config...${NC}"

# Check if credentials are stored or in a credential helper
AUTH_ENTRY=$(cat ~/.docker/config.json | jq -r ".auths[\"${REGISTRY}\"]")

if echo "$AUTH_ENTRY" | jq -e '.auth' > /dev/null 2>&1; then
    # Credentials are stored in base64
    AUTH_B64=$(echo "$AUTH_ENTRY" | jq -r '.auth')
    CREDS=$(echo "$AUTH_B64" | base64 -d)
    USERNAME=$(echo "$CREDS" | cut -d: -f1)
    PASSWORD=$(echo "$CREDS" | cut -d: -f2-)
    
    echo -e "${GREEN}✓ Extracted credentials from Docker config${NC}"
    echo -e "  Registry: ${REGISTRY}"
    echo -e "  Username: ${USERNAME}"
    echo ""
else
    # Try using credential helper or Azure CLI
    echo -e "${YELLOW}⚠ Credentials stored in helper, attempting Azure CLI login...${NC}"
    
    # Check if Azure CLI is available
    if ! command -v az &> /dev/null; then
        echo -e "${RED}✗ Azure CLI not found${NC}"
        echo -e "${YELLOW}  Please install Azure CLI or use direct credentials${NC}"
        exit 1
    fi
    
    # Get ACR credentials using Azure CLI
    REGISTRY_NAME=$(echo $REGISTRY | cut -d. -f1)
    echo -e "${BLUE}  Getting credentials for ACR: ${REGISTRY_NAME}${NC}"
    
    # Get username and password from Azure CLI
    USERNAME=$(az acr credential show -n ${REGISTRY_NAME} --query username -o tsv 2>/dev/null || echo "")
    PASSWORD=$(az acr credential show -n ${REGISTRY_NAME} --query passwords[0].value -o tsv 2>/dev/null || echo "")
    
    if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
        echo -e "${RED}✗ Could not retrieve ACR credentials${NC}"
        echo -e "${YELLOW}  Make sure you're logged in with 'az login' and have access to the registry${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Retrieved credentials from Azure CLI${NC}"
    echo -e "  Registry: ${REGISTRY}"
    echo -e "  Username: ${USERNAME}"
    echo ""
fi

# Login to ORAS
echo -e "${BLUE}Step 2: Logging into ORAS...${NC}"

if echo "$PASSWORD" | oras login "$REGISTRY" -u "$USERNAME" --password-stdin > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Successfully logged into ${REGISTRY} with ORAS${NC}"
else
    echo -e "${RED}✗ Failed to login with ORAS${NC}"
    exit 1
fi

echo ""

# Verify login by listing repositories (if accessible)
echo -e "${BLUE}Step 3: Verifying ORAS login...${NC}"

# Try to list repositories (this may fail if no permissions, but login still works)
if oras repo ls "$REGISTRY" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ ORAS login verified - can access registry${NC}"
    echo ""
    echo -e "${BLUE}Available repositories:${NC}"
    oras repo ls "$REGISTRY" | head -5
    REPO_COUNT=$(oras repo ls "$REGISTRY" | wc -l)
    if [ "$REPO_COUNT" -gt 5 ]; then
        echo -e "${YELLOW}  ... and $((REPO_COUNT - 5)) more${NC}"
    fi
else
    echo -e "${GREEN}✓ ORAS login successful${NC}"
    echo -e "${YELLOW}⚠ Cannot list repositories (may be a permissions issue, but login works)${NC}"
fi

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                    Login Complete!                        ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}You can now use ORAS commands with ${REGISTRY}${NC}"
echo ""
echo -e "Examples:"
echo -e "  ${YELLOW}# Pull an artifact${NC}"
echo -e "  oras pull ${REGISTRY}/byo-models-gpu/llama-3.2-1b-cuda:v2.0.0"
echo ""
echo -e "  ${YELLOW}# Push an artifact${NC}"
echo -e "  oras push ${REGISTRY}/byo-models-gpu/llama-3.2-1b-cuda:v2.0.0 ./models.tar.gz"
echo ""
