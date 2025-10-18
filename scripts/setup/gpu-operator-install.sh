#!/bin/bash

# NVIDIA GPU Operator Installation Script for k3s
# This script installs the NVIDIA GPU Operator on a k3s Kubernetes cluster
# The GPU Operator automatically installs and manages NVIDIA drivers and CUDA toolkit
# Based on official NVIDIA documentation:
# https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/getting-started.html

set -e

echo "================================"
echo "NVIDIA GPU Operator Installation"
echo "================================"
echo ""

# Step 1: Add NVIDIA Helm Repository
echo "Step 1: Adding NVIDIA Helm repository..."
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia 2>/dev/null || helm repo update nvidia
helm repo update
echo "✓ NVIDIA Helm repository added/updated"
echo ""

# Step 2: Create namespace for GPU Operator with Pod Security Standards
echo "Step 2: Creating gpu-operator namespace..."
kubectl create namespace gpu-operator 2>/dev/null || echo "  (Namespace already exists)"
kubectl label --overwrite ns gpu-operator pod-security.kubernetes.io/enforce=privileged
echo "✓ Namespace created/verified with privileged PSA enforcement"
echo ""

# Step 3: Check for existing Node Feature Discovery
echo "Step 3: Checking for Node Feature Discovery..."
if kubectl get nodes -o json | jq -e '.items[].metadata.labels | keys | any(startswith("feature.node.kubernetes.io"))' > /dev/null 2>&1; then
  echo "  NFD already running in cluster - will disable in GPU Operator"
  NFD_ENABLED="false"
else
  echo "  NFD not detected - will be deployed by GPU Operator"
  NFD_ENABLED="true"
fi
echo ""

# Step 4: Install NVIDIA GPU Operator
echo "Step 4: Installing NVIDIA GPU Operator..."
echo "  This may take several minutes as it downloads and installs GPU drivers..."
echo ""

# For k3s, we need to configure the toolkit to handle the different runtime paths
# k3s uses containerd with a non-standard socket location
helm install --wait gpu-operator \
  -n gpu-operator --create-namespace \
  nvidia/gpu-operator \
  --version=v25.3.4 \
  --set driver.enabled=true \
  --set toolkit.enabled=true \
  --set nfd.enabled=${NFD_ENABLED} \
  --set toolkit.env[0].name=CONTAINERD_CONFIG \
  --set toolkit.env[0].value=/var/lib/rancher/k3s/agent/etc/containerd/config.toml \
  --set toolkit.env[1].name=CONTAINERD_SOCKET \
  --set toolkit.env[1].value=/run/k3s/containerd/containerd.sock \
  --set toolkit.env[2].name=CONTAINERD_RUNTIME_CLASS \
  --set toolkit.env[2].value=nvidia \
  --set toolkit.env[3].name=CONTAINERD_SET_AS_DEFAULT \
  --set-string toolkit.env[3].value=true

echo ""
echo "✓ GPU Operator v25.3.4 installed with k3s-specific configuration"
echo ""

# Step 5: Verify Installation
echo "Step 5: Verifying installation..."
echo ""
echo "GPU Operator pods status:"
kubectl get pods -n gpu-operator
echo ""

# Step 6: Wait for pods to be ready
echo "Step 6: Waiting for GPU Operator components to be ready..."
kubectl wait --for=condition=ready pod -l app=gpu-operator -n gpu-operator --timeout=300s 2>/dev/null || echo "  (Still initializing...)"
echo ""

# Step 7: Check GPU device plugin
echo "Step 7: Checking GPU device plugin availability on nodes..."
echo ""
kubectl describe nodes | grep -A 5 "nvidia.com/gpu" || echo "  (GPUs not yet available - drivers may still be installing)"
echo ""

# Step 8: Installation Summary
echo "================================"
echo "Installation Summary"
echo "================================"
echo ""
echo "The NVIDIA GPU Operator v25.3.4 has been installed."
echo ""
echo "Components deployed:"
echo "  • NVIDIA GPU Driver (containerized)"
echo "  • NVIDIA Container Toolkit"
echo "  • GPU Device Plugin"
echo "  • GPU Feature Discovery"
echo "  • DCGM Exporter (monitoring)"
echo "  • Node Feature Discovery (if not pre-installed)"
echo ""
echo "Next steps:"
echo "  1. Wait 5-10 minutes for drivers to install on all GPU nodes"
echo "  2. Monitor installation progress:"
echo "     kubectl get pods -n gpu-operator -w"
echo "  3. Verify GPUs are available:"
echo "     kubectl get nodes '-o=custom-columns=NAME:.metadata.name,GPUs:.status.allocatable.nvidia\.com/gpu'"
echo "  4. Check driver installation logs (if needed):"
echo "     kubectl logs -n gpu-operator -l app=nvidia-driver-daemonset -f"
echo ""
echo "To test GPU access, create a pod with:"
echo "  resources:"
echo "    limits:"
echo "      nvidia.com/gpu: 1"
echo ""
echo "Or use runtimeClassName: nvidia"
echo ""
echo "To uninstall:"
echo "  helm uninstall gpu-operator -n gpu-operator"
echo ""
echo "Documentation:"
echo "  https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/"
echo ""
