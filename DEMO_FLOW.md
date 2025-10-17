# GitOps Demo Flow - AI Model Upgrade

A hands-on guide demonstrating GitOps-driven AI model upgrades from v0.1.0 to v0.2.0 using Azure Arc and Flux CD.

## 🎯 Demo Overview

**Starting Point:** Foundry Local v0.1.0 already deployed via GitOps

**What You'll Demonstrate:**
1. Verify current v0.1.0 deployment and test the model
2. Push new v0.2.0 model artifact to ACR
3. Update Git repository with new version
4. Watch GitOps automatically detect and upgrade
5. Verify v0.2.0 deployment and test upgraded model

**Duration:** ~3 minutes

---

## ✅ Starting State: Verify v0.1.0

### Check Current Deployment

```bash
# Verify GitOps configuration exists
kubectl get gitrepository,kustomization,helmrelease -n foundry-system

# Check pod status
kubectl get pods -n foundry-system

# Verify v0.1.0 is deployed
kubectl logs -n foundry-system $(kubectl get pod -n foundry-system -l app.kubernetes.io/component=foundry -o jsonpath='{.items[0].metadata.name}') 2>/dev/null | grep -E "Tag.*v0"
```

**Expected Output:** `🏷️ Tag: v0.1.0`

### Check Current Registry State

```bash
# List available model versions in ACR
oras repo tags foundryoci.azurecr.io/foundry-local-olive-models

# Check what ImagePolicy detected
kubectl get imagepolicy foundry-local-olive-models -n flux-system -o jsonpath='{.status.latestImage}'; echo
```

**Expected:** Only v0.1.0 exists

### Test Current Model via Open WebUI

```bash
# Get Open WebUI URL
kubectl get svc -n foundry-system | grep openwebui
```

**Access:** http://192.168.1.46:30800

**Login:**
- Email: `admin@foundry.local`
- Password: `foundry123`

**Test:**
1. Login to Open WebUI
2. Select available model
3. Ask: "What is Kubernetes?"
4. Note the response quality/behavior

---

## 📦 Step 1: Push v0.2.0 Model Artifact

```bash
# Navigate to models directory
cd /home/lior/repos/fl-arc-gitops/apps/foundry-gpu-oras/models

# Login to ACR (if needed)
oras login foundryoci.azurecr.io

# Push v0.2.0 model artifact to registry
oras push foundryoci.azurecr.io/foundry-local-olive-models:v0.2.0 \
  --artifact-type "foundry/models" \
  models.tar.gz:application/gzip
```

**What This Does:** Publishes the new model version as an OCI artifact in Azure Container Registry

### Verify New Artifact

```bash
# List all tags (should now show both versions)
oras repo tags foundryoci.azurecr.io/foundry-local-olive-models
```

**Expected Output:**

```text
v0.1.0
v0.2.0
```

### Watch ImageRepository Detect v0.2.0

```bash
# ImageRepository scans every 10s - watch it detect the new version
kubectl get imagerepository foundry-local-olive-models -n flux-system -w
```

**What to Observe:** LAST SCAN column updates (within 10 seconds)

```bash
# Check ImagePolicy selected v0.2.0 as latest
kubectl get imagepolicy foundry-local-olive-models -n flux-system -o jsonpath='{.status.latestImage}'; echo
```

**Expected:** `foundryoci.azurecr.io/foundry-local-olive-models:v0.2.0`

---

## 🔄 Step 2: Update Git Repository

```bash
# Navigate to repo root
cd /home/lior/repos/fl-arc-gitops

# Update HelmRelease manifest to use v0.2.0
sed -i 's/tag: v0.1.0/tag: v0.2.0/' apps/foundry-gpu-oras/helmrelease.yaml

# Verify the change
grep "tag:" apps/foundry-gpu-oras/helmrelease.yaml
```

**Expected Output:** `tag: v0.2.0`

