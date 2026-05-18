#!/usr/bin/env bash
# infra/kind/local-registry.sh
# Starts a local Docker registry and pushes dummy images for kind testing.
# Usage: bash infra/kind/local-registry.sh
set -euo pipefail

REGISTRY_NAME="kind-registry"
REGISTRY_PORT="5001"
APPS=(platform-svc engagement-svc knowledge-svc learning-card learning-ai)

# 1. Start registry container if not running
if ! docker inspect "$REGISTRY_NAME" &>/dev/null; then
  echo "Starting local registry on port $REGISTRY_PORT..."
  docker run -d --restart=always -p "${REGISTRY_PORT}:5000" \
    --network kind --name "$REGISTRY_NAME" registry:2
else
  echo "Registry '$REGISTRY_NAME' already running."
fi

# 2. Push dummy images (nginx:alpine as placeholder)
docker pull nginx:alpine 2>/dev/null || true
for app in "${APPS[@]}"; do
  docker tag nginx:alpine "localhost:${REGISTRY_PORT}/synapse/${app}:1.0.0"
  docker push "localhost:${REGISTRY_PORT}/synapse/${app}:1.0.0"
  echo "Pushed localhost:${REGISTRY_PORT}/synapse/${app}:1.0.0"
done

echo ""
echo "Registry ready. Images:"
curl -s "http://localhost:${REGISTRY_PORT}/v2/_catalog" | python3 -m json.tool 2>/dev/null || \
  curl -s "http://localhost:${REGISTRY_PORT}/v2/_catalog"
