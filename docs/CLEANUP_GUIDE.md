# Demo Cleanup Guide

This guide explains how to clean up your GitOps demo environment using the `demo-cleanup.sh` script.

## 📋 Overview

The cleanup script provides two modes to reset your environment:
- **Full Cleanup** - Complete reset, removes everything
- **Soft Cleanup** - GitOps-based rollback, preserves infrastructure

## 🔧 Cleanup Modes

### Full Cleanup

**Complete environment reset** - Use this when you want to start completely fresh.

```bash
./scripts/demo/demo-cleanup.sh --full
```

**Note**: You must explicitly specify either `--full` or `--soft` mode. The script requires explicit mode selection for safety.

#### What it Does

- ✅ Cleans up Open WebUI chat history
- ✅ Deletes Flux GitOps configuration from Arc cluster
- ✅ Removes Foundry Local application (Helm release, pods, services)
- ✅ Deletes `foundry-system` namespace
- ✅ Removes all OCI artifacts from ACR **except v1.0.0**
- ✅ Reverts Git repository code to v1.0.0
- ✅ Commits and pushes changes to Git
- ✅ Verifies Flux system controllers remain healthy

#### What it Preserves

- ✅ Cached container images in cluster
- ✅ ImageRepository/ImagePolicy resources (in flux-system)
- ✅ Flux system namespace and controllers
- ✅ GPU operator and cluster infrastructure
- ✅ OCI artifact v1.0.0 in registry (baseline for next demo)

#### After Full Cleanup

You need to redeploy GitOps configuration:
```bash
./scripts/setup/gitops-config.sh
```

---

### Soft Cleanup (Recommended for Quick Reset)

**GitOps-based rollback** - Use this when you want to quickly reset to v1.0.0 without tearing down infrastructure.

```bash
./scripts/demo/demo-cleanup.sh --soft
```

#### What it Does

- ✅ Cleans up Open WebUI chat history
- ✅ Removes all OCI artifacts from ACR **except v1.0.0**
- ✅ Reverts Git repository code to v1.0.0
- ✅ Commits and pushes changes to Git
- ✅ Waits for GitOps to sync and rollback deployment (60s)
- ✅ Validates resources on cluster:
  - HelmRelease reconciliation status
  - Pod status (running and ready)
  - Deployed model version (from logs)
  - ImagePolicy latest detected version

#### What it Preserves

- ✅ Flux GitOps configuration (**foundry-gitops**)
- ✅ `foundry-system` namespace
- ✅ All Flux resources (GitRepository, Kustomizations, HelmRelease)
- ✅ ImageRepository and ImagePolicy
- ✅ All cluster infrastructure

#### After Soft Cleanup

**No action needed!** GitOps automatically rolls back to v1.0.0. Just verify the deployment:
```bash
kubectl get pods -n foundry-system
kubectl logs -n foundry-system -l app.kubernetes.io/component=foundry | grep "Tag:"
```

---

## 🧪 Dry Run Mode

Preview what will happen **without making any changes**:

```bash
# Preview full cleanup
./scripts/demo/demo-cleanup.sh --full --dry-run

# Preview soft cleanup
./scripts/demo/demo-cleanup.sh --soft --dry-run
```

Dry run mode shows:
- Current state of resources
- What would be deleted
- What would be modified
- Final expected state

---

## 📊 Comparison Table

| Feature | Full Cleanup | Soft Cleanup |
|---------|-------------|--------------|
| **Speed** | ~2 min + redeployment | ~1 min (GitOps handles it) |
| **GitOps Config** | ❌ Deleted | ✅ Preserved |
| **Namespace** | ❌ Deleted | ✅ Preserved |
| **OCI Artifacts** | 🔄 Removed (keep v1.0.0) | 🔄 Removed (keep v1.0.0) |
| **Git Code** | 🔄 Reverted to v1.0.0 | 🔄 Reverted to v1.0.0 |
| **Validation** | ⚠️ Manual | ✅ Automatic |
| **Next Demo** | Requires `gitops-config.sh` | Ready immediately |
| **Use Case** | Complete reset | Quick rollback |

