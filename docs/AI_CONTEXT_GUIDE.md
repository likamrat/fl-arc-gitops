# AI Context Guide - GitOps Demo Environment

> **Purpose:** This document provides complete context for AI assistants working with this GitOps demo repository. Use this to quickly understand the system architecture, demo workflow, and key operations.

---

## 🎯 Project Overview

**What is this?**
A GitOps-based AI model deployment demo showcasing:
- Automatic model upgrades via Git commits
- GPU-accelerated AI inference with Foundry Local
- Multi-cluster Arc-enabled Kubernetes management
- ORAS OCI artifacts for model storage in Azure Container Registry

**Key Technologies:**
- **Kubernetes:** Two k3s v1.33.5 clusters (rog-fl-01, rog-fl-02)
- **GitOps:** Flux CD v1.18.2 via Azure Arc extension
- **GPU:** NVIDIA GeForce RTX 5080 (16GB) with CUDA 12.8
- **AI Platform:** Foundry Local + OpenWebUI
- **Model Storage:** Azure Container Registry with ORAS
- **Model:** CUDA-optimized Llama 3.2 1B (~1GB compressed)

---

## 🏗️ Architecture

### Two-Cluster Setup

| Cluster | IP | Purpose | GitOps State |
|---------|-----|---------|--------------|
| **rog-fl-01** | 192.168.8.101 | Demo upgrade cluster | Active (watches Git) |
| **rog-fl-02** | 192.168.8.102 | "Preview" cluster | Suspended (shows final state) |

### Application Endpoints

| Service | ROG-FL-01 | ROG-FL-02 |
|---------|-----------|-----------|
| Foundry Local | 192.168.8.101:30500 | 192.168.8.102:30500 |
| OpenWebUI | 192.168.8.101:30800 | 192.168.8.102:30800 |

### Model Versions

| Version | Description | Demo Usage |
|---------|-------------|------------|
| **v1.0.0** | Baseline model | Starting point for demo |
| **v2.0.0** | Upgraded model | Target for demo upgrade |

---

## 📂 Repository Structure

```
fl-arc-gitops/
├── apps/
│   └── foundry-gpu-oras/
│       ├── helmrelease.yaml          # GitOps manifest (line 36: tag version)
│       ├── values.yaml                # Helm values
│       ├── models/
│       │   └── models.tar.gz         # Model artifact (~1GB) for ORAS push
│       └── chart/                     # Helm chart for Foundry Local
├── docs/
│   ├── DEMO_TALK_TRACK.md            # Complete demo presentation guide
│   ├── AI_CONTEXT_GUIDE.md           # This file
│   ├── DEMO_FLOW_SUMMARY.md
│   └── GITOPS_FLOW_SUMMARY.md
├── scripts/
│   ├── demo/
│   │   ├── demo-prep.sh              # Automated demo preparation
│   │   └── demo-cleanup.sh           # Automated cleanup (--full or --soft)
│   └── setup/
│       ├── flux-setup.sh
│       └── gitops-config.sh
└── infrastructure/
    └── kustomization.yaml
```

---

## 🔑 Key Files and Line Numbers

### Critical File: `apps/foundry-gpu-oras/helmrelease.yaml`

**Line 36:** The model version tag
```yaml
tag: v1.0.0  # Change this to v2.0.0 to trigger upgrade
```

**Why it matters:** Flux watches this file. When you change the tag and push to Git, GitOps automatically upgrades the deployment.

### Demo Preparation Script: `scripts/demo/demo-prep.sh`

**Automates:**
1. Suspends GitOps on rog-fl-02
2. Verifies both clusters at v2.0.0
3. Deletes v2.0.0 from ACR
4. Rolls back Git to v1.0.0
5. Waits for rog-fl-01 to rollback (~5 minutes)
6. Verifies demo-ready state

**Run:**
```bash
cd ~/repos/fl-arc-gitops
./scripts/demo/demo-prep.sh
```

