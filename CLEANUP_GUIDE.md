# Demo Cleanup Guide

This guide explains how to clean up your GitOps demo environment using the `demo-cleanup.sh` script.

## 📋 Overview

The cleanup script provides two modes to reset your environment:
- **Full Cleanup** - Complete reset, removes everything
- **Soft Cleanup** - GitOps-based rollback, preserves infrastructure

## 🔧 Cleanup Modes

### Full Cleanup (Default)

**Complete environment reset** - Use this when you want to start completely fresh.

```bash
./scripts/demo-cleanup.sh
```

#### What it Does

- ✅ Deletes Flux GitOps configuration from Arc cluster
- ✅ Removes Foundry Local application (Helm release, pods, services)
- ✅ Deletes `foundry-system` namespace
- ✅ Removes all OCI artifacts from ACR **except v0.1.0**
- ✅ Reverts Git repository code to v0.1.0
- ✅ Commits and pushes changes to Git
- ✅ Verifies Flux system controllers remain healthy

#### What it Preserves

- ✅ Cached container images in cluster
- ✅ ImageRepository/ImagePolicy resources (in flux-system)
- ✅ Flux system namespace and controllers
- ✅ GPU operator and cluster infrastructure
- ✅ OCI artifact v0.1.0 in registry (baseline for next demo)

#### After Full Cleanup

You need to redeploy GitOps configuration:
```bash
./scripts/gitops-config.sh
```

---

### Soft Cleanup (Recommended for Quick Reset)

**GitOps-based rollback** - Use this when you want to quickly reset to v0.1.0 without tearing down infrastructure.

```bash
./scripts/demo-cleanup.sh --soft
```

#### What it Does

- ✅ Removes all OCI artifacts from ACR **except v0.1.0**
- ✅ Reverts Git repository code to v0.1.0
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

**No action needed!** GitOps automatically rolls back to v0.1.0. Just verify the deployment:
```bash
kubectl get pods -n foundry-system
kubectl logs -n foundry-system -l app.kubernetes.io/component=foundry | grep "Tag:"
```

---

## 🧪 Dry Run Mode

Preview what will happen **without making any changes**:

```bash
# Preview full cleanup
./scripts/demo-cleanup.sh --dry-run

# Preview soft cleanup
./scripts/demo-cleanup.sh --soft --dry-run
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
| **OCI Artifacts** | 🔄 Removed (keep v0.1.0) | 🔄 Removed (keep v0.1.0) |
| **Git Code** | 🔄 Reverted to v0.1.0 | 🔄 Reverted to v0.1.0 |
| **Validation** | ⚠️ Manual | ✅ Automatic |
| **Next Demo** | Requires `gitops-config.sh` | Ready immediately |
| **Use Case** | Complete reset | Quick rollback |

---

## 🚀 Usage Examples

### Scenario 1: Quick Demo Reset
You've completed a demo showing v0.1.0 → v0.2.0 and want to reset quickly:

```bash
# Preview first
./scripts/demo-cleanup.sh --soft --dry-run

# Execute soft cleanup
./scripts/demo-cleanup.sh --soft

# Verify rollback
kubectl get pods -n foundry-system -w
```

**Result**: System automatically rolls back to v0.1.0 via GitOps in ~1 minute.

---

### Scenario 2: Complete Environment Reset
You want to demonstrate the full GitOps setup from scratch:

```bash
# Full cleanup
./scripts/demo-cleanup.sh

# Redeploy GitOps config
./scripts/gitops-config.sh

# Wait for deployment (~2 minutes)
watch kubectl get pods -n foundry-system
```

**Result**: Clean environment ready for E2E GitOps demo.

---

### Scenario 3: Testing Upgrade Path Again
You want to test v0.1.0 → v0.2.0 → v0.3.0 upgrade flow:

```bash
# Soft cleanup (back to v0.1.0)
./scripts/demo-cleanup.sh --soft

# Push v0.2.0 artifact
cd apps/foundry-gpu-oras/models
oras push foundryoci.azurecr.io/foundry-local-olive-models:v0.2.0 \
  --artifact-type "foundry/models" \
  models.tar.gz:application/gzip

# Update Git
cd /home/lior/repos/fl-arc-gitops
sed -i 's/tag: v0.1.0/tag: v0.2.0/' apps/foundry-gpu-oras/helmrelease.yaml
git add apps/foundry-gpu-oras/helmrelease.yaml
git commit -m "Update to v0.2.0"
git push origin main

# Monitor upgrade
watch kubectl get pods -n foundry-system
```

---

## 🔍 Validation After Cleanup

### For Full Cleanup:
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

### For Soft Cleanup:
```bash
# Check HelmRelease
kubectl get helmrelease -n foundry-system

# Check pods
kubectl get pods -n foundry-system

# Verify v0.1.0 deployed
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
   bash scripts/oras-login.sh
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
bash scripts/oras-login.sh
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

## 📚 Related Documentation

- **[QUICK_START.md](QUICK_START.md)** - Fast-track guide to run E2E test
- **[E2E_TEST_PLAN.md](E2E_TEST_PLAN.md)** - Comprehensive test plan
- **[GITOPS_FLOW_SUMMARY.md](GITOPS_FLOW_SUMMARY.md)** - GitOps architecture and flow
- **[README.md](README.md)** - Main repository documentation

---

## 💡 Tips

1. **Always use dry-run first** to preview changes
2. **Use soft cleanup for demos** - faster and preserves infrastructure
3. **Use full cleanup for E2E tests** - demonstrates complete GitOps setup
4. **Check cluster state before cleanup** to understand what will be affected
5. **Keep v0.1.0 artifact** in registry as your baseline (script preserves it)

---

## 🎯 Quick Reference

```bash
# Quick reset (recommended)
./scripts/demo-cleanup.sh --soft

# Full reset
./scripts/demo-cleanup.sh

# Preview only
./scripts/demo-cleanup.sh --soft --dry-run
./scripts/demo-cleanup.sh --dry-run

# After full cleanup
./scripts/gitops-config.sh
```

---

**Last Updated**: October 17, 2025
