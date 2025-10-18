#!/bin/bash

################################################################################
# Demo Cleanup Script
# 
# This script performs a cleanup after a GitOps demo, preparing the cluster
# for the next demo run while preserving certain infrastructure components.
#
# MODES:
#
# FULL CLEANUP (default):
# - Deletes Flux GitOps configuration from Arc cluster
# - Removes Foundry Local application resources (Helm chart, pods, etc.)
# - Deletes foundry-system namespace
# - Removes ALL OCI artifacts from ACR EXCEPT v0.1.0 (keeps baseline for next demo)
# - Reverts Git repository code to v0.1.0
# - Commits and pushes changes to Git
# - Verifies Flux system controllers remain healthy
# - Shows final state comparison
#
# SOFT CLEANUP (--soft):
# - Removes ALL OCI artifacts from ACR EXCEPT v0.1.0
# - Reverts Git repository code to v0.1.0
# - Commits and pushes changes to Git
# - Waits for GitOps to sync and rollback deployment
# - Validates resources on cluster (HelmRelease, pods, version)
# - PRESERVES Flux GitOps configuration and namespace
#
# What this script DOES NOT do:
# - Delete cached container images (preserves for faster next demo)
# - Remove ImageRepository/ImagePolicy (infrastructure components, reused in next demo)
# - Delete Flux system namespace or controllers
# - Touch GPU operator or other cluster infrastructure
#
# Prerequisites:
# - Azure CLI logged in with access to Arc cluster
# - kubectl configured for the cluster
# - ORAS CLI installed and logged in to ACR
# - Git repository clean (no uncommitted changes)
#
# Usage:
#   ./scripts/demo-cleanup.sh                    # Full cleanup
#   ./scripts/demo-cleanup.sh --soft             # Soft cleanup (GitOps rollback)
#   ./scripts/demo-cleanup.sh --dry-run          # Full cleanup dry run
# Usage:
#   ./scripts/demo/demo-cleanup.sh --full             # Full cleanup
#   ./scripts/demo/demo-cleanup.sh --soft             # Soft cleanup (GitOps rollback)
#   ./scripts/demo/demo-cleanup.sh --full --dry-run   # Full cleanup dry run
#   ./scripts/demo/demo-cleanup.sh --soft --dry-run   # Soft cleanup dry run
################################################################################

set -e

# Parse command line arguments
DRY_RUN=false
SOFT_MODE=false
FULL_MODE=false

for arg in "$@"; do
  case $arg in
    --dry-run|-n)
      DRY_RUN=true
      shift
      ;;
    --soft|-s)
      SOFT_MODE=true
      shift
      ;;
    --full|-f)
      FULL_MODE=true
      shift
      ;;
    *)
      # Unknown option
      ;;
  esac
done

# Validate: must specify either --soft or --full
if [[ "${SOFT_MODE}" == "false" && "${FULL_MODE}" == "false" ]]; then
  echo -e "${RED}Error: Must specify either --full or --soft mode${NC}"
  echo ""
  echo "Usage:"
  echo "  $0 --full [--dry-run]   # Full cleanup (removes Flux config, namespace, all artifacts except v1.0.0)"
  echo "  $0 --soft [--dry-run]   # Soft cleanup (GitOps rollback, keeps Flux config and namespace)"
  echo ""
  exit 1
fi

# Validate: can't use both --soft and --full
if [[ "${SOFT_MODE}" == "true" && "${FULL_MODE}" == "true" ]]; then
  echo -e "${RED}Error: Cannot use both --soft and --full flags${NC}"
  exit 1
fi

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
CLUSTER_NAME="ROG-AI"
RESOURCE_GROUP="Foundry-Arc"
CONFIG_NAME="foundry-gitops"
NAMESPACE="foundry-system"
REGISTRY="foundryoci.azurecr.io"
REPO_NAME="byo-models-gpu/llama-3.2-1b-cuda"
VERSION_TO_REVERT="v1.0.0"

echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
if [[ "${DRY_RUN}" == "true" ]]; then
  if [[ "${SOFT_MODE}" == "true" ]]; then
    echo -e "${BLUE}║      Demo Cleanup Script - SOFT MODE (DRY RUN)           ║${NC}"
  elif [[ "${FULL_MODE}" == "true" ]]; then
    echo -e "${BLUE}║      Demo Cleanup Script - FULL MODE (DRY RUN)           ║${NC}"
  fi