### Demo Cleanup Script: `scripts/demo/demo-cleanup.sh`

**Two modes:**
- `--soft`: GitOps rollback only (preserves Flux config)
- `--full`: Complete reset (removes Flux config, namespace)

**Run:**
```bash
./scripts/demo/demo-cleanup.sh --soft [--dry-run]
./scripts/demo/demo-cleanup.sh --full [--dry-run]
```

---

## 🎬 Demo Workflow

### Pre-Demo State (Goal)

```
┌─────────────────────────────────────────────────────────┐
│ rog-fl-01: v1.0.0 (GitOps ACTIVE)                      │
│ rog-fl-02: v2.0.0 (GitOps SUSPENDED)                   │
│ ACR: v1.0.0 only                                        │
│ Git: apps/foundry-gpu-oras/helmrelease.yaml at v1.0.0  │
└─────────────────────────────────────────────────────────┘
```

### Demo Flow (21 Steps)

**Phase 1: Show Current State (Steps 1-9)**
1. Show architecture diagram (PowerPoint)
2. Show Arc-enabled cluster in Azure Portal
3. Show ACR with v1.0.0 tag only
4. Show GitHub repo at v1.0.0
5. Show helmrelease.yaml with v1.0.0 tag
6. Check pods on rog-fl-01
7. List models in Foundry
8. Verify v1.0.0 from logs
9. Test v1.0.0 in OpenWebUI

**Phase 2: Trigger Upgrade (Steps 10-15)**
10. Start watching pods on rog-fl-01
11. Push v2.0.0 to ACR with ORAS CLI
12. Verify v2.0.0 in ACR
13. Edit helmrelease.yaml (v1.0.0 → v2.0.0)
14. Git commit and push (GitOps triggers)
15. Watch pod termination and new pod creation

**Phase 3: Multi-Cluster Demo (Steps 16-18)**
16. Switch to rog-fl-02 (while rog-fl-01 upgrades)
17. Show rog-fl-02 already has v2.0.0
18. Test v2.0.0 in OpenWebUI on rog-fl-02

**Phase 4: Verify & Close (Steps 19-21)**
19. Return to rog-fl-01, confirm upgrade complete
20. Show GPU usage with nvitop during inference
21. Show closing architecture diagram

### Key Commands During Demo

**ORAS Push (Step 11):**
```bash
cd apps/foundry-gpu-oras/models
oras push foundryoci.azurecr.io/byo-models-gpu/llama-3.2-1b-cuda:v2.0.0 \
  --artifact-type "foundry/models" \
  models.tar.gz:application/gzip
```

**Git Update (Step 14):**
```bash
# Edit helmrelease.yaml line 36: v1.0.0 → v2.0.0
git add apps/foundry-gpu-oras/helmrelease.yaml
git commit -m "Upgrade Foundry Local GPU model to v2.0.0"
git push origin main
```

**Watch Pods (Step 15):**
```bash
kubectx rog-fl-01
kubectl get pods -n foundry-system -w
```

**Switch Cluster (Step 16):**
```bash
kubectx rog-fl-02
kubectl get pods -n foundry-system
```

---

## 🔧 Common Operations

### Check Current Version

**On Cluster:**
```bash
kubectx rog-fl-01  # or rog-fl-02
kubectl logs -n foundry-system \
  $(kubectl get pod -n foundry-system -l app.kubernetes.io/component=foundry -o jsonpath='{.items[0].metadata.name}') \
  | grep -E "(Registry:|Repository:|Tag:)" | grep -v "UserAgent"
```

**In Git:**
```bash
grep "tag:" apps/foundry-gpu-oras/helmrelease.yaml | head -1
```

**In ACR:**
```bash
oras repo tags foundryoci.azurecr.io/byo-models-gpu/llama-3.2-1b-cuda
```

### Suspend/Resume GitOps

**Suspend (freeze cluster state):**
```bash
kubectx rog-fl-02
kubectl patch kustomization foundry-gitops-apps -n foundry-system \
  -p '{"spec":{"suspend":true}}' --type=merge
```

