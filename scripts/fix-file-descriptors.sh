#!/bin/bash

################################################################################
# Fix File Descriptor Limits for k3s
# 
# This script increases the file descriptor limits on the k3s node to fix
# the "Too many open files" error in fluent-bit logging sidecars.
#
# The issue occurs because fluent-bit tries to watch many log files and
# hits the default system limits.
#
# Prerequisites:
# - Root/sudo access on the k3s node
# - k3s service running
#
# Usage:
#   sudo ./scripts/fix-file-descriptors.sh
################################################################################

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║        Fixing File Descriptor Limits for k3s                   ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}✗ This script must be run as root or with sudo${NC}"
    echo -e "${YELLOW}  Please run: sudo ./scripts/fix-file-descriptors.sh${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Running as root${NC}"
echo ""

# Step 1: Display current limits
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 1: Checking Current File Descriptor Limits${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${BLUE}Current system limits:${NC}"
echo -e "  Soft limit: $(ulimit -Sn)"
echo -e "  Hard limit: $(ulimit -Hn)"
echo ""

# Step 2: Update system-wide limits
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 2: Updating System-Wide File Descriptor Limits${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Backup existing limits.conf if it exists
if [ -f /etc/security/limits.conf ]; then
    echo -e "${BLUE}  Backing up /etc/security/limits.conf...${NC}"
    cp /etc/security/limits.conf /etc/security/limits.conf.backup.$(date +%Y%m%d-%H%M%S)
    echo -e "${GREEN}✓ Backup created${NC}"
fi

# Add or update limits in /etc/security/limits.conf
echo -e "${BLUE}  Updating /etc/security/limits.conf...${NC}"

# Remove existing entries if any
sed -i '/^root.*nofile/d' /etc/security/limits.conf
sed -i '/^\*.*nofile/d' /etc/security/limits.conf

# Add new limits
cat >> /etc/security/limits.conf << 'EOF'

# Increased file descriptor limits for k3s and containers
* soft nofile 65536
* hard nofile 65536
root soft nofile 65536
root hard nofile 65536
EOF

echo -e "${GREEN}✓ Updated /etc/security/limits.conf${NC}"
echo ""

# Step 3: Update systemd limits for k3s
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 3: Updating systemd Limits for k3s Service${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Create systemd override directory for k3s
mkdir -p /etc/systemd/system/k3s.service.d

echo -e "${BLUE}  Creating systemd override for k3s...${NC}"

cat > /etc/systemd/system/k3s.service.d/limits.conf << 'EOF'
[Service]
LimitNOFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
EOF

echo -e "${GREEN}✓ Created /etc/systemd/system/k3s.service.d/limits.conf${NC}"
echo ""

# Step 4: Update sysctl settings
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 4: Updating Kernel Parameters${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${BLUE}  Updating /etc/sysctl.conf...${NC}"

# Backup sysctl.conf
if [ -f /etc/sysctl.conf ]; then
    cp /etc/sysctl.conf /etc/sysctl.conf.backup.$(date +%Y%m%d-%H%M%S)
fi

# Remove existing fs.file-max entries
sed -i '/^fs.file-max/d' /etc/sysctl.conf
sed -i '/^fs.inotify.max_user_watches/d' /etc/sysctl.conf
sed -i '/^fs.inotify.max_user_instances/d' /etc/sysctl.conf

# Add new kernel parameters
cat >> /etc/sysctl.conf << 'EOF'

# Increased file descriptor limits for containers
fs.file-max = 2097152
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512
EOF

# Apply sysctl settings immediately
sysctl -p /etc/sysctl.conf > /dev/null 2>&1

echo -e "${GREEN}✓ Updated kernel parameters${NC}"
echo ""

# Step 5: Reload systemd and restart k3s
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 5: Restarting k3s Service${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${BLUE}  Reloading systemd daemon...${NC}"
systemctl daemon-reload
echo -e "${GREEN}✓ Systemd daemon reloaded${NC}"

echo -e "${BLUE}  Restarting k3s service...${NC}"
systemctl restart k3s
echo -e "${GREEN}✓ k3s service restarted${NC}"

echo -e "${YELLOW}  Waiting 30 seconds for k3s to stabilize...${NC}"
sleep 30

echo ""

# Step 6: Verify new limits
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 6: Verifying New Limits${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${BLUE}New system limits:${NC}"
echo -e "  Soft limit: $(ulimit -Sn)"
echo -e "  Hard limit: $(ulimit -Hn)"
echo ""

echo -e "${BLUE}Kernel parameters:${NC}"
sysctl fs.file-max
sysctl fs.inotify.max_user_watches
sysctl fs.inotify.max_user_instances
echo ""

echo -e "${BLUE}k3s service status:${NC}"
systemctl status k3s --no-pager -l | head -n 10

echo ""

# Step 7: Restart Flux pods
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 7: Restarting Flux Config Pods${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${BLUE}  Deleting flux config pods to pick up new limits...${NC}"
kubectl delete pods -n flux-system -l app=fluxconfig-agent 2>/dev/null || echo -e "${YELLOW}  No fluxconfig-agent pods found${NC}"
kubectl delete pods -n flux-system -l app=fluxconfig-controller 2>/dev/null || echo -e "${YELLOW}  No fluxconfig-controller pods found${NC}"

echo -e "${YELLOW}  Waiting 20 seconds for pods to restart...${NC}"
sleep 20

echo ""
echo -e "${BLUE}Flux pod status:${NC}"
kubectl get pods -n flux-system

echo ""

# Display summary
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         File Descriptor Limits Updated Successfully! ✓         ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${CYAN}Summary of Changes:${NC}"
echo ""
echo -e "${YELLOW}1. System-wide limits (/etc/security/limits.conf):${NC}"
echo -e "   • Soft nofile: 65536"
echo -e "   • Hard nofile: 65536"
echo ""
echo -e "${YELLOW}2. k3s service limits (systemd):${NC}"
echo -e "   • LimitNOFILE: 1048576"
echo -e "   • LimitNPROC: infinity"
echo ""
echo -e "${YELLOW}3. Kernel parameters (sysctl):${NC}"
echo -e "   • fs.file-max: 2097152"
echo -e "   • fs.inotify.max_user_watches: 524288"
echo -e "   • fs.inotify.max_user_instances: 512"
echo ""
echo -e "${CYAN}Next Steps:${NC}"
echo ""
echo -e "  ${YELLOW}# Monitor Flux pods to ensure they're healthy${NC}"
echo -e "  kubectl get pods -n flux-system -w"
echo ""
echo -e "  ${YELLOW}# Check fluent-bit logs (should no longer show 'Too many open files')${NC}"
echo -e "  kubectl logs -n flux-system -l app=fluxconfig-agent -c fluent-bit --tail=30"
echo ""
echo -e "${GREEN}✓ All changes have been applied and will persist across reboots!${NC}"
echo ""