else
  if [[ "${SOFT_MODE}" == "true" ]]; then
    echo -e "${BLUE}║      Demo Cleanup Script - SOFT MODE                     ║${NC}"
  elif [[ "${FULL_MODE}" == "true" ]]; then
    echo -e "${BLUE}║      Demo Cleanup Script - FULL MODE                     ║${NC}"
  fi
fi
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

if [[ "${SOFT_MODE}" == "true" ]]; then
  echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
  echo -e "${CYAN}SOFT MODE: GitOps-based rollback to ${VERSION_TO_REVERT}${NC}"
  echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
  echo ""
  echo -e "${YELLOW}This will:${NC}"
  echo "  • Remove OCI artifacts EXCEPT ${VERSION_TO_REVERT}"
  echo "  • Revert Git code to ${VERSION_TO_REVERT}"
  echo "  • Let GitOps rollback the deployment naturally"
  echo "  • Validate the rollback succeeded"
  echo ""
  echo -e "${YELLOW}This will NOT:${NC}"
  echo "  • Delete Flux GitOps configuration"
  echo "  • Delete foundry-system namespace"
  echo "  • Manually remove any cluster resources"
  echo ""
fi

if [[ "${DRY_RUN}" == "true" ]]; then
  echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
  echo -e "${YELLOW}DRY RUN MODE: No changes will be made${NC}"
  echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
  echo ""
fi