```bash
# Commit the change
git add apps/foundry-gpu-oras/helmrelease.yaml
git commit -m "Upgrade Foundry Local model to v0.2.0"

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

## ✅ Step 4: Verify v0.2.0 Deployment

### Check New Version in Logs

```bash
# Verify v0.2.0 tag in pod logs
kubectl logs -n foundry-system $(kubectl get pod -n foundry-system -l app.kubernetes.io/component=foundry -o jsonpath='{.items[0].metadata.name}') 2>/dev/null | grep -E "Tag.*v0"
```

**Expected Output:** `🏷️ Tag: v0.2.0`

### Check HelmRelease Status

```bash
# Verify upgrade succeeded
kubectl get helmrelease foundry-gpu-oras -n foundry-system
```

**Expected:** Shows upgrade succeeded with new revision (v3 or higher)

### Check Pod Status

```bash
# Get pod details
kubectl get pods -n foundry-system -l app.kubernetes.io/component=foundry
```

**Expected:** New pod running with recent AGE (< 2 minutes)

### Test Upgraded Model via Open WebUI

**Access:** http://192.168.1.46:30800

**Test:**

1. Refresh Open WebUI in browser
2. Ask same question: "What is Kubernetes?"
3. Compare response with v0.1.0
4. Note any improvements or differences

---

## 📊 Show Before/After Comparison

### Compare ReplicaSets

```bash
# Show old and new ReplicaSets
kubectl get replicaset -n foundry-system -l app.kubernetes.io/component=foundry
```

**What to Show:**

- Old ReplicaSet (contains v0.1.0): DESIRED 0, CURRENT 0, READY 0
- New ReplicaSet (contains v0.2.0): DESIRED 1, CURRENT 1, READY 1

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
oras repo tags foundryoci.azurecr.io/foundry-local-olive-models
```

---

## 🎬 Quick Demo Script

**For a live demo, run these commands in sequence:**

```bash
# 1. Show starting state (v0.1.0)
kubectl logs -n foundry-system $(kubectl get pod -n foundry-system -l app.kubernetes.io/component=foundry -o jsonpath='{.items[0].metadata.name}') 2>/dev/null | grep -E "Tag.*v0"
kubectl get pods -n foundry-system

# 2. Test in UI (browser)
# http://192.168.1.46:30800 - ask a question

# 3. Push v0.2.0 to registry
cd /home/lior/repos/fl-arc-gitops/apps/foundry-gpu-oras/models
oras push foundryoci.azurecr.io/foundry-local-olive-models:v0.2.0 \
  --artifact-type "foundry/models" models.tar.gz:application/gzip

# 4. Update Git
cd /home/lior/repos/fl-arc-gitops
sed -i 's/tag: v0.1.0/tag: v0.2.0/' apps/foundry-gpu-oras/helmrelease.yaml
git add apps/foundry-gpu-oras/helmrelease.yaml
git commit -m "Upgrade to v0.2.0"
git push origin main

# 5. Watch the magic happen
watch kubectl get pods -n foundry-system

# 6. Verify new version
kubectl logs -n foundry-system $(kubectl get pod -n foundry-system -l app.kubernetes.io/component=foundry -o jsonpath='{.items[0].metadata.name}') 2>/dev/null | grep -E "Tag.*v0"

# 7. Test in UI again - compare responses
```

---

## 🧹 Reset for Next Demo

```bash
# Quick reset back to v0.1.0
bash scripts/demo-cleanup.sh --soft
```

**This will:**

- Delete v0.2.0 artifact from registry
- Revert Git to v0.1.0
- Let GitOps rollback automatically
- Validate successful rollback

---

## 🎯 Key Demo Points

**Emphasize These Concepts:**

1. **Declarative** - Desired state in Git, actual state reconciled automatically
2. **Observable** - Complete visibility into every step via kubectl
3. **Automated** - No manual kubectl apply, everything via GitOps
4. **Safe** - Recreate strategy prevents GPU conflicts
5. **Versioned** - Models treated as code with semver and OCI artifacts
6. **Fast** - 30s sync intervals, ~2min total upgrade time

---

## 📝 Demo Notes

- **Model Size:** 702MB
- **Download Time:** ~90 seconds
- **Git Sync:** 30 seconds (configurable)
- **GPU:** RTX 5080 (single GPU, hence Recreate strategy)
- **Registry:** Public ACR with anonymous pull
- **Total Time:** ~2 minutes from Git push to pod ready

---

**Last Updated:** October 17, 2025