**Resume (enable GitOps):**
```bash
kubectx rog-fl-02
kubectl patch kustomization foundry-gitops-apps -n foundry-system \
  -p '{"spec":{"suspend":false}}' --type=merge
```

### Manual Version Change in Git

**Upgrade v1.0.0 → v2.0.0:**
```bash
sed -i 's/tag: v1.0.0/tag: v2.0.0/' apps/foundry-gpu-oras/helmrelease.yaml
git add apps/foundry-gpu-oras/helmrelease.yaml
git commit -m "Upgrade to v2.0.0"
git push origin main
```

**Rollback v2.0.0 → v1.0.0:**
```bash
sed -i 's/tag: v2.0.0/tag: v1.0.0/' apps/foundry-gpu-oras/helmrelease.yaml
git add apps/foundry-gpu-oras/helmrelease.yaml
git commit -m "Rollback to v1.0.0"
git push origin main
```

### Delete OCI Artifact

**Specific version:**
```bash
az acr repository delete --name foundryoci \
  --image byo-models-gpu/llama-3.2-1b-cuda:v2.0.0 --yes
```

**Using ORAS:**
```bash
oras manifest delete foundryoci.azurecr.io/byo-models-gpu/llama-3.2-1b-cuda:v2.0.0
```

### GPU Monitoring

**SSH to cluster node:**
```bash
ssh lior@192.168.8.101  # or 192.168.8.102
nvitop  # Interactive GPU monitor (replaces btop)
```

### Clean OpenWebUI Chats

**From pod:**
```bash
kubectl exec -n foundry-system \
  $(kubectl get pod -n foundry-system -l app.kubernetes.io/component=open-webui -o jsonpath='{.items[0].metadata.name}') \
  -- python3 -c '
import sqlite3
conn = sqlite3.connect("/app/backend/data/webui.db")
cursor = conn.cursor()
cursor.execute("DELETE FROM chat")
conn.commit()
cursor.execute("VACUUM")
conn.close()
'
```

---

## 🔍 Troubleshooting

### Pod Not Starting

**Check pod status:**
```bash
kubectl get pods -n foundry-system
kubectl describe pod <pod-name> -n foundry-system
kubectl logs <pod-name> -n foundry-system
```

**Check Flux status:**
```bash
kubectl get helmrelease foundry-gpu-oras -n foundry-system
kubectl describe helmrelease foundry-gpu-oras -n foundry-system
```

### GitOps Not Triggering

**Check GitRepository:**
```bash
kubectl get gitrepository -n foundry-system
kubectl describe gitrepository foundry-gitops -n foundry-system
```

**Check Kustomization:**
```bash
kubectl get kustomization -n foundry-system
kubectl describe kustomization foundry-gitops-apps -n foundry-system
```

**Force reconciliation:**
```bash
flux reconcile source git foundry-gitops -n foundry-system
flux reconcile kustomization foundry-gitops-apps -n foundry-system
```

### Model Not Loading

**Check init container logs:**
```bash
kubectl logs <pod-name> -n foundry-system -c init-models
```

**Check ORAS authentication:**
```bash
oras login foundryoci.azurecr.io
oras repo tags foundryoci.azurecr.io/byo-models-gpu/llama-3.2-1b-cuda
```

### Version Mismatch

**Verify all components:**
```bash
# Git
grep "tag:" apps/foundry-gpu-oras/helmrelease.yaml

# ACR
oras repo tags foundryoci.azurecr.io/byo-models-gpu/llama-3.2-1b-cuda

# ROG-FL-01
kubectx rog-fl-01
kubectl logs -n foundry-system \
  $(kubectl get pod -n foundry-system -l app.kubernetes.io/component=foundry -o jsonpath='{.items[0].metadata.name}') \
  | grep "Tag:"

# ROG-FL-02
kubectx rog-fl-02
kubectl logs -n foundry-system \
  $(kubectl get pod -n foundry-system -l app.kubernetes.io/component=foundry -o jsonpath='{.items[0].metadata.name}') \
  | grep "Tag:"
```

