# Azure Arc + Flux GitOps - Foundry Local with GPU-Accelerated BYO ORAS Models

This repository demonstrates GitOps-based deployment of **Foundry Local with GPU acceleration** using **Azure Arc-enabled Kubernetes**, **Flux CD**, and **CUDA-optimized BYO ORAS model artifacts** from Azure Container Registry.

## 🎯 Overview

**Goal**: Automate the deployment and upgrade of Foundry Local (AI/LLM container) on Kubernetes using GitOps principles, with GPU-accelerated model artifacts stored as OCI artifacts in Azure Container Registry.

**Architecture**:
- **Cluster**: k3s v1.33.5 with NVIDIA GPU (RTX 5080 16GB, CUDA 13.0)
- **GitOps Engine**: Flux CD v1.17.3 (via Azure Arc extension)
- **Azure Arc**: ROG-FL cluster in Foundry-Arc resource group
- **Container Registry**: foundryoci.azurecr.io (anonymous pull enabled)
- **Model Artifacts**: ORAS OCI artifacts (foundry/models artifact type)
- **Deployment**: Helm chart with BYO ORAS configuration
- **GPU Models**: CUDA-optimized ONNX Runtime GenAI format (int4 quantized)

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
bash scripts/setup/gitops-config.sh
```

## 📚 Documentation

- **[DEMO_FLOW.md](docs/DEMO_FLOW.md)** - Step-by-step demo workflow (v1.0.0 → v2.0.0)
- **[DEMO_TALK_TRACK.md](docs/DEMO_TALK_TRACK.md)** - Complete demo presentation script with talking points
- **[GITOPS_FLOW_SUMMARY.md](docs/GITOPS_FLOW_SUMMARY.md)** - GitOps architecture and flow
- **[CLEANUP_GUIDE.md](docs/CLEANUP_GUIDE.md)** - Cleanup modes, usage examples, and troubleshooting
- **[GPU_OPERATOR_INSTALLATION.md](docs/GPU_OPERATOR_INSTALLATION.md)** - GPU operator setup guide

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
│   ├── setup/                        # Setup and installation scripts
│   │   ├── gitops-config.sh          # Deploy GitOps config via Azure Arc
│   │   ├── flux-setup.sh             # Flux CD setup helper
│   │   └── gpu-operator-install.sh   # GPU operator installation
│   ├── demo/                         # Demo and cleanup scripts
│   │   ├── demo-cleanup.sh           # Environment cleanup (full/soft modes)
│   │   └── cleanup-openwebui-chats.sh # Open WebUI chat history cleanup
│   ├── utils/                        # Utility scripts
│   │   ├── oras-login.sh             # ORAS authentication helper
│   │   ├── gpu-test.sh               # GPU testing utilities
│   │   ├── fix-file-descriptors.sh   # Local file descriptor fixes
│   │   └── fix-remote-file-descriptors.sh  # Remote file descriptor fixes
│   └── migration/                    # Migration scripts
│       ├── migrate-container-image.sh    # Container migration helper
│       └── migrate-model-artifact.sh     # Model artifact migration helper
├── docs/                             # Documentation
│   ├── DEMO_FLOW.md                  # Step-by-step demo workflow
│   ├── GITOPS_FLOW_SUMMARY.md        # GitOps architecture and flow
│   ├── CLEANUP_GUIDE.md              # Cleanup procedures
│   └── GPU_OPERATOR_INSTALLATION.md  # GPU operator setup guide
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

### 3. GPU-Accelerated BYO ORAS Model Artifacts
- CUDA-optimized ONNX Runtime GenAI models
- Models stored as OCI artifacts in ACR with hierarchical structure
- Runtime download via ORAS from `byo-models-gpu/{model-name}:{version}`
- Version-controlled with semver tags (v1.0.0, v2.0.0)
- Example: Llama 3.2 1B int4 quantized from onnx-community
- CUDAExecutionProvider with int4 quantization for optimal GPU performance

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
bash scripts/setup/gitops-config.sh
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

1. Push new OCI artifact (v2.0.0) to `byo-models-gpu/llama-3.2-1b-cuda:v2.0.0`
2. Update helmrelease.yaml tag (v1.0.0 → v2.0.0)
3. Git commit + push
4. Watch GitOps sync (within 3-5 seconds)
5. Verify GPU model deployment with CUDA acceleration

See [DEMO_FLOW.md](docs/DEMO_FLOW.md) for detailed step-by-step demo instructions.

## 🧹 Cleanup

```bash
# Full cleanup (removes all GitOps resources)
bash scripts/demo/demo-cleanup.sh --full

# Soft cleanup (GitOps-based rollback to v1.0.0)
bash scripts/demo/demo-cleanup.sh --soft
```

See [CLEANUP_GUIDE.md](docs/CLEANUP_GUIDE.md) for detailed cleanup options and usage examples.

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

**Status**: ✅ GPU-accelerated model deployment ready  
**Current Model**: Llama 3.2 1B CUDA (int4 quantized, v1.0.0/v2.0.0)  
**Last Updated**: October 18, 2025