---

## 🚀 Usage Examples

### Scenario 1: Quick Demo Reset

You've completed a demo showing v1.0.0 → v2.0.0 and want to reset quickly:

```bash
# Preview first
./scripts/demo/demo-cleanup.sh --soft --dry-run

# Execute soft cleanup
./scripts/demo/demo-cleanup.sh --soft

# Verify rollback
kubectl get pods -n foundry-system -w
```

**Result**: System automatically rolls back to v1.0.0 via GitOps in ~1 minute.

---

### Scenario 2: Complete Environment Reset

You want to demonstrate the full GitOps setup from scratch:

```bash
# Full cleanup
./scripts/demo/demo-cleanup.sh --full

# Redeploy GitOps config
./scripts/setup/gitops-config.sh

# Wait for deployment (~2 minutes)
watch kubectl get pods -n foundry-system
```

**Result**: Clean environment ready for E2E GitOps demo.

---

### Scenario 3: Testing Upgrade Path Again

You want to test v1.0.0 → v2.0.0 → v3.0.0 upgrade flow:

```bash
# Soft cleanup (back to v1.0.0)
./scripts/demo/demo-cleanup.sh --soft

# Push v2.0.0 artifact
cd apps/foundry-gpu-oras/models
oras push foundryoci.azurecr.io/byo-models-gpu/llama-3.2-1b-cuda:v2.0.0 \
  --artifact-type "foundry/models" \
  models.tar.gz:application/gzip

# Update Git
cd /home/lior/repos/fl-arc-gitops
sed -i 's/tag: v1.0.0/tag: v2.0.0/' apps/foundry-gpu-oras/helmrelease.yaml
git add apps/foundry-gpu-oras/helmrelease.yaml
git commit -m "Update to v2.0.0"
git push origin main

# Monitor upgrade
watch kubectl get pods -n foundry-system
```

---

## 🔍 Validation After Cleanup

### For Full Cleanup

```bash
# Verify GitOps config deleted
az k8s-configuration flux list \
  --cluster-name ROG-AI \
  --cluster-type connectedClusters \
  --resource-group Foundry-Arc

# Verify namespace deleted
kubectl get namespace foundry-system

# Verify Flux controllers still healthy
kubectl get pods -n flux-system
```

### For Soft Cleanup

```bash
# Check HelmRelease
kubectl get helmrelease -n foundry-system

# Check pods
kubectl get pods -n foundry-system

# Verify v1.0.0 deployed
kubectl logs -n foundry-system -l app.kubernetes.io/component=foundry | grep "Tag:"

# Check ImagePolicy
kubectl get imagepolicy foundry-local-olive-models -n flux-system -o jsonpath='{.status.latestImage}'
```

---

## ⚠️ Prerequisites

Before running cleanup:

1. **Azure CLI** - Logged in with access to Arc cluster
   ```bash
   az account show
   ```

2. **kubectl** - Configured for the cluster
   ```bash
   kubectl get nodes
   ```

3. **ORAS CLI** - Installed and logged in to ACR (for artifact deletion)
   ```bash
   oras version
   bash scripts/utils/oras-login.sh
   ```

4. **Clean Git** - No uncommitted changes
   ```bash
   git status
   ```

---

## 🐛 Troubleshooting

### Issue: "Uncommitted changes detected"
**Solution**: Commit or stash your changes first
```bash
git status
git add .
git commit -m "Your message"
# OR
git stash
```

### Issue: Soft cleanup pod still on old version
**Solution**: Check GitOps sync timing
```bash
# Check if Git synced
kubectl get gitrepository -n foundry-system

# Check HelmRelease status
kubectl describe helmrelease foundry-gpu-oras -n foundry-system

# Force reconciliation
flux reconcile source git foundry-gitops -n foundry-system
flux reconcile helmrelease foundry-gpu-oras -n foundry-system
```