# Show current state
echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}CURRENT STATE (Before Cleanup)${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
echo ""

echo -e "${BLUE}Flux Configuration:${NC}"
az k8s-configuration flux list \
  --cluster-name ${CLUSTER_NAME} \
  --cluster-type connectedClusters \
  --resource-group ${RESOURCE_GROUP} \
  -o table 2>/dev/null || echo "No Flux configurations found"
echo ""

echo -e "${BLUE}Foundry Resources:${NC}"
kubectl get all -n ${NAMESPACE} 2>/dev/null || echo "No resources in ${NAMESPACE}"
echo ""

echo -e "${BLUE}Current Git Version:${NC}"
CURRENT_TAG=$(yq eval '.spec.values.foundry.byo.tag' apps/foundry-gpu-oras/helmrelease.yaml 2>/dev/null || grep -A 5 "byo:" apps/foundry-gpu-oras/helmrelease.yaml | grep "tag:" | awk '{print $2}' | head -1)
echo "  HelmRelease tag: ${CURRENT_TAG}"
echo ""

echo -e "${BLUE}OCI Artifacts in Registry:${NC}"
oras repo tags ${REGISTRY}/${REPO_NAME} 2>/dev/null || echo "Cannot list tags (may need authentication)"
echo ""

if [[ "${DRY_RUN}" == "false" ]]; then
  read -p "$(echo -e ${YELLOW}Press ENTER to proceed with cleanup or Ctrl+C to cancel...${NC})"
  echo ""
fi

################################################################################
# SOFT MODE: GitOps-based Rollback
################################################################################
if [[ "${SOFT_MODE}" == "true" ]]; then
  
  # Step 1: Remove all OCI artifacts except v0.1.0
  echo -e "${BLUE}Step 1: Removing OCI artifacts (keeping only ${VERSION_TO_REVERT})...${NC}"
  
  TAGS=$(oras repo tags ${REGISTRY}/${REPO_NAME} 2>/dev/null || echo "")
  
  if [[ -z "${TAGS}" ]]; then
    echo -e "${YELLOW}⚠ Could not list tags (may need authentication or repo doesn't exist)${NC}"
  else
    DELETED_COUNT=0
    for TAG in ${TAGS}; do
      if [[ "${TAG}" != "${VERSION_TO_REVERT}" ]]; then
        if [[ "${DRY_RUN}" == "true" ]]; then
          echo -e "  ${YELLOW}[DRY RUN]${NC} Would delete ${TAG}"
          DELETED_COUNT=$((DELETED_COUNT + 1))
        else
          echo "  Deleting ${TAG}..."
          if oras manifest delete ${REGISTRY}/${REPO_NAME}:${TAG} 2>/dev/null; then
            echo -e "  ${GREEN}✓${NC} Deleted ${TAG}"
            DELETED_COUNT=$((DELETED_COUNT + 1))
          else
            echo -e "  ${YELLOW}⚠${NC} Could not delete ${TAG}"
          fi
        fi
      fi
    done
    
    if [[ ${DELETED_COUNT} -eq 0 ]]; then
      echo -e "${GREEN}✓ No artifacts to delete (only ${VERSION_TO_REVERT} exists)${NC}"
    else
      if [[ "${DRY_RUN}" == "true" ]]; then
        echo -e "${YELLOW}[DRY RUN]${NC} Would delete ${DELETED_COUNT} artifact(s), keep ${VERSION_TO_REVERT}"
      else
        echo -e "${GREEN}✓ Deleted ${DELETED_COUNT} artifact(s), kept ${VERSION_TO_REVERT}${NC}"
      fi
    fi
  fi
  echo ""
  
  # Step 2: Revert code to v0.1.0
  echo -e "${BLUE}Step 2: Reverting Git repository to ${VERSION_TO_REVERT}...${NC}"
  
  # Check for uncommitted changes
  if [[ -n $(git status -s) ]]; then
    echo -e "${RED}✗ Uncommitted changes detected in Git repository${NC}"
    if [[ "${DRY_RUN}" == "true" ]]; then
      echo -e "${YELLOW}[DRY RUN]${NC} Would exit due to uncommitted changes"
    else
      echo "Please commit or stash your changes before running cleanup."
      exit 1
    fi
  fi
  
  # Update helmrelease.yaml to v0.1.0
  CURRENT_TAG_IN_FILE=$(yq eval '.spec.values.foundry.byo.tag' apps/foundry-gpu-oras/helmrelease.yaml 2>/dev/null || grep -A 5 "byo:" apps/foundry-gpu-oras/helmrelease.yaml | grep "tag:" | awk '{print $2}' | head -1)
  
  if [[ "${CURRENT_TAG_IN_FILE}" != "${VERSION_TO_REVERT}" ]]; then
    if [[ "${DRY_RUN}" == "true" ]]; then
      echo -e "${YELLOW}[DRY RUN]${NC} Would update helmrelease.yaml: ${CURRENT_TAG_IN_FILE} → ${VERSION_TO_REVERT}"
    else
      sed -i "s/tag: ${CURRENT_TAG_IN_FILE}/tag: ${VERSION_TO_REVERT}/" apps/foundry-gpu-oras/helmrelease.yaml
      echo -e "${GREEN}✓ Updated helmrelease.yaml: ${CURRENT_TAG_IN_FILE} → ${VERSION_TO_REVERT}${NC}"
    fi
  else
    echo -e "${YELLOW}⚠ helmrelease.yaml already at ${VERSION_TO_REVERT}${NC}"
  fi
  echo ""
  
  # Step 3: Commit and push changes
  echo -e "${BLUE}Step 3: Committing and pushing changes...${NC}"
  
  if [[ -n $(git status -s) ]]; then
    if [[ "${DRY_RUN}" == "true" ]]; then
      echo -e "${YELLOW}[DRY RUN]${NC} Would commit and push:"
      git status -s | sed 's/^/  /'
    else
      git add apps/foundry-gpu-oras/helmrelease.yaml
      git commit -m "Soft cleanup: Revert Foundry Local model to ${VERSION_TO_REVERT}"
      git push origin main
      echo -e "${GREEN}✓ Changes committed and pushed${NC}"
    fi
  else
    echo -e "${YELLOW}⚠ No changes to commit${NC}"
  fi
  echo ""
  
  # Step 4: Wait for GitOps to sync
  if [[ "${DRY_RUN}" == "false" ]]; then
    echo -e "${BLUE}Step 4: Waiting for GitOps to sync and rollback...${NC}"
    echo "  This may take up to 2 minutes (Git sync + model download + pod restart)"
    echo ""
    
    # Wait for GitRepository to sync
    echo "  Waiting for GitRepository to sync new commit..."
    TIMEOUT=60
    ELAPSED=0
    while [[ ${ELAPSED} -lt ${TIMEOUT} ]]; do
      if kubectl get gitrepository foundry-gitops -n ${NAMESPACE} -o jsonpath='{.status.artifact.revision}' 2>/dev/null | grep -q "$(git rev-parse HEAD)"; then
        echo -e "  ${GREEN}✓${NC} GitRepository synced to latest commit"
        break
      fi
      sleep 3
      ELAPSED=$((ELAPSED + 3))
      echo -n "."
    done
    echo ""
    
    if [[ ${ELAPSED} -ge ${TIMEOUT} ]]; then
      echo -e "  ${YELLOW}⚠${NC} GitRepository sync timeout (but may still be in progress)"
    fi
    
    # Wait for HelmRelease to reconcile
    echo "  Waiting for HelmRelease to reconcile..."
    sleep 10  # Give Flux time to start the reconciliation
    TIMEOUT=120
    ELAPSED=0
    while [[ ${ELAPSED} -lt ${TIMEOUT} ]]; do
      HELM_READY=$(kubectl get helmrelease foundry-gpu-oras -n ${NAMESPACE} -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
      if [[ "${HELM_READY}" == "True" ]]; then
        echo -e "  ${GREEN}✓${NC} HelmRelease reconciled successfully"
        break
      fi
      sleep 5
      ELAPSED=$((ELAPSED + 5))
      echo -n "."
    done
    echo ""
    
    if [[ ${ELAPSED} -ge ${TIMEOUT} ]]; then
      echo -e "  ${YELLOW}⚠${NC} HelmRelease reconciliation timeout (but may still be in progress)"
    fi
    
    # Wait for pod to be ready with new version
    echo "  Waiting for pod to be running and ready..."
    TIMEOUT=120
    ELAPSED=0
    while [[ ${ELAPSED} -lt ${TIMEOUT} ]]; do
      POD_STATUS=$(kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/component=foundry -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Unknown")
      POD_READY=$(kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/component=foundry -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
      
      if [[ "${POD_STATUS}" == "Running" ]] && [[ "${POD_READY}" == "True" ]]; then
        echo -e "  ${GREEN}✓${NC} Pod is running and ready"
        break
      fi
      sleep 5
      ELAPSED=$((ELAPSED + 5))
      echo -n "."
    done
    echo ""
    
    if [[ ${ELAPSED} -ge ${TIMEOUT} ]]; then
      echo -e "  ${YELLOW}⚠${NC} Pod readiness timeout (may need manual verification)"
    fi
    
    echo -e "${GREEN}✓ GitOps rollback process completed${NC}"
    echo ""
  else
    echo -e "${YELLOW}[DRY RUN]${NC} Would wait for GitOps to sync and rollback"
    echo ""
  fi
  
  # Step 5: Validate resources on cluster
  echo -e "${BLUE}Step 5: Validating cluster resources...${NC}"
  echo ""
  
  if [[ "${DRY_RUN}" == "false" ]]; then
    # Check HelmRelease status
    echo -e "${CYAN}HelmRelease Status:${NC}"
    HELM_READY=$(kubectl get helmrelease foundry-gpu-oras -n ${NAMESPACE} -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
    HELM_REASON=$(kubectl get helmrelease foundry-gpu-oras -n ${NAMESPACE} -o jsonpath='{.status.conditions[?(@.type=="Ready")].reason}' 2>/dev/null || echo "Unknown")
    HELM_MESSAGE=$(kubectl get helmrelease foundry-gpu-oras -n ${NAMESPACE} -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}' 2>/dev/null || echo "Unknown")
    
    if [[ "${HELM_READY}" == "True" ]]; then
      echo -e "  ${GREEN}✓${NC} Ready: ${HELM_READY}"
      echo -e "  ${GREEN}✓${NC} Reason: ${HELM_REASON}"
      echo "  Message: ${HELM_MESSAGE}"
    else
      echo -e "  ${RED}✗${NC} Ready: ${HELM_READY}"
      echo -e "  ${RED}✗${NC} Reason: ${HELM_REASON}"
      echo "  Message: ${HELM_MESSAGE}"
    fi
    echo ""
    
    # Check Pod status
    echo -e "${CYAN}Pod Status:${NC}"
    POD_NAME=$(kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/component=foundry -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [[ -n "${POD_NAME}" ]]; then
      POD_STATUS=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
      POD_READY=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
      
      if [[ "${POD_STATUS}" == "Running" ]] && [[ "${POD_READY}" == "True" ]]; then
        echo -e "  ${GREEN}✓${NC} Pod: ${POD_NAME}"
        echo -e "  ${GREEN}✓${NC} Status: ${POD_STATUS}"
        echo -e "  ${GREEN}✓${NC} Ready: ${POD_READY}"
      else
        echo -e "  ${YELLOW}⚠${NC} Pod: ${POD_NAME}"
        echo -e "  ${YELLOW}⚠${NC} Status: ${POD_STATUS}"
        echo -e "  ${YELLOW}⚠${NC} Ready: ${POD_READY}"
      fi
    else
      echo -e "  ${RED}✗${NC} No Foundry pod found"
    fi
    echo ""
    
    # Check deployed version in logs
    echo -e "${CYAN}Deployed Model Version:${NC}"
    if [[ -n "${POD_NAME}" ]]; then
      DEPLOYED_VERSION=$(kubectl logs ${POD_NAME} -n ${NAMESPACE} 2>/dev/null | grep -o "Tag: v[0-9]*\.[0-9]*\.[0-9]*" | tail -1 || echo "")
      if [[ -n "${DEPLOYED_VERSION}" ]]; then
        DEPLOYED_TAG=$(echo ${DEPLOYED_VERSION} | awk '{print $2}')
        if [[ "${DEPLOYED_TAG}" == "${VERSION_TO_REVERT}" ]]; then
          echo -e "  ${GREEN}✓${NC} ${DEPLOYED_VERSION} (matches target)"
        else
          echo -e "  ${YELLOW}⚠${NC} ${DEPLOYED_VERSION} (expected ${VERSION_TO_REVERT})"
        fi
      else
        echo -e "  ${YELLOW}⚠${NC} Could not detect version from logs"
      fi
    fi
    echo ""
    
    # Check ImagePolicy
    echo -e "${CYAN}ImagePolicy Status:${NC}"
    LATEST_IMAGE=$(kubectl get imagepolicy foundry-local-olive-models -n flux-system -o jsonpath='{.status.latestImage}' 2>/dev/null || echo "")
    if [[ -n "${LATEST_IMAGE}" ]]; then
      if echo "${LATEST_IMAGE}" | grep -q "${VERSION_TO_REVERT}"; then
        echo -e "  ${GREEN}✓${NC} Latest detected: ${LATEST_IMAGE}"
      else
        echo -e "  ${YELLOW}⚠${NC} Latest detected: ${LATEST_IMAGE} (expected ${VERSION_TO_REVERT})"
      fi
    else
      echo -e "  ${YELLOW}⚠${NC} Could not get ImagePolicy status"
    fi
    echo ""
    
    # Summary
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    if [[ "${HELM_READY}" == "True" ]] && [[ "${POD_STATUS}" == "Running" ]] && [[ "${POD_READY}" == "True" ]] && [[ "${DEPLOYED_TAG}" == "${VERSION_TO_REVERT}" ]]; then
      echo -e "${GREEN}✓ VALIDATION PASSED: System successfully rolled back to ${VERSION_TO_REVERT}${NC}"
    else
      echo -e "${YELLOW}⚠ VALIDATION INCOMPLETE: Some checks did not pass (see above)${NC}"
    fi
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
  else
    echo -e "${YELLOW}[DRY RUN]${NC} Would validate:"
    echo "  • HelmRelease status and reconciliation"
    echo "  • Pod status (running and ready)"
    echo "  • Deployed model version from logs"
    echo "  • ImagePolicy latest detected version"
    echo ""
  fi
  
  # Final state
  echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo -e "${GREEN}║      Soft Cleanup Dry Run Complete!                     ║${NC}"
  else
    echo -e "${GREEN}║      Soft Cleanup Complete!                              ║${NC}"
  fi
  echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
  echo ""
  
  echo -e "${MAGENTA}What was done:${NC}"
  echo "  • Removed OCI artifacts EXCEPT ${VERSION_TO_REVERT}"
  echo "  • Reverted Git code to ${VERSION_TO_REVERT}"
  echo "  • GitOps rolled back deployment naturally"
  echo "  • Validated cluster resources"
  echo ""
  
  echo -e "${MAGENTA}What was preserved:${NC}"
  echo "  • Flux GitOps configuration"
  echo "  • foundry-system namespace"
  echo "  • All Flux resources (GitRepository, Kustomizations, HelmRelease)"
  echo "  • ImageRepository and ImagePolicy"
  echo ""
  
  if [[ "${DRY_RUN}" == "false" ]]; then
    echo -e "${CYAN}System is now at ${VERSION_TO_REVERT} via GitOps rollback. Ready for next upgrade! 🚀${NC}"
  else
    echo -e "${CYAN}Dry run complete. Run without --dry-run to perform soft cleanup. 🔍${NC}"
  fi
  echo ""
  
  exit 0
fi

################################################################################
# FULL MODE: Complete Reset
################################################################################

# Step 1: Delete Flux GitOps Configuration from Arc
echo -e "${BLUE}Step 1: Deleting Flux GitOps configuration from Arc cluster...${NC}"
if az k8s-configuration flux show \
  --cluster-name ${CLUSTER_NAME} \
  --cluster-type connectedClusters \
  --resource-group ${RESOURCE_GROUP} \
  --name ${CONFIG_NAME} &>/dev/null; then
  
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo -e "${YELLOW}[DRY RUN]${NC} Would delete Flux configuration '${CONFIG_NAME}'"
  else
    az k8s-configuration flux delete \
      --cluster-name ${CLUSTER_NAME} \
      --cluster-type connectedClusters \
      --resource-group ${RESOURCE_GROUP} \
      --name ${CONFIG_NAME} \
      --yes
    
    echo -e "${GREEN}✓ Flux configuration '${CONFIG_NAME}' deleted${NC}"
  fi
else
  echo -e "${YELLOW}⚠ Flux configuration '${CONFIG_NAME}' not found (already deleted)${NC}"
fi
echo ""

# Wait for resources to be cleaned up
if [[ "${DRY_RUN}" == "false" ]]; then
  echo -e "${BLUE}Waiting for Flux to clean up managed resources...${NC}"
  sleep 10
  echo ""
fi

# Step 2: Ensure Foundry resources are removed
echo -e "${BLUE}Step 2: Ensuring Foundry Local resources are removed...${NC}"

# Check if namespace exists
if kubectl get namespace ${NAMESPACE} &>/dev/null; then
  # Try to uninstall Helm release if it exists
  if helm list -n ${NAMESPACE} 2>/dev/null | grep -q "foundry-gpu-oras"; then
    if [[ "${DRY_RUN}" == "true" ]]; then
      echo -e "${YELLOW}[DRY RUN]${NC} Would uninstall Helm release 'foundry-gpu-oras'"
    else
      echo "  Uninstalling Helm release..."
      helm uninstall foundry-gpu-oras -n ${NAMESPACE} --wait || true
      echo -e "${GREEN}✓ Helm release uninstalled${NC}"
    fi
  else
    echo -e "${YELLOW}⚠ Helm release not found${NC}"
  fi
  
  # Delete any remaining resources
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo -e "${YELLOW}[DRY RUN]${NC} Would delete all resources in ${NAMESPACE}"
    echo -e "${YELLOW}[DRY RUN]${NC} Would delete namespace ${NAMESPACE}"
  else
    echo "  Deleting remaining resources in ${NAMESPACE}..."
    kubectl delete all --all -n ${NAMESPACE} --wait=false || true
    
    # Delete the namespace
    echo "  Deleting namespace ${NAMESPACE}..."
    kubectl delete namespace ${NAMESPACE} --wait=true || true
    echo -e "${GREEN}✓ Namespace ${NAMESPACE} deleted${NC}"
  fi
else
  echo -e "${YELLOW}⚠ Namespace ${NAMESPACE} not found (already deleted)${NC}"
fi
echo ""

# Step 3: Remove all OCI artifacts except v0.1.0 from registry
echo -e "${BLUE}Step 3: Removing OCI artifacts (keeping only ${VERSION_TO_REVERT})...${NC}"

# Get all tags from registry
TAGS=$(oras repo tags ${REGISTRY}/${REPO_NAME} 2>/dev/null || echo "")

if [[ -z "${TAGS}" ]]; then
  echo -e "${YELLOW}⚠ Could not list tags (may need authentication or repo doesn't exist)${NC}"
else
  DELETED_COUNT=0
  for TAG in ${TAGS}; do
    if [[ "${TAG}" != "${VERSION_TO_REVERT}" ]]; then
      if [[ "${DRY_RUN}" == "true" ]]; then
        echo -e "  ${YELLOW}[DRY RUN]${NC} Would delete ${TAG}"
        DELETED_COUNT=$((DELETED_COUNT + 1))
      else
        echo "  Deleting ${TAG}..."
        if oras manifest delete ${REGISTRY}/${REPO_NAME}:${TAG} 2>/dev/null; then
          echo -e "  ${GREEN}✓${NC} Deleted ${TAG}"
          DELETED_COUNT=$((DELETED_COUNT + 1))
        else
          echo -e "  ${YELLOW}⚠${NC} Could not delete ${TAG}"
        fi
      fi
    fi
  done
  
  if [[ ${DELETED_COUNT} -eq 0 ]]; then
    echo -e "${GREEN}✓ No artifacts to delete (only ${VERSION_TO_REVERT} exists)${NC}"
  else
    if [[ "${DRY_RUN}" == "true" ]]; then
      echo -e "${YELLOW}[DRY RUN]${NC} Would delete ${DELETED_COUNT} artifact(s), keep ${VERSION_TO_REVERT}"
    else
      echo -e "${GREEN}✓ Deleted ${DELETED_COUNT} artifact(s), kept ${VERSION_TO_REVERT}${NC}"
    fi
  fi
fi
echo ""

# Step 4: Revert code to v0.1.0
echo -e "${BLUE}Step 4: Reverting Git repository to ${VERSION_TO_REVERT}...${NC}"

# Check for uncommitted changes
if [[ -n $(git status -s) ]]; then
  echo -e "${RED}✗ Uncommitted changes detected in Git repository${NC}"
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo -e "${YELLOW}[DRY RUN]${NC} Would exit due to uncommitted changes"
  else
    echo "Please commit or stash your changes before running cleanup."
    exit 1
  fi
fi

# Update helmrelease.yaml to v0.1.0
CURRENT_TAG_IN_FILE=$(yq eval '.spec.values.foundry.byo.tag' apps/foundry-gpu-oras/helmrelease.yaml 2>/dev/null || grep -A 5 "byo:" apps/foundry-gpu-oras/helmrelease.yaml | grep "tag:" | awk '{print $2}' | head -1)

if [[ "${CURRENT_TAG_IN_FILE}" != "${VERSION_TO_REVERT}" ]]; then
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo -e "${YELLOW}[DRY RUN]${NC} Would update helmrelease.yaml: ${CURRENT_TAG_IN_FILE} → ${VERSION_TO_REVERT}"
  else
    sed -i "s/tag: ${CURRENT_TAG_IN_FILE}/tag: ${VERSION_TO_REVERT}/" apps/foundry-gpu-oras/helmrelease.yaml
    echo -e "${GREEN}✓ Updated helmrelease.yaml: ${CURRENT_TAG_IN_FILE} → ${VERSION_TO_REVERT}${NC}"
  fi
else
  echo -e "${YELLOW}⚠ helmrelease.yaml already at ${VERSION_TO_REVERT}${NC}"
fi
echo ""

# Step 5: Commit and push changes
echo -e "${BLUE}Step 5: Committing and pushing changes...${NC}"

if [[ -n $(git status -s) ]]; then
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo -e "${YELLOW}[DRY RUN]${NC} Would commit and push:"
    git status -s | sed 's/^/  /'
  else
    git add apps/foundry-gpu-oras/helmrelease.yaml
    git commit -m "Cleanup: Revert Foundry Local model to ${VERSION_TO_REVERT}"
    git push origin main
    echo -e "${GREEN}✓ Changes committed and pushed${NC}"
  fi
else
  echo -e "${YELLOW}⚠ No changes to commit${NC}"
fi
echo ""

# Step 6: Verify Flux system controllers are healthy
echo -e "${BLUE}Step 6: Verifying Flux system controllers...${NC}"
FLUX_HEALTHY=true

FLUX_CONTROLLERS=(
  "source-controller"
  "kustomize-controller"
  "helm-controller"
  "notification-controller"
  "image-reflector-controller"
  "image-automation-controller"
)

for controller in "${FLUX_CONTROLLERS[@]}"; do
  if kubectl get deployment ${controller} -n flux-system &>/dev/null; then
    READY=$(kubectl get deployment ${controller} -n flux-system -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    DESIRED=$(kubectl get deployment ${controller} -n flux-system -o jsonpath='{.status.replicas}' 2>/dev/null || echo "0")
    
    if [[ "${READY}" == "${DESIRED}" ]] && [[ "${READY}" != "0" ]]; then
      echo -e "  ${GREEN}✓${NC} ${controller}: ${READY}/${DESIRED} ready"
    else
      echo -e "  ${RED}✗${NC} ${controller}: ${READY}/${DESIRED} ready"
      FLUX_HEALTHY=false
    fi
  else
    echo -e "  ${YELLOW}⚠${NC} ${controller}: not found"
  fi
done

if [[ "${FLUX_HEALTHY}" == "true" ]]; then
  echo -e "${GREEN}✓ All Flux controllers are healthy${NC}"
else
  echo -e "${YELLOW}⚠ Some Flux controllers may need attention${NC}"
fi
echo ""

# Step 7: Show final state
echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}FINAL STATE (After Cleanup)${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
echo ""

echo -e "${MAGENTA}✓ CLEANED UP:${NC}"
echo "  • Flux GitOps configuration (${CONFIG_NAME})"
echo "  • Foundry Local application resources"
echo "  • Namespace: ${NAMESPACE}"
echo "  • All OCI artifacts EXCEPT ${VERSION_TO_REVERT}"
echo "  • Git repository reverted to: ${VERSION_TO_REVERT}"
echo ""

echo -e "${MAGENTA}✓ PRESERVED (for next demo):${NC}"
echo "  • Cached container images in cluster"
echo "  • ImageRepository: flux-system/foundry-local-olive-models"
echo "  • ImagePolicy: flux-system/foundry-local-olive-models"
echo "  • Flux system controllers and namespace"
echo "  • GPU operator and cluster infrastructure"
echo "  • OCI artifact: ${REGISTRY}/${REPO_NAME}:${VERSION_TO_REVERT}"
echo ""

echo -e "${BLUE}Remaining OCI Artifacts:${NC}"
oras repo tags ${REGISTRY}/${REPO_NAME} 2>/dev/null || echo "  (Cannot list - authentication may be needed)"
echo ""

echo -e "${BLUE}ImageRepository Status:${NC}"
kubectl get imagerepository -n flux-system 2>/dev/null || echo "  (No ImageRepository found)"
echo ""

echo -e "${BLUE}ImagePolicy Status:${NC}"
kubectl get imagepolicy -n flux-system 2>/dev/null || echo "  (No ImagePolicy found)"
echo ""

echo -e "${BLUE}Flux System Pods:${NC}"
kubectl get pods -n flux-system --no-headers 2>/dev/null | awk '{print "  " $1 " - " $3}' || echo "  (No pods found)"
echo ""

echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
if [[ "${DRY_RUN}" == "true" ]]; then
  echo -e "${GREEN}║      Full Cleanup Dry Run Complete!                     ║${NC}"
else
  echo -e "${GREEN}║      Full Cleanup Complete!                              ║${NC}"
fi
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

if [[ "${DRY_RUN}" == "true" ]]; then
  echo -e "${YELLOW}This was a dry run. No changes were made.${NC}"
  echo -e "${YELLOW}Run without --dry-run to perform actual cleanup.${NC}"
  echo ""
fi

echo -e "${CYAN}Next Steps:${NC}"
echo "  1. Verify OCI artifact ${VERSION_TO_REVERT} exists in registry"
echo -e "  2. Run: ${YELLOW}./scripts/setup/gitops-config.sh${NC} to redeploy"
echo "  3. System will deploy Foundry Local with ${VERSION_TO_REVERT}"
echo ""
if [[ "${DRY_RUN}" == "true" ]]; then
  echo -e "${BLUE}Full cleanup dry run complete. Review the changes above. 🔍${NC}"
else
  echo -e "${BLUE}Ready for next demo! 🚀${NC}"
fi
echo ""
