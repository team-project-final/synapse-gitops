#!/usr/bin/env bash
# infra/kind/setup-kind-w2.sh
# Full kind cluster bootstrap for W2: cluster + registry + ArgoCD + ESO + Image Updater
# Usage: bash infra/kind/setup-kind-w2.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "=== 1/6 Creating kind cluster ==="
if kind get clusters 2>/dev/null | grep -q synapse-w2; then
  echo "Cluster synapse-w2 already exists, skipping."
else
  kind create cluster --name synapse-w2 --config "$SCRIPT_DIR/kind-config.yaml" --wait 5m
fi
kubectl cluster-info --context kind-synapse-w2

echo ""
echo "=== 2/6 Starting local registry ==="
bash "$SCRIPT_DIR/local-registry.sh" synapse-w2

echo ""
echo "=== 3/6 Installing ArgoCD ==="
kubectl create namespace argocd 2>/dev/null || true
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml \
  --server-side --force-conflicts
echo "Waiting for argocd-server..."
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s

echo ""
echo "=== 4/6 Applying ArgoCD project + ApplicationSet ==="
kubectl apply -f "$REPO_ROOT/argocd/projects.yaml"
kubectl apply -f "$REPO_ROOT/argocd/applicationset.yaml"

echo ""
echo "=== 5/6 Installing ESO + Fake SecretStore ==="
helm repo add external-secrets https://charts.external-secrets.io 2>/dev/null || true
helm repo update
if ! helm list -n external-secrets 2>/dev/null | grep -q external-secrets; then
  helm install external-secrets external-secrets/external-secrets \
    --namespace external-secrets \
    --create-namespace \
    --set installCRDs=true \
    --wait
fi
kubectl apply -f "$SCRIPT_DIR/fake-secret-store.yaml"

echo ""
echo "=== 6/6 Installing ArgoCD Image Updater ==="
helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
helm repo update
if ! helm list -n argocd 2>/dev/null | grep -q argocd-image-updater; then
  helm install argocd-image-updater argo/argocd-image-updater \
    --namespace argocd \
    --set config.registries[0].name=local \
    --set config.registries[0].api_url="http://kind-registry:5001" \
    --set config.registries[0].prefix="localhost:5001" \
    --set config.registries[0].default=true \
    --set config.registries[0].insecure=true \
    --set config.argocd.plaintext=true \
    --set "extraArgs[0]=--interval=1m" \
    --wait
fi

echo ""
echo "=== Setup complete ==="
echo ""
echo "Verification commands:"
echo "  kubectl get nodes"
echo "  kubectl get pods -n argocd"
echo "  kubectl get pods -n external-secrets"
echo "  kubectl get applications -n argocd"
echo "  kubectl get clustersecretstore"
echo "  curl http://localhost:5001/v2/_catalog"
