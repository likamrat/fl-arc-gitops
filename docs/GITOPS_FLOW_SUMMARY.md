# GitOps Flow Summary - GPU-Accelerated Foundry Local with Azure Arc

## Architecture Overview

- **k3s Cluster**: v1.33.5 on 192.168.1.46 (ROG-AI)
- **GPU**: NVIDIA RTX 5080 (16GB VRAM, CUDA 13.0, driver 581.57)
- **Azure Arc**: ROG-AI cluster (Foundry-Arc resource group, eastus2)
- **Flux**: v1.17.3 (microsoft.flux extension)
- **Container Registry**: foundryoci.azurecr.io (public, anonymous pull enabled)
- **Git Repository**: github.com/likamrat/fl-arc-gitops
- **Model Repository**: byo-models-gpu/llama-3.2-1b-cuda (hierarchical structure)
- **Model**: CUDA-optimized Llama 3.2 1B (int4 quantized, ~1GB, from onnx-community)

## Optimized Sync Intervals

All intervals reduced from minutes to seconds for maximum responsiveness:

- **GitRepository sync**: 30s (Git → Cluster)
- **Kustomization infrastructure**: 30s sync, 30s retry
- **Kustomization apps**: 30s sync, 30s retry  
- **ImageRepository scan**: 5s (Registry monitoring, updated for GPU models)
- **ImageUpdateAutomation**: 30s (Manual Git updates currently)

## GitOps Flow (Manual Update)

1. **Push OCI Artifact**: `oras push foundryoci.azurecr.io/byo-models-gpu/llama-3.2-1b-cuda:vX.Y.Z`
2. **ImageRepository Detection**: Within 5 seconds
3. **ImagePolicy Selection**: Automatic (semver >=1.0.0)
4. **Manual Git Update**: Update `apps/foundry-gpu-oras/helmrelease.yaml` with new tag
5. **Git Push**: Commit and push to main branch
6. **Flux Sync**: Within 30 seconds
7. **Helm Upgrade**: Automatic via HelmRelease
8. **Pod Restart**: With Recreate strategy (prevents GPU resource conflicts)

## Deployments Validated

✅ **v1.0.0** - GPU-optimized baseline deployment (CUDA-enabled Llama 3.2 1B)  
✅ **v2.0.0** - First GPU model upgrade test (validated end-to-end GitOps flow)

**Note**: Previous CPU-only versions (v0.1.0-v0.3.0) deprecated in favor of GPU-optimized models.

## Key Components

- **HelmRelease**: `foundry-gpu-oras` in foundry-system namespace
- **Chart**: Local chart at `./apps/foundry-gpu-oras/chart`
- **Deployment Strategy**: Recreate (prevents GPU resource conflicts)
- **Model Storage**: `apps/foundry-gpu-oras/models/` (gitignored, ~1GB compressed)
- **Model Format**: ONNX Runtime GenAI with CUDA provider
- **GPU Support**: CUDAExecutionProvider enabled at model compile-time

## Future Enhancements

To enable **fully automated** Git updates (no manual commits):

1. Create GitHub Personal Access Token (PAT) with repo write access
2. Create Kubernetes secret with PAT
3. Update GitRepository to use PAT for push access
4. ImageUpdateAutomation will then auto-commit tag updates

## Testing Commands

```bash
# Push new GPU model version
cd /home/lior/repos/fl-arc-gitops/apps/foundry-gpu-oras/models
oras push foundryoci.azurecr.io/byo-models-gpu/llama-3.2-1b-cuda:vX.Y.Z \
  --artifact-type "foundry/models" \
  models.tar.gz:application/gzip

# Monitor ImageRepository
kubectl get imagerepository,imagepolicy -n flux-system -w

# Update Git (manual)
cd /home/lior/repos/fl-arc-gitops
# Edit apps/foundry-gpu-oras/helmrelease.yaml (update byo.tag to vX.Y.Z)
git add apps/foundry-gpu-oras/helmrelease.yaml
git commit -m "Update Foundry Local GPU model to vX.Y.Z"
git push origin main

# Monitor deployment
kubectl get gitrepository,kustomization,helmrelease,pods -n foundry-system -w

# Verify GPU model loaded
kubectl logs -n foundry-system -l app.kubernetes.io/component=foundry | grep -E "Tag:|CUDAExecutionProvider"
```

## Demo Success Criteria

✅ OCI artifact push triggers GitOps flow  
✅ Model version updates automatically detected (5s scan interval)  
✅ Helm upgrades pods with new GPU model version  
✅ GPU acceleration confirmed (CUDAExecutionProvider)  
✅ No crashing pods (GPU resource conflicts resolved)  
✅ Fast sync times (5-30s intervals)  
✅ End-to-end flow validated (v1.0.0 → v2.0.0)
✅ Hierarchical ACR structure supports multiple model variants

## Related Documentation

- **[README.md](../README.md)** - Main repository overview and quick start
- **[DEMO_FLOW.md](./DEMO_FLOW.md)** - Step-by-step demo workflow (v1.0.0 → v2.0.0)
- **[CLEANUP_GUIDE.md](./CLEANUP_GUIDE.md)** - Environment cleanup and reset procedures
- **[GPU_OPERATOR_INSTALLATION.md](./GPU_OPERATOR_INSTALLATION.md)** - GPU operator setup guide

---

**Version**: v2.0.0  
**Last Updated**: October 18, 2025  
**Status**: GPU-accelerated models with hierarchical ACR structure
