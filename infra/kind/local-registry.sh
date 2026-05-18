#!/usr/bin/env bash
# infra/kind/local-registry.sh
# Starts a local Docker registry, connects it to kind network,
# and configures kind nodes to use it.
# Usage: bash infra/kind/local-registry.sh
set -euo pipefail

REGISTRY_NAME="kind-registry"
REGISTRY_PORT="5001"
CLUSTER_NAME="${1:-synapse-w2}"
APPS=(platform-svc engagement-svc knowledge-svc learning-card learning-ai)

# 1. Start registry container if not running
if ! docker inspect "$REGISTRY_NAME" &>/dev/null; then
  echo "Starting local registry on port $REGISTRY_PORT..."
  docker run -d --restart=always -p "${REGISTRY_PORT}:5000" \
    --name "$REGISTRY_NAME" registry:2
else
  echo "Registry '$REGISTRY_NAME' already running."
fi

# 2. Connect registry to kind network (if not already connected)
if ! docker network inspect kind &>/dev/null; then
  echo "kind network not found, creating..."
  docker network create kind
fi
if ! docker inspect "$REGISTRY_NAME" --format='{{json .NetworkSettings.Networks.kind}}' | grep -q "IPAddress"; then
  echo "Connecting registry to kind network..."
  docker network connect kind "$REGISTRY_NAME" 2>/dev/null || true
fi

# 3. Configure kind nodes to use the local registry via configmap
# See: https://kind.sigs.k8s.io/docs/user/local-registry/
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-registry-hosting
  namespace: kube-public
data:
  localRegistryHosting.v1: |
    host: "localhost:${REGISTRY_PORT}"
    help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
EOF

# 4. Push dummy images (nginx:alpine as placeholder)
docker pull nginx:alpine 2>/dev/null || true
for app in "${APPS[@]}"; do
  docker tag nginx:alpine "localhost:${REGISTRY_PORT}/synapse/${app}:1.0.0"
  docker push "localhost:${REGISTRY_PORT}/synapse/${app}:1.0.0"
  echo "Pushed localhost:${REGISTRY_PORT}/synapse/${app}:1.0.0"
done

echo ""
echo "Registry ready. Images:"
curl -s "http://localhost:${REGISTRY_PORT}/v2/_catalog" | jq . 2>/dev/null || \
  curl -s "http://localhost:${REGISTRY_PORT}/v2/_catalog"
