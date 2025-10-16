# GitOps Flow Summary - Foundry Local with Azure Arc

## Architecture Overview
- **k3s Cluster**: v1.33.5 on 192.168.1.46 with NVIDIA RTX 5080 GPU
- **Azure Arc**: ROG-AI cluster (Foundry-Arc resource group, eastus2)
- **Flux**: v1.17.3 (microsoft.flux extension)
- **Container Registry**: foundryoci.azurecr.io (public, anonymous pull enabled)
- **Git Repository**: github.com/likamrat/fl-arc-gitops

## Optimized Sync Intervals
All intervals reduced from minutes to seconds for maximum responsiveness:

- **GitRepository sync**: 30s (Git → Cluster)
- **Kustomization infrastructure**: 30s sync, 30s retry
- **Kustomization apps**: 30s sync, 30s retry  
- **ImageRepository scan**: 10s (Registry monitoring)
- **ImageUpdateAutomation**: 30s (Git update automation)

## GitOps Flow (Manual Update)
1. **Push OCI Artifact**: `oras push foundryoci.azurecr.io/foundry-local-olive-models:vX.Y.Z`
2. **ImageRepository Detection**: Within 10 seconds
3. **ImagePolicy Selection**: Automatic (semver >=0.1.0)
4. **Manual Git Update**: Update `apps/foundry-gpu-oras/helmrelease.yaml` with new tag
5. **Git Push**: Commit and push to main branch
6. **Flux Sync**: Within 30 seconds
7. **Helm Upgrade**: Automatic via HelmRelease
8. **Pod Restart**: With Recreate strategy (no GPU deadlock)

## Deployments Validated
✅ **v0.1.0** - Initial deployment via GitOps  
✅ **v0.2.0** - First upgrade test (manual pod deletion needed due to RollingUpdate)  
✅ **v0.3.0** - Second upgrade test (Recreate strategy in chart, applied on next upgrade)

## Key Components
- **HelmRelease**: `foundry-gpu-oras` in foundry-system namespace
- **Chart**: Local chart at `./apps/foundry-gpu-oras/chart`
- **Deployment Strategy**: Recreate (prevents GPU resource conflicts)
- **Model Storage**: `apps/foundry-gpu-oras/models/` (gitignored, 702MB)

## Future Enhancements
To enable **fully automated** Git updates (no manual commits):
1. Create GitHub Personal Access Token (PAT) with repo write access
2. Create Kubernetes secret with PAT
3. Update GitRepository to use PAT for push access
4. ImageUpdateAutomation will then auto-commit tag updates

## Testing Commands
```bash
# Push new model version
cd /home/lior/repos/fl-arc-gitops/apps/foundry-gpu-oras/models
oras push foundryoci.azurecr.io/foundry-local-olive-models:vX.Y.Z \
  --artifact-type "foundry/models" \
  models.tar.gz:application/gzip

# Monitor ImageRepository
kubectl get imagerepository,imagepolicy -n flux-system -w

# Update Git (manual)
cd /home/lior/repos/fl-arc-gitops
# Edit apps/foundry-gpu-oras/helmrelease.yaml (update byo.tag)
git add apps/foundry-gpu-oras/helmrelease.yaml
git commit -m "Update Foundry Local model to vX.Y.Z"
git push origin main

# Monitor deployment
kubectl get gitrepository,kustomization,helmrelease,pods -n foundry-system -w
```

## Demo Success Criteria
✅ OCI artifact push triggers GitOps flow  
✅ Model version updates automatically detected  
✅ Helm upgrades pods with new model version  
✅ No crashing pods (GPU deadlock resolved)  
✅ Fast sync times (30s intervals)  
✅ End-to-end flow validated (v0.1.0 → v0.2.0 → v0.3.0)