---

## 🔐 Prerequisites and Authentication

### Required Tools

| Tool | Purpose | Installation Check |
|------|---------|-------------------|
| `kubectx` | Kubernetes context switcher | `kubectx --version` |
| `kubectl` | Kubernetes CLI | `kubectl version` |
| `az` | Azure CLI | `az --version` |
| `oras` | OCI Registry as Storage | `oras version` |
| `git` | Version control | `git --version` |
| `flux` | Flux CLI (optional) | `flux --version` |
| `nvitop` | GPU monitor | `nvitop --version` |

### Authentication Check

**Azure CLI:**
```bash
az account show
# If not logged in: az login
```

**ORAS to ACR:**
```bash
oras repo tags foundryoci.azurecr.io/byo-models-gpu/llama-3.2-1b-cuda
# If auth fails: oras login foundryoci.azurecr.io
```

**Kubernetes Contexts:**
```bash
kubectx
# Should show: rog-fl-01, rog-fl-02
```

---

## 📊 State Verification Matrix

Use this to quickly verify system state:

| Component | Expected Demo Start | Check Command |
|-----------|---------------------|---------------|
| **rog-fl-01 Version** | v1.0.0 | `kubectx rog-fl-01 && kubectl logs -n foundry-system $(kubectl get pod -n foundry-system -l app.kubernetes.io/component=foundry -o jsonpath='{.items[0].metadata.name}') \| grep "Tag:"` |
| **rog-fl-02 Version** | v2.0.0 | `kubectx rog-fl-02 && kubectl logs -n foundry-system $(kubectl get pod -n foundry-system -l app.kubernetes.io/component=foundry -o jsonpath='{.items[0].metadata.name}') \| grep "Tag:"` |
| **rog-fl-02 GitOps** | Suspended | `kubectl get kustomization foundry-gitops-apps -n foundry-system -o jsonpath='{.spec.suspend}'` (should be `true`) |
| **Git Version** | v1.0.0 | `grep "tag:" apps/foundry-gpu-oras/helmrelease.yaml` |
| **ACR Tags** | v1.0.0 only | `oras repo tags foundryoci.azurecr.io/byo-models-gpu/llama-3.2-1b-cuda` |
| **rog-fl-01 Pods** | Running | `kubectl get pods -n foundry-system` |
| **rog-fl-02 Pods** | Running | `kubectx rog-fl-02 && kubectl get pods -n foundry-system` |

---

## 🎯 Quick Reference: What Changed When

### Version Migration Timeline

**Original Setup (Before This Demo):**
- Used v0.1.0 and other versions
- Single cluster demos
- Manual GitOps suspension

**Current Setup (v1.0.0/v2.0.0):**
- Standardized on v1.0.0 (baseline) and v2.0.0 (upgrade target)
- Two-cluster demo strategy
- Automated prep and cleanup scripts
- Enhanced documentation

### File Version References

All files now consistently use:
- **v1.0.0** - Baseline/starting version
- **v2.0.0** - Upgrade/target version

Updated files:
- `scripts/demo/demo-prep.sh` - Uses v1.0.0/v2.0.0
- `scripts/demo/demo-cleanup.sh` - Uses v1.0.0/v2.0.0
- `docs/DEMO_TALK_TRACK.md` - Uses v1.0.0/v2.0.0
- `apps/foundry-gpu-oras/helmrelease.yaml` - Tag on line 36

---

## 🚀 Getting Started Checklist

When working with this repo for the first time (or after losing context):

1. **Verify Prerequisites:**
   - [ ] All required tools installed
   - [ ] Azure CLI authenticated
   - [ ] ORAS CLI authenticated to ACR
   - [ ] kubectl contexts configured for both clusters

