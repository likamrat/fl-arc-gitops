# GitOps Demo Flow - AI Model Upgrade

A hands-on guide demonstrating GitOps-driven GPU-accelerated AI model upgrades from v1.0.0 to v2.0.0 using Azure Arc and Flux CD.

## 🎯 Demo Overview

**Starting Point:** Foundry Local v1.0.0 with CUDA-optimized Llama 3.2 1B already deployed via GitOps

**What You'll Demonstrate:**
1. Verify current v1.0.0 deployment and test the GPU model
2. Push new v2.0.0 model artifact to ACR
3. Update Git repository with new version
4. Watch GitOps automatically detect and upgrade
5. Verify v2.0.0 deployment and test upgraded model

**Duration:** ~3 minutes

**Model:** CUDA-optimized Llama 3.2 1B (int4 quantized, ~1GB, from onnx-community)

---

## ✅ Starting State: Verify v1.0.0

### Check Current Deployment

```bash
# Verify GitOps configuration exists
kubectl get gitrepository,kustomization,helmrelease -n foundry-system

# Check pod status
kubectl get pods -n foundry-system

# Verify v1.0.0 is deployed
kubectl logs -n foundry-system $(kubectl get pod -n foundry-system -l app.kubernetes.io/component=foundry -o jsonpath='{.items[0].metadata.name}') 2>/dev/null | grep -E "Tag.*v"
```

**Expected Output:** `🏷️ Tag: v1.0.0`

### Check Current Registry State

```bash
# List available model versions in ACR
oras repo tags foundryoci.azurecr.io/byo-models-gpu/llama-3.2-1b-cuda

# Check what ImagePolicy detected
kubectl get imagepolicy foundry-local-olive-models -n flux-system -o jsonpath='{.status.latestImage}'; echo
```

**Expected:** Only v1.0.0 exists

### Test Current Model via Open WebUI

```bash
# Get Open WebUI URL
kubectl get svc -n foundry-system | grep openwebui
```

**Access:** http://192.168.8.100:30800

**Login:**
- Email: `admin@foundry.local`
- Password: `foundry123`

**Test:**
1. Login to Open WebUI
2. Select available model
3. Ask: "What is Kubernetes?"
4. Note the response quality/behavior

---

## 📦 Step 1: Push v2.0.0 Model Artifact

```bash
# Navigate to models directory
cd /home/lior/repos/fl-arc-gitops/apps/foundry-gpu-oras/models

# Login to ACR (if needed)
oras login foundryoci.azurecr.io

# Push v2.0.0 model artifact to registry
oras push foundryoci.azurecr.io/byo-models-gpu/llama-3.2-1b-cuda:v2.0.0 \
  --artifact-type "foundry/models" \
  models.tar.gz:application/gzip
```

**What This Does:** Publishes the new GPU model version as an OCI artifact in Azure Container Registry

### Verify New Artifact

```bash
# List all tags (should now show both versions)
oras repo tags foundryoci.azurecr.io/byo-models-gpu/llama-3.2-1b-cuda
```

**Expected Output:**

```text
v1.0.0
v2.0.0
```

### Watch ImageRepository Detect v2.0.0

```bash
# ImageRepository scans every 5s - watch it detect the new version
kubectl get imagerepository foundry-local-olive-models -n flux-system -w
```

**What to Observe:** LAST SCAN column updates (within 5-10 seconds)

```bash
# Check ImagePolicy selected v2.0.0 as latest
kubectl get imagepolicy foundry-local-olive-models -n flux-system -o jsonpath='{.status.latestImage}'; echo
```

**Expected:** `foundryoci.azurecr.io/byo-models-gpu/llama-3.2-1b-cuda:v2.0.0`

---

## 🔄 Step 2: Update Git Repository

```bash
# Navigate to repo root
cd /home/lior/repos/fl-arc-gitops

# Update HelmRelease manifest to use v2.0.0
sed -i 's/tag: v1.0.0/tag: v2.0.0/' apps/foundry-gpu-oras/helmrelease.yaml

# Verify the change
grep "tag:" apps/foundry-gpu-oras/helmrelease.yaml
```

**Expected Output:** `tag: v2.0.0`

```bash
# Commit the change
git add apps/foundry-gpu-oras/helmrelease.yaml
git commit -m "Upgrade Foundry Local GPU model to v2.0.0"

# Push to trigger GitOps
git push origin main
```

**What This Does:** Updates the desired state in Git, triggering GitOps reconciliation

---

## 👀 Step 3: Watch GitOps Automation

### Monitor Git Sync

```bash
# Watch GitRepository sync new commit (within 30s)
kubectl get gitrepository foundry-gitops -n foundry-system -w
```

**What to Observe:** Revision updates to new commit SHA

### Monitor HelmRelease Reconciliation

```bash
# Watch HelmRelease detect change and upgrade
kubectl get helmrelease foundry-gpu-oras -n foundry-system -w
```

**What to Observe:** Status changes from Ready → Reconciling → Ready

### Watch Pod Rollout

```bash
# Monitor pod replacement (Recreate strategy)
watch kubectl get pods -n foundry-system
```

**What to Observe:**

1. Old pod (v0.1.0) starts terminating
2. Old pod fully terminated
3. New pod (v0.2.0) starts creating
4. New pod downloads model (~90 seconds)
5. New pod becomes Running and Ready

