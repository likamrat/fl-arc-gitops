#!/bin/bash

################################################################################
# Remote File Descriptor Fix for k3s Node
# 
# This script copies the file descriptor fix to the k3s node and executes it
# via SSH to resolve the "Too many open files" error.
#
# Prerequisites:
# - SSH access to the k3s node (lior@192.168.8.100)
# - SSH key authentication configured (no password prompt)
# - sudo access on the remote node
#
# Usage:
#   ./scripts/fix-remote-file-descriptors.sh
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
K3S_NODE="lior@192.168.8.102"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIX_SCRIPT="${SCRIPT_DIR}/fix-file-descriptors.sh"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Remote File Descriptor Fix for k3s Node                   ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Step 1: Verify local fix script exists
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 1: Verifying Fix Script${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if [ ! -f "${FIX_SCRIPT}" ]; then
    echo -e "${RED}✗ Fix script not found: ${FIX_SCRIPT}${NC}"
    echo -e "${YELLOW}  Please ensure fix-file-descriptors.sh exists in the scripts directory${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Fix script found: ${FIX_SCRIPT}${NC}"
chmod +x "${FIX_SCRIPT}"
echo ""

# Step 2: Test SSH connectivity
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 2: Testing SSH Connectivity${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${BLUE}  Testing connection to ${K3S_NODE}...${NC}"
if ! ssh -o ConnectTimeout=10 -o BatchMode=yes "${K3S_NODE}" "echo 'SSH connection successful'" 2>/dev/null; then
    echo -e "${RED}✗ Cannot connect to ${K3S_NODE}${NC}"
    echo -e "${YELLOW}  Please ensure:${NC}"
    echo -e "${YELLOW}  1. SSH key is configured for ${K3S_NODE}${NC}"
    echo -e "${YELLOW}  2. Node is accessible at 192.168.8.100${NC}"
    echo -e "${YELLOW}  3. User 'lior' has SSH access${NC}"
    exit 1
fi

echo -e "${GREEN}✓ SSH connection successful${NC}"
echo ""

# Step 3: Copy fix script to remote node
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 3: Copying Fix Script to k3s Node${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${BLUE}  Uploading fix-file-descriptors.sh...${NC}"
scp "${FIX_SCRIPT}" "${K3S_NODE}:/tmp/fix-file-descriptors.sh"
ssh "${K3S_NODE}" "chmod +x /tmp/fix-file-descriptors.sh"
echo -e "${GREEN}✓ Script uploaded to /tmp/fix-file-descriptors.sh${NC}"
echo ""

# Step 4: Execute fix script on remote node
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 4: Executing Fix Script on k3s Node${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${YELLOW}⚠  This will restart the k3s service on the remote node${NC}"
echo -e "${YELLOW}⚠  The cluster will be briefly unavailable during the restart${NC}"
echo ""
read -p "Do you want to proceed? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Aborted by user${NC}"
    ssh "${K3S_NODE}" "rm -f /tmp/fix-file-descriptors.sh"
    exit 0
fi

echo ""
echo -e "${BLUE}  Running fix script with sudo...${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Execute the script with sudo and stream output
ssh -t "${K3S_NODE}" "sudo /tmp/fix-file-descriptors.sh"

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Step 5: Cleanup
echo -e "${BLUE}  Cleaning up remote script...${NC}"
ssh "${K3S_NODE}" "rm -f /tmp/fix-file-descriptors.sh"
echo -e "${GREEN}✓ Cleanup complete${NC}"
echo ""

# Step 6: Wait for cluster to stabilize
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 5: Waiting for Cluster to Stabilize${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${YELLOW}  Waiting 45 seconds for k3s to fully restart...${NC}"
sleep 45

echo -e "${BLUE}  Checking cluster connectivity...${NC}"
if kubectl cluster-info &> /dev/null; then
    echo -e "${GREEN}✓ Cluster is accessible${NC}"
else
    echo -e "${YELLOW}⚠ Cluster not yet ready, waiting another 15 seconds...${NC}"
    sleep 15
    if kubectl cluster-info &> /dev/null; then
        echo -e "${GREEN}✓ Cluster is accessible${NC}"
    else
        echo -e "${RED}✗ Cluster not responding${NC}"
        echo -e "${YELLOW}  You may need to manually check the k3s service status${NC}"
    fi
fi

echo ""

# Step 7: Verify Flux pods
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 6: Verifying Flux Pods${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${BLUE}Current Flux pod status:${NC}"
kubectl get pods -n flux-system

echo ""

# Final summary
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           File Descriptor Fix Completed! ✓                     ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${CYAN}Next Steps:${NC}"
echo ""
echo -e "${YELLOW}1. Monitor Flux Pods${NC}"
echo -e "   ${BLUE}kubectl get pods -n flux-system -w${NC}"
echo ""
echo -e "${YELLOW}2. Check fluent-bit logs (should now start successfully)${NC}"
echo -e "   ${BLUE}kubectl logs -n flux-system -l app=fluxconfig-agent -c fluent-bit --tail=20${NC}"
echo -e "   ${BLUE}kubectl logs -n flux-system -l app=fluxconfig-controller -c fluent-bit --tail=20${NC}"
echo ""
echo -e "${YELLOW}3. Verify all Flux controllers are ready${NC}"
echo -e "   ${BLUE}kubectl wait --for=condition=ready pod -l app.kubernetes.io/part-of=flux -n flux-system --timeout=180s${NC}"
echo ""
echo -e "${GREEN}✓ File descriptor limits have been permanently increased on the k3s node${NC}"
echo -e "${GREEN}✓ The changes will persist across reboots${NC}"
echo ""
