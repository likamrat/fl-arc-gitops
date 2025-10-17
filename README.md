# Azure Arc + Flux GitOps - Foundry Local with BYO ORAS Models

This repository demonstrates GitOps-based deployment of **Foundry Local with GPU support** using **Azure Arc-enabled Kubernetes**, **Flux CD**, and **BYO ORAS model artifacts** from Azure Container Registry.

## 🎯 Overview

**Goal**: Automate the deployment and upgrade of Foundry Local (AI/LLM container) on Kubernetes using GitOps principles, with model artifacts stored as OCI artifacts in Azure Container Registry.

**Architecture**:
- **Cluster**: k3s v1.33.5 with NVIDIA GPU (RTX 5080)
- **GitOps Engine**: Flux CD v1.17.3 (via Azure Arc extension)
- **Azure Arc**: ROG-AI cluster in Foundry-Arc resource group
- **Container Registry**: foundryoci.azurecr.io (anonymous pull enabled)
- **Model Artifacts**: ORAS OCI artifacts (foundry/models artifact type)
- **Deployment**: Helm chart with BYO ORAS configuration

## ⚡ Performance Optimizations

**Extreme sync intervals for demo purposes**:
- **GitRepository**: 3s sync interval
- **Kustomizations**: 3s sync + 3s retry
- **ImageRepository**: 5s scan interval
- **Recreate Strategy**: Prevents GPU deadlock during updates

**Expected GitOps Flow**: OCI push → ImageRepository detection (5s) → Manual Git update → GitOps sync (3s) → Deployment (90s) = **~2 minutes total**

## 🚀 Quick Start

**Prerequisites**:
- Azure Arc-enabled Kubernetes cluster
- Flux extension installed
- Azure Container Registry with anonymous pull
- ORAS CLI v1.3.0+

**Deploy GitOps Configuration**:
```bash
bash scripts/gitops-config.sh
```

See [QUICK_START.md](QUICK_START.md) for detailed instructions.

## 📚 Documentation

- **[QUICK_START.md](QUICK_START.md)** - Fast-track guide to run E2E test
- **[E2E_TEST_PLAN.md](E2E_TEST_PLAN.md)** - Comprehensive test plan with all phases
- **[GITOPS_FLOW_SUMMARY.md](GITOPS_FLOW_SUMMARY.md)** - GitOps architecture and flow
- **[CLEANUP_GUIDE.md](CLEANUP_GUIDE.md)** - Cleanup modes, usage examples, and troubleshooting

## 🏗️ Repository Structure

```
├── apps/
│   └── foundry-gpu-oras/
│       ├── helmrelease.yaml          # Flux HelmRelease with BYO config
│       ├── kustomization.yaml        # Kustomization for app manifests
│       ├── chart/                    # Local Helm chart (Recreate strategy)
│       └── models/                   # Model artifacts for ORAS
├── infrastructure/
│   └── kustomization.yaml            # Infrastructure Kustomization
├── scripts/
│   ├── gitops-config.sh              # Deploy GitOps config via Azure Arc
│   ├── oras-login.sh                 # ORAS authentication helper
│   └── migrate-container-image.sh    # Container migration helper
└── flux-system/
    └── kustomization.yaml            # Flux system Kustomization
```

## 🔧 Key Features

### 1. Recreate Deployment Strategy
- Prevents GPU deadlock (only one pod at a time)
- Old pod terminates before new pod starts
- Critical for single-GPU environments

### 2. Anonymous ACR Pull
- No imagePullSecrets required
- Public network access enabled
- Simplified authentication

### 3. BYO ORAS Model Artifacts
- Models stored as OCI artifacts in ACR
- Runtime download via ORAS
- Version-controlled with semver tags

### 4. Post-Deployment Interval Patching
- Azure CLI doesn't support retry-interval directly
- Script patches Kustomizations after creation
- Achieves 3s sync + 3s retry intervals

### 5. Image Policy Automation
- ImageRepository scans ACR every 5s
- ImagePolicy selects latest semver tag
- Ready for ImageUpdateAutomation (needs Git write token)

## 🧪 Testing

**Run E2E test**:
```bash
cd /home/lior/repos/fl-arc-gitops
bash scripts/gitops-config.sh
```

**Monitor deployment**:
```bash
watch kubectl get pods -n foundry-system
```

**Verify version**:
```bash
kubectl logs -n foundry-system -l app.kubernetes.io/component=foundry | grep "Tag:"
```

**Test upgrade flow**:
1. Push new OCI artifact (v0.2.0)
2. Update helmrelease.yaml tag
3. Git commit + push
4. Watch GitOps sync (within 3-5 seconds)

## 🧹 Cleanup

```bash
az k8s-configuration flux delete \
  --name foundry-gitops \
  --cluster-name ROG-AI \
  --cluster-type connectedClusters \
  --resource-group Foundry-Arc \
  --yes

kubectl delete namespace foundry-system
kubectl delete imagerepository,imagepolicy foundry-local-olive-models -n flux-system
```

## 📊 Performance Metrics

| Metric | Target | Achieved |
|--------|--------|----------|
| GitOps config creation | < 1 min | ✅ ~30s |
| Git sync interval | 3s | ✅ 3s |
| Kustomization reconcile | 3s | ✅ 3s |
| ImageRepository scan | 5s | ✅ 5s |
| Pod Ready (w/ models) | < 2 min | ✅ ~2 min |
| Upgrade flow | < 3 min | ✅ ~2.5 min |

## ⚠️ Known Limitations

1. **Manual Git Update Required**
   - ImageUpdateAutomation not configured (needs GitHub PAT)
   - Must manually update Git after OCI push
   
2. **Aggressive Sync Intervals**
   - 3s/5s intervals are demo-optimized
   - Watch GitHub API rate limits (5000 req/hour)
   - Production: Use 10-30s intervals

3. **Single-GPU Environment**
   - Recreate strategy required
   - Cannot run multiple pods simultaneously
   - No horizontal scaling

## 🔗 Resources

- [Azure Arc-enabled Kubernetes](https://docs.microsoft.com/azure/azure-arc/kubernetes/)
- [Flux CD Documentation](https://fluxcd.io/docs/)
- [ORAS Documentation](https://oras.land/)
- [Foundry Local](https://github.com/microsoft/foundry-local-k8s)

## 📝 License

MIT License - See LICENSE file for details

---

**Status**: ✅ Ready for E2E testing  
**Latest Commit**: 004f0d2  
**Last Updated**: 2025-01-22