**Key Point:** Recreate strategy ensures only one pod at a time (prevents GPU conflict)

---

## ✅ Step 4: Verify v2.0.0 Deployment

### Check New Version in Logs

```bash
# Verify v2.0.0 tag in pod logs
kubectl logs -n foundry-system $(kubectl get pod -n foundry-system -l app.kubernetes.io/component=foundry -o jsonpath='{.items[0].metadata.name}') 2>/dev/null | grep -E "Tag.*v"
```

**Expected Output:** `🏷️ Tag: v2.0.0`

### Check HelmRelease Status

```bash
# Verify upgrade succeeded
kubectl get helmrelease foundry-gpu-oras -n foundry-system
```

**Expected:** Shows upgrade succeeded with new revision (v7 or higher)

### Check Pod Status

```bash
# Get pod details
kubectl get pods -n foundry-system -l app.kubernetes.io/component=foundry
```

**Expected:** New pod running with recent AGE (< 3 minutes)

### Test Upgraded GPU Model via Open WebUI

**Access:** http://192.168.8.100:30800

**Test:**

1. Refresh Open WebUI in browser
2. Select "Llama 3.2 1B CUDA GPU" model
3. Ask: "Explain how CUDA acceleration works for AI models"
4. Compare response with v1.0.0
5. Note GPU-optimized performance improvements

---

## 📊 Show Before/After Comparison

### Compare ReplicaSets

```bash
# Show old and new ReplicaSets
kubectl get replicaset -n foundry-system -l app.kubernetes.io/component=foundry
```

**What to Show:**

- Old ReplicaSet (contains v1.0.0): DESIRED 0, CURRENT 0, READY 0
- New ReplicaSet (contains v2.0.0): DESIRED 1, CURRENT 1, READY 1

### Show HelmRelease History

```bash
# View HelmRelease events and status
kubectl describe helmrelease foundry-gpu-oras -n foundry-system
```

**What to Point Out:**

- Last successful revision
- Upgrade success message
- Chart version

### Show Complete State

```bash
# Show all GitOps resources
kubectl get gitrepository,kustomization,helmrelease,pods -n foundry-system

# Show Git commit history
git log --oneline -3

# Show OCI artifacts
oras repo tags foundryoci.azurecr.io/byo-models-gpu/llama-3.2-1b-cuda
```

---

## 🎬 Quick Demo Script

**For a live demo, run these commands in sequence:**

```bash
# 1. Show starting state (v1.0.0)
kubectl logs -n foundry-system $(kubectl get pod -n foundry-system -l app.kubernetes.io/component=foundry -o jsonpath='{.items[0].metadata.name}') 2>/dev/null | grep -E "Tag.*v"
kubectl get pods -n foundry-system

# 2. Test in UI (browser)
# http://192.168.8.100:30800 - test GPU model

# 3. Push v2.0.0 to registry
cd /home/lior/repos/fl-arc-gitops/apps/foundry-gpu-oras/models
oras push foundryoci.azurecr.io/byo-models-gpu/llama-3.2-1b-cuda:v2.0.0 \
  --artifact-type "foundry/models" models.tar.gz:application/gzip

# 4. Update Git
cd /home/lior/repos/fl-arc-gitops
sed -i 's/tag: v1.0.0/tag: v2.0.0/' apps/foundry-gpu-oras/helmrelease.yaml
git add apps/foundry-gpu-oras/helmrelease.yaml
git commit -m "Upgrade to v2.0.0"
git push origin main

# 5. Watch the magic happen
watch kubectl get pods -n foundry-system

# 6. Verify new version
kubectl logs -n foundry-system $(kubectl get pod -n foundry-system -l app.kubernetes.io/component=foundry -o jsonpath='{.items[0].metadata.name}') 2>/dev/null | grep -E "Tag.*v"

# 7. Test in UI again - compare GPU performance
```

---

## 🧹 Reset for Next Demo

```bash
# Quick reset back to v1.0.0
bash scripts/demo/demo-cleanup.sh --soft
```

**This will:**

- Delete v2.0.0 artifact from registry
- Revert Git to v1.0.0
- Let GitOps rollback automatically
- Validate successful rollback

---

## 🎯 Key Demo Points

**Emphasize These Concepts:**

1. **Declarative** - Desired state in Git, actual state reconciled automatically
2. **Observable** - Complete visibility into every step via kubectl
3. **Automated** - No manual kubectl apply, everything via GitOps
4. **Safe** - Recreate strategy prevents GPU conflicts
5. **Versioned** - GPU models treated as code with semver and OCI artifacts
6. **Fast** - 5s scan intervals, ~3min total upgrade time
7. **GPU-Optimized** - CUDA-accelerated ONNX Runtime GenAI models with int4 quantization

---

## 📝 Demo Notes

- **Model:** Llama 3.2 1B (CUDA int4 quantized, from onnx-community)
- **Model Size:** ~1GB compressed
- **Download Time:** ~60 seconds (cached layers speed up v2.0.0)
- **Git Sync:** 30 seconds (configurable)
- **GPU:** RTX 5080 16GB (single GPU, hence Recreate strategy)
- **Registry:** Public ACR with anonymous pull
- **Total Time:** ~2-3 minutes from Git push to pod ready
- **ACR Repository:** Hierarchical structure (byo-models-gpu/llama-3.2-1b-cuda)

---

**Last Updated:** October 18, 2025