### Issue: Cannot delete OCI artifacts
**Solution**: Authenticate with ORAS
```bash
bash scripts/utils/oras-login.sh
# OR manually
oras login foundryoci.azurecr.io
```

### Issue: Flux controllers not healthy after cleanup
**Solution**: Check Flux system
```bash
kubectl get pods -n flux-system
kubectl logs -n flux-system -l app=source-controller
```

---

## 🧹 Standalone Open WebUI Chat Cleanup

If you only need to clean up Open WebUI chat history without affecting other resources, use the standalone script:

```bash
./scripts/demo/cleanup-openwebui-chats.sh
```

This script:
- ✅ Finds the Open WebUI pod automatically
- ✅ Deletes all chat conversations from the SQLite database
- ✅ Shows count of deleted chats
- ✅ Reclaims disk space (VACUUM operation)
- ✅ Doesn't affect models, configurations, or deployments

**Use this when:**
- Preparing for a demo recording
- Clearing chat history between demo runs
- Testing chat functionality with a clean slate
- You want to keep the deployed model but clear conversations

**Example output:**
```
🗑️  Cleaning up Open WebUI chat history...
📍 Found Open WebUI pod: foundry-gpu-oras-foundry-local-openwebui-5c9cdc9b8f-wght6
🔧 Deleting all chats from database...
Found 14 chats
Deleted 14 chats
✅ Chat history cleanup complete!

💡 Tip: Refresh your Open WebUI browser tab to see the changes
```

**Note**: This script is automatically run as **Step 0** in both `--full` and `--soft` cleanup modes of `demo-cleanup.sh`.

---

## 📚 Related Documentation

- **[README.md](../README.md)** - Main repository documentation
- **[DEMO_TALK_TRACK.md](./DEMO_TALK_TRACK.md)** - Complete demo presentation script with 36 talking points
- **[DEMO_FLOW.md](./DEMO_FLOW.md)** - Step-by-step demo workflow
- **[GITOPS_FLOW_SUMMARY.md](./GITOPS_FLOW_SUMMARY.md)** - GitOps architecture and flow
- **[GPU_OPERATOR_INSTALLATION.md](./GPU_OPERATOR_INSTALLATION.md)** - GPU operator setup guide

---

## 💡 Tips

1. **Always use dry-run first** to preview changes
2. **Use soft cleanup for demos** - faster and preserves infrastructure
3. **Use full cleanup for E2E tests** - demonstrates complete GitOps setup
4. **Check cluster state before cleanup** to understand what will be affected
5. **Keep v1.0.0 artifact** in registry as your baseline (script preserves it)
6. **Explicit mode required** - always specify either `--full` or `--soft`

---

## 🎯 Quick Reference

```bash
# Quick reset (recommended)
./scripts/demo/demo-cleanup.sh --soft

# Full reset
./scripts/demo/demo-cleanup.sh --full

# Preview only
./scripts/demo/demo-cleanup.sh --soft --dry-run
./scripts/demo/demo-cleanup.sh --full --dry-run

# After full cleanup
./scripts/setup/gitops-config.sh
```

---

## 🔄 Model Repository Structure

The cleanup script now uses the hierarchical GPU model repository:

- **Repository**: `foundryoci.azurecr.io/byo-models-gpu/llama-3.2-1b-cuda`
- **Baseline Version**: `v1.0.0` (preserved during cleanup)
- **Model**: CUDA-optimized Llama 3.2 1B (int4 quantized, ~1GB)
- **Source**: onnx-community/Llama-3.2-1B-Instruct-ONNX

This structure allows multiple GPU-optimized models in the same registry namespace while maintaining clear version control per model variant.

---

**Version**: v1.0.0  
**Last Updated**: October 18, 2025  
**Status**: Updated for GPU-accelerated models and explicit mode selection
./scripts/setup/gitops-config.sh
```

---

**Last Updated**: October 17, 2025
