# Foundry Local GitOps Demo with Azure Arc

This repository demonstrates **OCI artifact-triggered GitOps** for deploying Foundry Local AI inference service on Azure Arc-enabled Kubernetes with GPU support.

## 🎯 Demo Overview

**Scenario**: Automatically deploy new AI models to GPU cluster when optimized models are pushed to Azure Container Registry.

**GitOps Flow**:
```
Optimize Model → Push to ACR → Flux Detects → Git Update → Cluster Reconcile → Pod Restart with New Model
```

**Key Technologies**:
- **Azure Arc-enabled Kubernetes** - k3s cluster with NVIDIA RTX 5080 GPU
- **Flux v2** - GitOps with image automation controllers
- **Foundry Local** - AI inference service with OpenAI-compatible API
- **ORAS** - OCI Registry As Storage for BYO (Bring Your Own) models
- **Helm** - Kubernetes package manager

---

## 📂 Repository Structure

```
fl-arc-gitops/
├── scripts/
│   ├── arc-k8s.sh                 # Azure Arc cluster connection
│   ├── gpu-operator-install.sh    # NVIDIA GPU Operator setup
│   ├── gpu-test.sh                # GPU verification tests
│   ├── oras-login.sh              # ORAS authentication to ACR
│   └── flux-setup.sh              # Flux v2 installation & configuration
├── flux-system/                   # (To be created) Flux configuration
│   ├── gotk-components.yaml
│   └── gotk-sync.yaml
├── infrastructure/                # (To be created) Base resources
│   └── namespace.yaml
├── apps/                          # (To be created) Application deployments
│   ├── foundry-gpu-oras/
│   │   ├── kustomization.yaml
│   │   ├── helmrelease.yaml
│   │   └── values.yaml
│   └── image-automation/
│       ├── imagerepository.yaml
│       ├── imagepolicy.yaml
│       └── imageupdateautomation.yaml
├── GPU_OPERATOR_INSTALLATION.md   # GPU setup documentation
├── gpu-test-manifests.yaml        # GPU test workloads
└── README.md                      # This file
```

---

## 🚀 Quick Start

### Prerequisites

✅ **Already Configured**:
- Azure Arc-enabled k3s cluster (`ROG-AI`)
- NVIDIA GPU Operator installed and working
- Docker logged into `foundryoci.azurecr.io`

### Setup Steps

#### 1. **ORAS Login** (Authenticate to ACR for model push)
```bash
./scripts/oras-login.sh
```

#### 2. **Install Flux v2** (GitOps controllers)
```bash
./scripts/flux-setup.sh
```

This installs:
- ✓ Source Controller (Git sync)
- ✓ Kustomize Controller (manifest processing)
- ✓ Helm Controller (Helm releases)
- ✓ Notification Controller (events)
- ✓ **Image Reflector Controller** (OCI artifact scanning)
- ✓ **Image Automation Controller** (Git auto-update)

#### 3. **Verify Installation**
```bash
kubectl get pods -n flux-system
kubectl get crds | grep flux
```

---

## 🎪 Demo Workflow

### Phase 1: Initial Deployment

1. **Create Flux Configuration** (Git source)
2. **Deploy Infrastructure** (namespaces, RBAC)
3. **Deploy Foundry GPU-ORAS** (initial model v1.0.0)
4. **Set up Image Automation** (watch ACR for new models)

### Phase 2: Trigger Update

1. **Optimize New Model** with Microsoft Olive
2. **Push to ACR** with ORAS (`v1.1.0`)
3. **Flux Detects** new artifact (Image Reflector)
4. **Git Auto-Update** (Image Automation commits change)
5. **Cluster Reconciles** (Flux syncs from Git)
6. **Pod Restarts** with new model

**Timeline**: ~2-3 minutes from push to deployment 🚀

---

## 🛠️ Scripts Reference

### `oras-login.sh`
**Purpose**: Authenticate ORAS CLI to Azure Container Registry

**Usage**:
```bash
./scripts/oras-login.sh
```

**What it does**:
- Extracts Docker credentials from `~/.docker/config.json`
- Logs into ACR using ORAS CLI
- Verifies access to repositories

**Output**:
- ✓ Successful authentication to `foundryoci.azurecr.io`
- Lists available repositories

---

### `flux-setup.sh`
**Purpose**: Install and configure Flux v2 GitOps on Azure Arc cluster

**Usage**:
```bash
./scripts/flux-setup.sh
```

**What it does**:
1. Verifies prerequisites (Azure CLI, kubectl, cluster access)
2. Installs Azure CLI extensions (`k8s-configuration`, `k8s-extension`)
3. Registers Azure resource providers
4. Installs Flux v2 extension with image automation
5. Verifies all Flux controllers are running

