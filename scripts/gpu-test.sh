#!/bin/bash
# GPU Test Script - Verifies GPU access in Kubernetes workloads

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║              NVIDIA GPU OPERATOR - FUNCTIONAL TEST             ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Deploy GPU test pod
echo "1️⃣  Deploying GPU test pod..."
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: gpu-test-cuda
spec:
  restartPolicy: OnFailure
  runtimeClassName: nvidia
  containers:
  - name: cuda-test
    image: nvidia/cuda:12.8.1-runtime-ubuntu24.04
    command: ["nvidia-smi"]
    resources:
      limits:
        nvidia.com/gpu: 1
EOF
echo "   ✅ Pod deployed"
echo ""

# Wait for pod to complete
echo "2️⃣  Waiting for pod to complete..."
sleep 5
kubectl wait --for=condition=ready pod/gpu-test-cuda --timeout=30s 2>/dev/null || true
sleep 2
echo "   ✅ Pod execution completed"
echo ""

# Check status
echo "3️⃣  Pod Status:"
kubectl get pods gpu-test-cuda
echo ""

# Display results
echo "4️⃣  GPU Test Output (nvidia-smi):"
echo "═══════════════════════════════════════════════════════════════"
kubectl logs gpu-test-cuda
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Verification
POD_STATUS=$(kubectl get pod gpu-test-cuda -o jsonpath='{.status.phase}')
if [ "$POD_STATUS" == "Succeeded" ] || [ "$POD_STATUS" == "Completed" ]; then
    echo "✅ GPU TEST SUCCESSFUL!"
    echo "   Container successfully accessed the GPU"
else
    echo "❌ GPU TEST FAILED!"
    echo "   Pod Status: $POD_STATUS"
fi
echo ""

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║            Test pod: gpu-test-cuda                            ║"
echo "║            Namespace: default                                 ║"
echo "║                                                                ║"
echo "║  To clean up test:                                            ║"
echo "║    kubectl delete pod gpu-test-cuda                           ║"
echo "╚════════════════════════════════════════════════════════════════╝"