2. **Understand Current State:**
   - [ ] Check Git version: `grep "tag:" apps/foundry-gpu-oras/helmrelease.yaml`
   - [ ] Check ACR tags: `oras repo tags foundryoci.azurecr.io/byo-models-gpu/llama-3.2-1b-cuda`
   - [ ] Check rog-fl-01 version
   - [ ] Check rog-fl-02 version and GitOps suspension status

3. **Prepare for Demo (if needed):**
   - [ ] Run `./scripts/demo/demo-prep.sh`
   - [ ] Wait for completion (~5 minutes)
   - [ ] Verify demo-ready state using State Verification Matrix

4. **Review Demo Flow:**
   - [ ] Read `docs/DEMO_TALK_TRACK.md`
   - [ ] Understand 21-step demo flow
   - [ ] Note critical commands and timing

---

## 📝 Important Notes

### What NOT to Do

❌ **Don't manually edit resources on cluster** - Use Git
❌ **Don't delete v1.0.0 from ACR** - It's the baseline
❌ **Don't forget to suspend rog-fl-02 GitOps** - Demo will fail
❌ **Don't use `btop`** - Use `nvitop` for GPU monitoring
❌ **Don't skip authentication checks** - ORAS and Azure CLI must be logged in

### Demo Timing

- **Total demo time:** ~10-15 minutes
- **Pod upgrade time:** ~2-3 minutes (includes model download)
- **GitOps detection time:** ~5-30 seconds after Git push
- **Rollback time:** ~5 minutes (full pod recreation)

### Model File Location

The model artifact (`models.tar.gz`) must exist at:
```
apps/foundry-gpu-oras/models/models.tar.gz
```

Size: ~1GB compressed
Contains: CUDA-optimized Llama 3.2 1B ONNX model

---

## 🔗 Related Documentation

- **Demo Talk Track:** `docs/DEMO_TALK_TRACK.md` - Complete presentation guide
- **Demo Flow Summary:** `docs/DEMO_FLOW_SUMMARY.md` - Quick reference
- **GitOps Flow:** `docs/GITOPS_FLOW_SUMMARY.md` - Technical details
- **Cleanup Guide:** `docs/CLEANUP_GUIDE.md` - Post-demo cleanup
- **GPU Operator Install:** `docs/GPU_OPERATOR_INSTALLATION.md` - GPU setup

---

## 🆘 Emergency Recovery

If demo goes wrong:

**Option 1: Soft Cleanup (Preserve Flux)**
```bash
./scripts/demo/demo-cleanup.sh --soft
# Then re-run prep:
./scripts/demo/demo-prep.sh
```

**Option 2: Full Reset**
```bash
./scripts/demo/demo-cleanup.sh --full
# Then re-deploy:
./scripts/setup/gitops-config.sh
# Then prep for demo:
./scripts/demo/demo-prep.sh
```

**Option 3: Manual Recovery**
1. Resume GitOps on both clusters
2. Delete all OCI artifacts except v1.0.0
3. Reset Git to v1.0.0
4. Wait for GitOps to sync
5. Suspend GitOps on rog-fl-02
6. Push v2.0.0 to ACR
7. Edit Git to v2.0.0
8. Wait for rog-fl-02 to reach v2.0.0
9. Suspend GitOps on rog-fl-02
10. Rollback Git to v1.0.0
11. Wait for rog-fl-01 to rollback

---

## 💡 Pro Tips

1. **Always check authentication first** - Most issues are auth-related
2. **Use `--dry-run` flags** - Test scripts before running
3. **Monitor Flux events** - `kubectl get events -n foundry-system --sort-by='.lastTimestamp'`
4. **Keep models.tar.gz backed up** - It's large and slow to download
5. **Test OpenWebUI before demo** - Ensure both instances are accessible
6. **Clean chats before demo** - Fresh start looks professional
7. **Have `nvitop` running during demo** - GPU usage is impressive

---

**Last Updated:** November 11, 2025
**Maintained By:** AI Assistant with human collaboration
**Version:** 1.0.0