**Configuration**:
```bash
RESOURCE_GROUP="Foundry-Arc"
CLUSTER_NAME="ROG-AI"
CLUSTER_TYPE="connectedClusters"
FLUX_NAMESPACE="flux-system"
```

**Output**:
- ✓ Flux controllers running in `flux-system` namespace
- ✓ Image automation enabled
- ✓ Ready for GitOps configurations

---

## 🔧 System Information

### Cluster Details
- **Cluster Name**: `ROG-AI`
- **Type**: Azure Arc-enabled Kubernetes (k3s v1.33.5)
- **Resource Group**: `Foundry-Arc`
- **Runtime**: containerd

### GPU Configuration
- **GPU**: NVIDIA GeForce RTX 5080 Laptop GPU
- **Driver**: 570.172.08
- **CUDA**: 12.8
- **Compute Capability**: 12.0
- **Operator**: v25.3.4

### Container Registry
- **Registry**: `foundryoci.azurecr.io`
- **Type**: Private (authenticated)
- **BYO Models Repo**: `foundry-local-olive-models`

---

## 📚 Key Concepts

### **Image Reflector Controller**
- Scans ACR for new OCI artifacts every 1 minute
- Tracks semantic versions or specific tag patterns
- Stores metadata about available images

### **Image Automation Controller**
- Monitors Image Policies for changes
- Auto-updates Git repository when new artifacts detected
- Creates commits with updated model references
- Triggers Flux reconciliation

### **Kustomizations**
- Define what to deploy from Git
- Support dependencies (`dependsOn`)
- Enable pruning (cleanup on delete)

---

## 🎯 Next Steps

After running the setup scripts:

1. **Create Git Source**:
   ```bash
   az k8s-configuration flux create \
     -g Foundry-Arc \
     -c ROG-AI \
     -n foundry-gitops \
     --namespace flux-system \
     -t connectedClusters \
     --scope cluster \
     -u https://github.com/likamrat/fl-arc-gitops \
     --branch main \
     --kustomization name=infra path=./infrastructure prune=true \
     --kustomization name=apps path=./apps/foundry-gpu-oras prune=true dependsOn=["infra"]
   ```

2. **Create Image Automation Resources** (see `apps/image-automation/`)

3. **Deploy Foundry** (see `apps/foundry-gpu-oras/`)

4. **Test Model Update**:
   ```bash
   # Push new model to ACR
   cd /path/to/foundry-local-k8s/byo-model/oras-local
   ./push.sh
   
   # Watch Flux detect and deploy
   kubectl logs -n flux-system -l app=image-reflector-controller -f
   ```

---

## 📖 Documentation

- [Flux v2 Documentation](https://fluxcd.io/docs/)
- [Azure Arc Kubernetes GitOps](https://learn.microsoft.com/azure/azure-arc/kubernetes/tutorial-use-gitops-flux2)
- [Foundry Local Helm Guide](../foundry-local-k8s/docs/HELM_README.md)
- [ORAS Documentation](https://oras.land/)

---

## 🐛 Troubleshooting

### Check Flux Status
```bash
kubectl get pods -n flux-system
kubectl get gitrepositories -A
kubectl get kustomizations -A
kubectl get helmreleases -A
```

### Check Image Automation
```bash
kubectl get imagerepositories -A
kubectl get imagepolicies -A
kubectl get imageupdateautomations -A
```

### View Logs
```bash
kubectl logs -n flux-system -l app=source-controller -f
kubectl logs -n flux-system -l app=image-reflector-controller -f
kubectl logs -n flux-system -l app=image-automation-controller -f
```

### Common Issues

**Flux pods not starting**:
```bash
kubectl describe pod -n flux-system <pod-name>
kubectl get events -n flux-system --sort-by='.lastTimestamp'
```

**Image automation not working**:
```bash
# Check ImageRepository
kubectl describe imagerepository -n flux-system <name>

# Check ImagePolicy
kubectl describe imagepolicy -n flux-system <name>
```

---

## 📝 License

This is a demonstration repository for Azure Arc and Foundry Local GitOps patterns.

---

## 🤝 Contributing

This is a demo repository. For issues or questions about:
- **Foundry Local**: See the [foundry-local-k8s](https://github.com/microsoft/foundry-local-k8s) repository
- **Azure Arc**: See [Azure Arc documentation](https://learn.microsoft.com/azure/azure-arc/)
- **Flux**: See [Flux documentation](https://fluxcd.io/)
