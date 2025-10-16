# End-to-End GitOps Flow Test Plan

## Test Environment Ready ✅

### Current State
- ✅ Cluster: Clean (no deployments)
- ✅ Git: All code committed and pushed (commit: 15a5681)
- ✅ Registry: v0.1.0 available
- ✅ Flux Controllers: Healthy (8/8 running)
- ✅ Azure Arc: Connected (ROG-AI cluster)

### Configuration Optimizations
- **GitRepository**: 3s sync interval
- **Kustomizations**: 3s sync, 3s retry
- **ImageRepository**: 5s scan interval
- **Recreate Strategy**: Applied in Helm chart
- **BYO ORAS**: Properly configured under `foundry.byo`
- **Anonymous Pull**: Enabled (no provider in ImageRepository)

---

## Test Scenario: v0.1.0 → v0.2.0 Upgrade

### Phase 1: Initial Deployment (v0.1.0)

**Step 1: Deploy GitOps Configuration**
```bash
cd /home/lior/repos/fl-arc-gitops
bash scripts/gitops-config.sh
```

**Expected Results:**
- GitRepository created and synced (within 3s)
- Kustomizations applied (within 3s each)
- ImageRepository detecting v0.1.0 (within 5s)
- HelmRelease installed (v1)
- Pod running with v0.1.0 BYO models

**Verification Commands:**
```bash
# Check all resources
kubectl get gitrepository,kustomization,helmrelease,pods -n foundry-system

# Verify v0.1.0 in pod logs
kubectl logs -n foundry-system -l app.kubernetes.io/component=foundry | grep "Tag:"

# Check ImageRepository
kubectl get imagerepository,imagepolicy -n flux-system
```

**Success Criteria:**
- ✅ All resources: Ready/Running
- ✅ Pod logs show: `🏷️ Tag: v0.1.0`
- ✅ BYO models downloaded successfully
- ✅ ImageRepository: 1 tag detected

---

### Phase 2: Trigger GitOps Flow (Push v0.2.0)

**Step 2: Push v0.2.0 OCI Artifact**
```bash
cd /home/lior/repos/fl-arc-gitops/apps/foundry-gpu-oras/models
oras push foundryoci.azurecr.io/foundry-local-olive-models:v0.2.0 \
  --artifact-type "foundry/models" \
  models.tar.gz:application/gzip
```

**Step 3: Monitor ImageRepository Detection**
```bash
# Wait 5-7 seconds
sleep 7
kubectl get imagerepository,imagepolicy -n flux-system
```

**Expected Results:**
- ImageRepository TAGS: 2 (v0.1.0, v0.2.0)
- ImagePolicy LATESTIMAGE: v0.2.0

---

### Phase 3: Manual Git Update (Required Step)

**Step 4: Update Git with v0.2.0**
```bash
cd /home/lior/repos/fl-arc-gitops
# Update helmrelease.yaml tag from v0.1.0 to v0.2.0
sed -i 's/tag: v0.1.0/tag: v0.2.0/' apps/foundry-gpu-oras/helmrelease.yaml
git add apps/foundry-gpu-oras/helmrelease.yaml
git commit -m "Update Foundry Local model to v0.2.0"
git push origin main
```

**Step 5: Monitor GitOps Sync (3s intervals)**
```bash
# Wait 3-5 seconds for Git sync
sleep 5
kubectl get gitrepository -n foundry-system -o jsonpath='{.status.artifact.revision}'
```

**Expected Results:**
- GitRepository synced to new commit (within 3s)

---

### Phase 4: Automatic Deployment

**Step 6: Monitor Kustomization and HelmRelease**
```bash
# Wait 3-5 seconds for Kustomizations
sleep 5
kubectl get kustomization,helmrelease -n foundry-system
```

**Expected Results:**
- Kustomizations: Applied new revision (within 3s)
- HelmRelease: Starting upgrade (v1 → v2)

**Step 7: Monitor Pod Upgrade with Recreate Strategy**
```bash
kubectl get pods -n foundry-system -w
```

**Expected Behavior:**
- Old pod: **Terminating** (Recreate strategy)
- No new pod starts until old pod is gone
- New pod: **ContainerCreating** → **Running**
- **No GPU deadlock** (only one pod at a time)

**Step 8: Verify v0.2.0 Deployment**
```bash
# Check pod logs
kubectl logs -n foundry-system -l app.kubernetes.io/component=foundry | grep "Tag:"

# Check BYO models
kubectl exec -n foundry-system <pod-name> -- ls -la /home/foundry/.foundry/cache/models/
```

**Success Criteria:**
- ✅ Pod logs show: `🏷️ Tag: v0.2.0`
- ✅ BYO models downloaded from v0.2.0 artifact
- ✅ New models available (e.g., llama-3.2)
- ✅ HelmRelease: v2 succeeded
- ✅ No GPU deadlock occurred

---

## Performance Metrics to Record

### Timing Checkpoints
1. **OCI Push → ImageRepository Detection**: Target < 7s
2. **Git Push → GitRepository Sync**: Target < 5s
3. **GitRepository → Kustomization Apply**: Target < 5s
4. **Kustomization → HelmRelease Upgrade Start**: Target < 5s
5. **Old Pod Termination → New Pod Running**: ~90s (includes model download)
6. **Total End-to-End**: Target < 2 minutes (excluding model download)

### Resource Monitoring
- Flux controller CPU/Memory usage
- GitHub API rate limit status
- Network bandwidth during model download

---

## Rollback Test (Optional)

**Step 9: Rollback to v0.1.0**
```bash
cd /home/lior/repos/fl-arc-gitops
sed -i 's/tag: v0.2.0/tag: v0.1.0/' apps/foundry-gpu-oras/helmrelease.yaml
git add apps/foundry-gpu-oras/helmrelease.yaml
git commit -m "Rollback Foundry Local model to v0.1.0"
git push origin main
```

**Monitor the same flow (3s sync intervals)**

---

## Known Limitations

1. **Manual Git Update Required**
   - ImageUpdateAutomation exists but no Git write credentials
   - Must manually update Git after detecting new OCI artifacts
   - Future: Add GitHub PAT for full automation

2. **3-Second Intervals**
   - Very aggressive, suitable for demos
   - Monitor GitHub API rate limits (5000 req/hour)
   - Production: Consider 5-10s intervals

3. **Model Download Time**
   - 702 MB artifact takes ~60-90s to download
   - Not counted in GitOps flow timing
   - Depends on network speed

---

## Success Criteria Summary

### Functional Requirements
- ✅ OCI artifact push triggers detection
- ✅ Git update triggers deployment
- ✅ Recreate strategy prevents GPU deadlock
- ✅ BYO ORAS downloads correct version
- ✅ End-to-end flow completes without errors

### Performance Requirements
- ✅ GitOps flow < 15 seconds (pre-download)
- ✅ All sync intervals optimized (3s, 5s)
- ✅ No pod crashes or restarts

### Reliability Requirements
- ✅ Flux controllers remain healthy
- ✅ No GitHub API rate limiting
- ✅ Azure Arc stays connected

---

**Ready to execute test/home/lior/repos/fl-arc-gitops && \
git add CLEANUP_STATUS.md GITOPS_FLOW_SUMMARY.md scripts/*.sh && \
git commit -m "docs: Add cleanup status, GitOps flow summary and utility scripts" && \
git push origin main* 🚀
