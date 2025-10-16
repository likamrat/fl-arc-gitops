# Quick Start Guide - E2E GitOps Flow Test

## ✅ System Status

### Pre-flight Checklist
- ✅ **Cluster**: Clean (no deployments)
- ✅ **Git**: All code committed (latest: commit 590b548)
- ✅ **Registry**: v0.1.0 available (702 MB)
- ✅ **Flux Controllers**: All 8 healthy (2/2 or 1/1 Running)
- ✅ **Azure Arc**: ROG-AI cluster connected
- ✅ **Intervals**: Optimized (3s Git/Kustomization, 5s ImageRepository)
- ✅ **Recreate Strategy**: Applied in Helm chart
- ✅ **Anonymous Pull**: Enabled (no ACR credentials needed)

---

## 🚀 Execute E2E Test

### Option 1: Full Automated Test (Recommended)

Run the entire flow in one command:

```bash
cd /home/lior/repos/fl-arc-gitops
bash scripts/gitops-config.sh && \
echo "⏳ Waiting 2 minutes for deployment..." && \
sleep 120 && \
kubectl get pods -n foundry-system && \
kubectl logs -n foundry-system -l app.kubernetes.io/component=foundry | grep "Tag:"
```

**Expected output:**
- GitOps configuration created
- Pod running (1/1 Ready)
- Logs show: `🏷️ Tag: v0.1.0`

---

### Option 2: Step-by-Step Test

**Step 1: Deploy GitOps Configuration**
```bash
cd /home/lior/repos/fl-arc-gitops
bash scripts/gitops-config.sh
```

**Step 2: Monitor Deployment** (wait ~2 minutes)
```bash
watch kubectl get pods -n foundry-system
# Press Ctrl+C when pod is 1/1 Running
```

**Step 3: Verify v0.1.0**
```bash
kubectl logs -n foundry-system -l app.kubernetes.io/component=foundry | grep "Tag:"
```

**Step 4: Test Upgrade Flow** (Optional)
```bash
# Push v0.2.0 artifact
cd /home/lior/repos/fl-arc-gitops/apps/foundry-gpu-oras/models
oras push foundryoci.azurecr.io/foundry-local-olive-models:v0.2.0 \
  --artifact-type "foundry/models" \
  models.tar.gz:application/gzip

# Update Git
cd /home/lior/repos/fl-arc-gitops
sed -i 's/tag: v0.1.0/tag: v0.2.0/' apps/foundry-gpu-oras/helmrelease.yaml
git add apps/foundry-gpu-oras/helmrelease.yaml
git commit -m "Update Foundry Local model to v0.2.0"
git push origin main

# Monitor upgrade (with Recreate strategy)
watch kubectl get pods -n foundry-system
```

---

## 📊 Performance Expectations

### Timing Targets
| Phase | Target Time |
|-------|-------------|
| GitOps config creation | ~30s |
| Git sync + Kustomization | < 10s |
| HelmRelease install | ~30s |
| Model download (702 MB) | ~90s |
| **Total to Pod Ready** | **~2 minutes** |

### Upgrade Flow (v0.1.0 → v0.2.0)
| Phase | Target Time |
|-------|-------------|
| OCI push | Instant |
| ImageRepository detection | < 7s |
| Git update + push | ~30s |
| GitOps sync | < 5s |
| Kustomization apply | < 5s |
| Recreate pod termination | ~30s |
| New pod + model download | ~90s |
| **Total upgrade time** | **~2.5 minutes** |

---

## 🔍 Verification Commands

```bash
# Check all Flux resources
kubectl get gitrepository,kustomization,helmrelease -n foundry-system

# Check ImageRepository
kubectl get imagerepository,imagepolicy -n flux-system

# Check pod status
kubectl get pods -n foundry-system

# View pod logs
kubectl logs -n foundry-system -l app.kubernetes.io/component=foundry

# Check BYO models
POD_NAME=$(kubectl get pod -n foundry-system -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n foundry-system $POD_NAME -- ls -la /home/foundry/.foundry/cache/models/
```

---

## 🧹 Cleanup After Test

```bash
# Delete GitOps configuration
az k8s-configuration flux delete \
  --name foundry-gitops \
  --cluster-name ROG-AI \
  --cluster-type connectedClusters \
  --resource-group Foundry-Arc \
  --yes

# Wait and verify
sleep 30
kubectl get all -n foundry-system

# Delete namespace
kubectl delete namespace foundry-system

# Delete image resources
kubectl delete imagerepository foundry-local-olive-models -n flux-system
kubectl delete imagepolicy foundry-local-olive-models -n flux-system
```

---

## 📚 Documentation Reference

- **Full Test Plan**: See [E2E_TEST_PLAN.md](E2E_TEST_PLAN.md)
- **GitOps Flow**: See [GITOPS_FLOW_SUMMARY.md](GITOPS_FLOW_SUMMARY.md)
- **Cleanup Status**: See [CLEANUP_STATUS.md](CLEANUP_STATUS.md)

---

## 🎯 Success Criteria

✅ **GitOps configuration created in < 1 minute**  
✅ **Pod running with v0.1.0 in < 2 minutes**  
✅ **BYO models downloaded successfully**  
✅ **All Flux controllers healthy**  
✅ **3-second sync intervals working**  
✅ **Recreate strategy prevents GPU deadlock**

---

**Ready to start? Run:** `bash scripts/gitops-config.sh` 🚀
