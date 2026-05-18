# W2 Dev Deploy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy 5 apps to dev environment with ESO secret management and image auto-sync, validated on kind first then transitioned to EKS.

**Architecture:** Kustomize base/overlay pattern with ConfigMap for non-sensitive config, ExternalSecret (ESO) for secrets with overlay-patched secretStoreRef to swap between Fake (kind) and AWS (EKS) providers, and ArgoCD Image Updater with local registry (kind) / ECR (EKS) for automatic image tag sync.

**Tech Stack:** Kustomize, ArgoCD, External Secrets Operator, ArgoCD Image Updater, kind, Docker registry:2, Helm

---

## File Structure

### New files to create

```
infra/kind/
├── kind-config.yaml                    # kind cluster config with local registry mirror
├── local-registry.sh                   # Start registry:2, push dummy images
├── setup-kind-w2.sh                    # Full kind bootstrap: cluster + ArgoCD + ESO + Image Updater
└── fake-secret-store.yaml              # ClusterSecretStore with Fake provider

apps/platform-svc/base/configmap.yaml           # Non-sensitive env vars
apps/platform-svc/base/externalsecret.yaml       # ESO ExternalSecret (secretStoreRef: TO_BE_PATCHED)
apps/engagement-svc/base/configmap.yaml
apps/engagement-svc/base/externalsecret.yaml
apps/knowledge-svc/base/configmap.yaml
apps/knowledge-svc/base/externalsecret.yaml
apps/learning-card/base/configmap.yaml
apps/learning-card/base/externalsecret.yaml
apps/learning-ai/base/configmap.yaml
apps/learning-ai/base/externalsecret.yaml
```

### Existing files to modify

```
apps/platform-svc/base/deployment.yaml          # Add envFrom (configMapRef + secretRef)
apps/platform-svc/base/kustomization.yaml        # Add configmap.yaml + externalsecret.yaml to resources
apps/platform-svc/overlays/dev/kustomization.yaml  # Add ConfigMap patch + ExternalSecret secretStoreRef patch

apps/engagement-svc/base/deployment.yaml
apps/engagement-svc/base/kustomization.yaml
apps/engagement-svc/overlays/dev/kustomization.yaml

apps/knowledge-svc/base/deployment.yaml
apps/knowledge-svc/base/kustomization.yaml
apps/knowledge-svc/overlays/dev/kustomization.yaml

apps/learning-card/base/deployment.yaml
apps/learning-card/base/kustomization.yaml
apps/learning-card/overlays/dev/kustomization.yaml

apps/learning-ai/base/deployment.yaml
apps/learning-ai/base/kustomization.yaml
apps/learning-ai/overlays/dev/kustomization.yaml

argocd/applicationset.yaml                       # Add Image Updater annotations to template

docs/project-management/history/HISTORY_gitops.md  # W2 section
docs/project-management/workflow/WORKFLOW_gitops_W2.md  # Check off completed items
docs/project-management/task/TASK_gitops.md      # Step 4/5/6 Status → Done
```

---

## Task 1: kind cluster with local registry

**Files:**
- Create: `infra/kind/kind-config.yaml`
- Create: `infra/kind/local-registry.sh`

- [ ] **Step 1: Create kind cluster config with local registry mirror**

```yaml
# infra/kind/kind-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
containerdConfigPatches:
  - |-
    [plugins."io.containerd.grpc.v1.cri".registry.mirrors."localhost:5001"]
      endpoint = ["http://kind-registry:5001"]
nodes:
  - role: control-plane
  - role: worker
  - role: worker
```

- [ ] **Step 2: Create local registry bootstrap script**

```bash
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
```

- [ ] **Step 3: Create kind cluster and verify**

Run:
```bash
kind create cluster --name synapse-w2 --config infra/kind/kind-config.yaml
kubectl cluster-info --context kind-synapse-w2
kubectl get nodes
```
Expected: 3 nodes (1 control-plane, 2 workers) in Ready state.

- [ ] **Step 4: Start local registry and push dummy images**

Run:
```bash
bash infra/kind/local-registry.sh
```
Expected: 5 images pushed. `curl http://localhost:5001/v2/_catalog` shows `synapse/platform-svc` etc.

- [ ] **Step 5: Commit**

```bash
git add infra/kind/kind-config.yaml infra/kind/local-registry.sh
git commit -m "feat(infra): add kind cluster config with local registry"
```

---

## Task 2: platform-svc base manifests — ConfigMap + envFrom

**Files:**
- Create: `apps/platform-svc/base/configmap.yaml`
- Modify: `apps/platform-svc/base/deployment.yaml`
- Modify: `apps/platform-svc/base/kustomization.yaml`

- [ ] **Step 1: Verify current kustomize build works before changes**

Run:
```bash
kustomize build apps/platform-svc/overlays/dev
```
Expected: YAML output with Deployment + Service, no errors.

- [ ] **Step 2: Create ConfigMap**

```yaml
# apps/platform-svc/base/configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: platform-svc-config
  labels:
    app.kubernetes.io/name: platform-svc
    app.kubernetes.io/part-of: synapse
data:
  LOG_LEVEL: "INFO"
  SERVER_PORT: "8080"
  SPRING_PROFILES_ACTIVE: "default"
```

- [ ] **Step 3: Add envFrom to deployment.yaml**

In `apps/platform-svc/base/deployment.yaml`, add `envFrom` block after `ports`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: platform-svc
  labels:
    app.kubernetes.io/name: platform-svc
    app.kubernetes.io/part-of: synapse
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: platform-svc
  template:
    metadata:
      labels:
        app.kubernetes.io/name: platform-svc
        app.kubernetes.io/part-of: synapse
    spec:
      containers:
        - name: platform-svc
          image: ghcr.io/team-project-final/synapse-platform-svc:latest
          ports:
            - containerPort: 8080
          envFrom:
            - configMapRef:
                name: platform-svc-config
            - secretRef:
                name: platform-svc-secret
                optional: true
          livenessProbe:
            httpGet:
              path: /actuator/health/liveness
              port: 8080
            initialDelaySeconds: 30
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /actuator/health/readiness
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 5
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 512Mi
```

- [ ] **Step 4: Add configmap.yaml to kustomization.yaml**

```yaml
# apps/platform-svc/base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - deployment.yaml
  - service.yaml
  - configmap.yaml

commonLabels:
  app.kubernetes.io/managed-by: kustomize
```

- [ ] **Step 5: Verify kustomize build still works**

Run:
```bash
kustomize build apps/platform-svc/overlays/dev
```
Expected: YAML output now includes ConfigMap resource. No errors.

- [ ] **Step 6: Commit**

```bash
git add apps/platform-svc/base/
git commit -m "feat(platform-svc): add ConfigMap and envFrom to base"
```

---

## Task 3: engagement-svc base manifests — ConfigMap + envFrom

**Files:**
- Create: `apps/engagement-svc/base/configmap.yaml`
- Modify: `apps/engagement-svc/base/deployment.yaml`
- Modify: `apps/engagement-svc/base/kustomization.yaml`

- [ ] **Step 1: Create ConfigMap**

```yaml
# apps/engagement-svc/base/configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: engagement-svc-config
  labels:
    app.kubernetes.io/name: engagement-svc
    app.kubernetes.io/part-of: synapse
data:
  LOG_LEVEL: "INFO"
  SERVER_PORT: "8080"
  SPRING_PROFILES_ACTIVE: "default"
```

- [ ] **Step 2: Add envFrom to deployment.yaml**

Full file `apps/engagement-svc/base/deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: engagement-svc
  labels:
    app.kubernetes.io/name: engagement-svc
    app.kubernetes.io/part-of: synapse
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: engagement-svc
  template:
    metadata:
      labels:
        app.kubernetes.io/name: engagement-svc
        app.kubernetes.io/part-of: synapse
    spec:
      containers:
        - name: engagement-svc
          image: ghcr.io/team-project-final/synapse-engagement-svc:latest
          ports:
            - containerPort: 8080
          envFrom:
            - configMapRef:
                name: engagement-svc-config
            - secretRef:
                name: engagement-svc-secret
                optional: true
          livenessProbe:
            httpGet:
              path: /actuator/health/liveness
              port: 8080
            initialDelaySeconds: 30
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /actuator/health/readiness
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 5
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 512Mi
```

- [ ] **Step 3: Add configmap.yaml to kustomization.yaml**

```yaml
# apps/engagement-svc/base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - deployment.yaml
  - service.yaml
  - configmap.yaml

commonLabels:
  app.kubernetes.io/managed-by: kustomize
```

- [ ] **Step 4: Verify kustomize build**

Run:
```bash
kustomize build apps/engagement-svc/overlays/dev
```
Expected: YAML with Deployment + Service + ConfigMap. No errors.

- [ ] **Step 5: Commit**

```bash
git add apps/engagement-svc/base/
git commit -m "feat(engagement-svc): add ConfigMap and envFrom to base"
```

---

## Task 4: knowledge-svc base manifests — ConfigMap + envFrom

**Files:**
- Create: `apps/knowledge-svc/base/configmap.yaml`
- Modify: `apps/knowledge-svc/base/deployment.yaml`
- Modify: `apps/knowledge-svc/base/kustomization.yaml`

- [ ] **Step 1: Create ConfigMap**

```yaml
# apps/knowledge-svc/base/configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: knowledge-svc-config
  labels:
    app.kubernetes.io/name: knowledge-svc
    app.kubernetes.io/part-of: synapse
data:
  LOG_LEVEL: "INFO"
  SERVER_PORT: "8080"
  SPRING_PROFILES_ACTIVE: "default"
```

- [ ] **Step 2: Add envFrom to deployment.yaml**

Full file `apps/knowledge-svc/base/deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: knowledge-svc
  labels:
    app.kubernetes.io/name: knowledge-svc
    app.kubernetes.io/part-of: synapse
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: knowledge-svc
  template:
    metadata:
      labels:
        app.kubernetes.io/name: knowledge-svc
        app.kubernetes.io/part-of: synapse
    spec:
      containers:
        - name: knowledge-svc
          image: ghcr.io/team-project-final/synapse-knowledge-svc:latest
          ports:
            - containerPort: 8080
          envFrom:
            - configMapRef:
                name: knowledge-svc-config
            - secretRef:
                name: knowledge-svc-secret
                optional: true
          livenessProbe:
            httpGet:
              path: /actuator/health/liveness
              port: 8080
            initialDelaySeconds: 30
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /actuator/health/readiness
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 5
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 512Mi
```

- [ ] **Step 3: Add configmap.yaml to kustomization.yaml**

```yaml
# apps/knowledge-svc/base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - deployment.yaml
  - service.yaml
  - configmap.yaml

commonLabels:
  app.kubernetes.io/managed-by: kustomize
```

- [ ] **Step 4: Verify kustomize build**

Run:
```bash
kustomize build apps/knowledge-svc/overlays/dev
```
Expected: No errors.

- [ ] **Step 5: Commit**

```bash
git add apps/knowledge-svc/base/
git commit -m "feat(knowledge-svc): add ConfigMap and envFrom to base"
```

---

## Task 5: learning-card base manifests — ConfigMap + envFrom

**Files:**
- Create: `apps/learning-card/base/configmap.yaml`
- Modify: `apps/learning-card/base/deployment.yaml`
- Modify: `apps/learning-card/base/kustomization.yaml`

Note: learning-card's port and health check need confirmation from the svc repo. The current base uses 8080 and Spring actuator endpoints. If the svc repo confirms it's Next.js on port 3000, update `containerPort`, `targetPort` in service.yaml, and health check paths accordingly. For now, keep the existing 8080/Spring config and add a TODO comment.

- [ ] **Step 1: Create ConfigMap**

```yaml
# apps/learning-card/base/configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: learning-card-config
  labels:
    app.kubernetes.io/name: learning-card
    app.kubernetes.io/part-of: synapse
data:
  LOG_LEVEL: "INFO"
  SERVER_PORT: "8080"
  SPRING_PROFILES_ACTIVE: "default"
```

- [ ] **Step 2: Add envFrom to deployment.yaml**

Full file `apps/learning-card/base/deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: learning-card
  labels:
    app.kubernetes.io/name: learning-card
    app.kubernetes.io/part-of: synapse
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: learning-card
  template:
    metadata:
      labels:
        app.kubernetes.io/name: learning-card
        app.kubernetes.io/part-of: synapse
    spec:
      containers:
        - name: learning-card
          image: ghcr.io/team-project-final/synapse-learning-card:latest
          ports:
            - containerPort: 8080
          envFrom:
            - configMapRef:
                name: learning-card-config
            - secretRef:
                name: learning-card-secret
                optional: true
          livenessProbe:
            httpGet:
              path: /actuator/health/liveness
              port: 8080
            initialDelaySeconds: 30
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /actuator/health/readiness
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 5
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 512Mi
```

- [ ] **Step 3: Add configmap.yaml to kustomization.yaml**

```yaml
# apps/learning-card/base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - deployment.yaml
  - service.yaml
  - configmap.yaml

commonLabels:
  app.kubernetes.io/managed-by: kustomize
```

- [ ] **Step 4: Verify kustomize build**

Run:
```bash
kustomize build apps/learning-card/overlays/dev
```
Expected: No errors.

- [ ] **Step 5: Commit**

```bash
git add apps/learning-card/base/
git commit -m "feat(learning-card): add ConfigMap and envFrom to base"
```

---

## Task 6: learning-ai base manifests — ConfigMap + envFrom

**Files:**
- Create: `apps/learning-ai/base/configmap.yaml`
- Modify: `apps/learning-ai/base/deployment.yaml`
- Modify: `apps/learning-ai/base/kustomization.yaml`

- [ ] **Step 1: Create ConfigMap**

```yaml
# apps/learning-ai/base/configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: learning-ai-config
  labels:
    app.kubernetes.io/name: learning-ai
    app.kubernetes.io/part-of: synapse
data:
  LOG_LEVEL: "INFO"
  SERVER_PORT: "8000"
  PYTHONUNBUFFERED: "1"
  MODEL_NAME: "gpt-4o-mini"
```

- [ ] **Step 2: Add envFrom to deployment.yaml**

Full file `apps/learning-ai/base/deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: learning-ai
  labels:
    app.kubernetes.io/name: learning-ai
    app.kubernetes.io/part-of: synapse
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: learning-ai
  template:
    metadata:
      labels:
        app.kubernetes.io/name: learning-ai
        app.kubernetes.io/part-of: synapse
    spec:
      containers:
        - name: learning-ai
          image: ghcr.io/team-project-final/synapse-learning-ai:latest
          ports:
            - containerPort: 8000
          envFrom:
            - configMapRef:
                name: learning-ai-config
            - secretRef:
                name: learning-ai-secret
                optional: true
          livenessProbe:
            httpGet:
              path: /health
              port: 8000
            initialDelaySeconds: 30
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /health/ready
              port: 8000
            initialDelaySeconds: 10
            periodSeconds: 5
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 512Mi
```

- [ ] **Step 3: Add configmap.yaml to kustomization.yaml**

```yaml
# apps/learning-ai/base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - deployment.yaml
  - service.yaml
  - configmap.yaml

commonLabels:
  app.kubernetes.io/managed-by: kustomize
```

- [ ] **Step 4: Verify kustomize build**

Run:
```bash
kustomize build apps/learning-ai/overlays/dev
```
Expected: No errors.

- [ ] **Step 5: Commit**

```bash
git add apps/learning-ai/base/
git commit -m "feat(learning-ai): add ConfigMap and envFrom to base"
```

---

## Task 7: Dev overlay ConfigMap patches for all 5 apps

**Files:**
- Modify: `apps/platform-svc/overlays/dev/kustomization.yaml`
- Modify: `apps/engagement-svc/overlays/dev/kustomization.yaml`
- Modify: `apps/knowledge-svc/overlays/dev/kustomization.yaml`
- Modify: `apps/learning-card/overlays/dev/kustomization.yaml`
- Modify: `apps/learning-ai/overlays/dev/kustomization.yaml`

- [ ] **Step 1: Update platform-svc dev overlay**

```yaml
# apps/platform-svc/overlays/dev/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

namespace: synapse-dev

patches:
  - target:
      kind: Deployment
      name: platform-svc
    patch: |
      - op: replace
        path: /spec/replicas
        value: 1
  - target:
      kind: ConfigMap
      name: platform-svc-config
    patch: |
      - op: replace
        path: /data/LOG_LEVEL
        value: "DEBUG"
      - op: replace
        path: /data/SPRING_PROFILES_ACTIVE
        value: "dev"

images:
  - name: ghcr.io/team-project-final/synapse-platform-svc
    newTag: dev-latest
```

- [ ] **Step 2: Update engagement-svc dev overlay**

```yaml
# apps/engagement-svc/overlays/dev/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

namespace: synapse-dev

patches:
  - target:
      kind: Deployment
      name: engagement-svc
    patch: |
      - op: replace
        path: /spec/replicas
        value: 1
  - target:
      kind: ConfigMap
      name: engagement-svc-config
    patch: |
      - op: replace
        path: /data/LOG_LEVEL
        value: "DEBUG"
      - op: replace
        path: /data/SPRING_PROFILES_ACTIVE
        value: "dev"

images:
  - name: ghcr.io/team-project-final/synapse-engagement-svc
    newTag: dev-latest
```

- [ ] **Step 3: Update knowledge-svc dev overlay**

```yaml
# apps/knowledge-svc/overlays/dev/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

namespace: synapse-dev

patches:
  - target:
      kind: Deployment
      name: knowledge-svc
    patch: |
      - op: replace
        path: /spec/replicas
        value: 1
  - target:
      kind: ConfigMap
      name: knowledge-svc-config
    patch: |
      - op: replace
        path: /data/LOG_LEVEL
        value: "DEBUG"
      - op: replace
        path: /data/SPRING_PROFILES_ACTIVE
        value: "dev"

images:
  - name: ghcr.io/team-project-final/synapse-knowledge-svc
    newTag: dev-latest
```

- [ ] **Step 4: Update learning-card dev overlay**

```yaml
# apps/learning-card/overlays/dev/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

namespace: synapse-dev

patches:
  - target:
      kind: Deployment
      name: learning-card
    patch: |
      - op: replace
        path: /spec/replicas
        value: 1
  - target:
      kind: ConfigMap
      name: learning-card-config
    patch: |
      - op: replace
        path: /data/LOG_LEVEL
        value: "DEBUG"
      - op: replace
        path: /data/SPRING_PROFILES_ACTIVE
        value: "dev"

images:
  - name: ghcr.io/team-project-final/synapse-learning-card
    newTag: dev-latest
```

- [ ] **Step 5: Update learning-ai dev overlay**

```yaml
# apps/learning-ai/overlays/dev/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

namespace: synapse-dev

patches:
  - target:
      kind: Deployment
      name: learning-ai
    patch: |
      - op: replace
        path: /spec/replicas
        value: 1
  - target:
      kind: ConfigMap
      name: learning-ai-config
    patch: |
      - op: replace
        path: /data/LOG_LEVEL
        value: "DEBUG"

images:
  - name: ghcr.io/team-project-final/synapse-learning-ai
    newTag: dev-latest
```

- [ ] **Step 6: Verify all 5 kustomize builds pass**

Run:
```bash
for app in platform-svc engagement-svc knowledge-svc learning-card learning-ai; do
  echo "=== $app ==="
  kustomize build "apps/$app/overlays/dev" > /dev/null && echo "OK" || echo "FAIL"
done
```
Expected: All 5 print "OK".

- [ ] **Step 7: Commit**

```bash
git add apps/*/overlays/dev/kustomization.yaml
git commit -m "feat(overlays): add dev ConfigMap patches for all 5 apps"
```

---

## Task 8: Step 4 kind verification — ArgoCD sync

This task is a **user action** — the engineer runs these commands on their kind cluster with ArgoCD already installed (from W1 bootstrap).

- [ ] **Step 1: Install ArgoCD on kind (if not already running)**

Run:
```bash
kubectl create namespace argocd 2>/dev/null || true
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml --server-side --force-conflicts
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s
```

- [ ] **Step 2: Apply ArgoCD project and ApplicationSet**

Run:
```bash
kubectl apply -f argocd/projects.yaml
kubectl apply -f argocd/applicationset.yaml
```

- [ ] **Step 3: Verify 5 apps appear in ArgoCD**

Run:
```bash
kubectl get applications -n argocd
```
Expected: 5 applications named `synapse-{app}-dev` listed.

- [ ] **Step 4: Check sync status**

Run:
```bash
for app in platform-svc engagement-svc knowledge-svc learning-card learning-ai; do
  echo "=== synapse-$app-dev ==="
  kubectl get application "synapse-$app-dev" -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null
  echo ""
done
```
Expected: All 5 show `Synced` or `OutOfSync` (OutOfSync is fine — the cluster doesn't have the namespace yet, which is expected on a fresh kind).

- [ ] **Step 5: Commit (no code changes, just checkpoint)**

No commit needed — this is a verification task.

---

## Task 9: ExternalSecret base manifests for all 5 apps

**Files:**
- Create: `apps/platform-svc/base/externalsecret.yaml`
- Create: `apps/engagement-svc/base/externalsecret.yaml`
- Create: `apps/knowledge-svc/base/externalsecret.yaml`
- Create: `apps/learning-card/base/externalsecret.yaml`
- Create: `apps/learning-ai/base/externalsecret.yaml`
- Modify: `apps/platform-svc/base/kustomization.yaml`
- Modify: `apps/engagement-svc/base/kustomization.yaml`
- Modify: `apps/knowledge-svc/base/kustomization.yaml`
- Modify: `apps/learning-card/base/kustomization.yaml`
- Modify: `apps/learning-ai/base/kustomization.yaml`

- [ ] **Step 1: Create platform-svc ExternalSecret**

```yaml
# apps/platform-svc/base/externalsecret.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: platform-svc-external-secret
  labels:
    app.kubernetes.io/name: platform-svc
    app.kubernetes.io/part-of: synapse
spec:
  refreshInterval: 5m
  secretStoreRef:
    name: TO_BE_PATCHED
    kind: ClusterSecretStore
  target:
    name: platform-svc-secret
    creationPolicy: Owner
  data:
    - secretKey: DATABASE_PASSWORD
      remoteRef:
        key: synapse/dev/platform-svc/db-password
    - secretKey: JWT_SECRET
      remoteRef:
        key: synapse/dev/platform-svc/jwt-secret
```

- [ ] **Step 2: Create engagement-svc ExternalSecret**

```yaml
# apps/engagement-svc/base/externalsecret.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: engagement-svc-external-secret
  labels:
    app.kubernetes.io/name: engagement-svc
    app.kubernetes.io/part-of: synapse
spec:
  refreshInterval: 5m
  secretStoreRef:
    name: TO_BE_PATCHED
    kind: ClusterSecretStore
  target:
    name: engagement-svc-secret
    creationPolicy: Owner
  data:
    - secretKey: DATABASE_PASSWORD
      remoteRef:
        key: synapse/dev/engagement-svc/db-password
```

- [ ] **Step 3: Create knowledge-svc ExternalSecret**

```yaml
# apps/knowledge-svc/base/externalsecret.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: knowledge-svc-external-secret
  labels:
    app.kubernetes.io/name: knowledge-svc
    app.kubernetes.io/part-of: synapse
spec:
  refreshInterval: 5m
  secretStoreRef:
    name: TO_BE_PATCHED
    kind: ClusterSecretStore
  target:
    name: knowledge-svc-secret
    creationPolicy: Owner
  data:
    - secretKey: DATABASE_PASSWORD
      remoteRef:
        key: synapse/dev/knowledge-svc/db-password
    - secretKey: S3_ACCESS_KEY
      remoteRef:
        key: synapse/dev/knowledge-svc/s3-access-key
```

- [ ] **Step 4: Create learning-card ExternalSecret**

```yaml
# apps/learning-card/base/externalsecret.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: learning-card-external-secret
  labels:
    app.kubernetes.io/name: learning-card
    app.kubernetes.io/part-of: synapse
spec:
  refreshInterval: 5m
  secretStoreRef:
    name: TO_BE_PATCHED
    kind: ClusterSecretStore
  target:
    name: learning-card-secret
    creationPolicy: Owner
  data:
    - secretKey: API_KEY
      remoteRef:
        key: synapse/dev/learning-card/api-key
```

- [ ] **Step 5: Create learning-ai ExternalSecret**

```yaml
# apps/learning-ai/base/externalsecret.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: learning-ai-external-secret
  labels:
    app.kubernetes.io/name: learning-ai
    app.kubernetes.io/part-of: synapse
spec:
  refreshInterval: 5m
  secretStoreRef:
    name: TO_BE_PATCHED
    kind: ClusterSecretStore
  target:
    name: learning-ai-secret
    creationPolicy: Owner
  data:
    - secretKey: OPENAI_API_KEY
      remoteRef:
        key: synapse/dev/learning-ai/openai-api-key
    - secretKey: DATABASE_PASSWORD
      remoteRef:
        key: synapse/dev/learning-ai/db-password
```

- [ ] **Step 6: Add externalsecret.yaml to all 5 base kustomization.yaml files**

Each app's `base/kustomization.yaml` should now list 4 resources. Example for platform-svc:

```yaml
# apps/platform-svc/base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - deployment.yaml
  - service.yaml
  - configmap.yaml
  - externalsecret.yaml

commonLabels:
  app.kubernetes.io/managed-by: kustomize
```

Repeat for all 5 apps (engagement-svc, knowledge-svc, learning-card, learning-ai) — same pattern, just add `- externalsecret.yaml` to resources.

- [ ] **Step 7: Verify kustomize build for all 5 (expect CRD warning)**

Run:
```bash
for app in platform-svc engagement-svc knowledge-svc learning-card learning-ai; do
  echo "=== $app ==="
  kustomize build "apps/$app/overlays/dev" > /dev/null && echo "OK" || echo "FAIL"
done
```
Expected: All 5 print "OK". kubeconform may warn about unknown ExternalSecret CRD — this is expected with `-ignore-missing-schemas`.

- [ ] **Step 8: Commit**

```bash
git add apps/*/base/externalsecret.yaml apps/*/base/kustomization.yaml
git commit -m "feat(apps): add ExternalSecret manifests for all 5 apps"
```

---

## Task 10: Dev overlay ExternalSecret secretStoreRef patches

**Files:**
- Modify: `apps/platform-svc/overlays/dev/kustomization.yaml`
- Modify: `apps/engagement-svc/overlays/dev/kustomization.yaml`
- Modify: `apps/knowledge-svc/overlays/dev/kustomization.yaml`
- Modify: `apps/learning-card/overlays/dev/kustomization.yaml`
- Modify: `apps/learning-ai/overlays/dev/kustomization.yaml`

- [ ] **Step 1: Add ExternalSecret patch to platform-svc dev overlay**

Add to the `patches` list in `apps/platform-svc/overlays/dev/kustomization.yaml`:

```yaml
  - target:
      kind: ExternalSecret
      name: platform-svc-external-secret
    patch: |
      - op: replace
        path: /spec/secretStoreRef/name
        value: fake-secrets
```

Full file after this change:

```yaml
# apps/platform-svc/overlays/dev/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

namespace: synapse-dev

patches:
  - target:
      kind: Deployment
      name: platform-svc
    patch: |
      - op: replace
        path: /spec/replicas
        value: 1
  - target:
      kind: ConfigMap
      name: platform-svc-config
    patch: |
      - op: replace
        path: /data/LOG_LEVEL
        value: "DEBUG"
      - op: replace
        path: /data/SPRING_PROFILES_ACTIVE
        value: "dev"
  - target:
      kind: ExternalSecret
      name: platform-svc-external-secret
    patch: |
      - op: replace
        path: /spec/secretStoreRef/name
        value: fake-secrets

images:
  - name: ghcr.io/team-project-final/synapse-platform-svc
    newTag: dev-latest
```

- [ ] **Step 2: Add ExternalSecret patch to engagement-svc dev overlay**

```yaml
# apps/engagement-svc/overlays/dev/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

namespace: synapse-dev

patches:
  - target:
      kind: Deployment
      name: engagement-svc
    patch: |
      - op: replace
        path: /spec/replicas
        value: 1
  - target:
      kind: ConfigMap
      name: engagement-svc-config
    patch: |
      - op: replace
        path: /data/LOG_LEVEL
        value: "DEBUG"
      - op: replace
        path: /data/SPRING_PROFILES_ACTIVE
        value: "dev"
  - target:
      kind: ExternalSecret
      name: engagement-svc-external-secret
    patch: |
      - op: replace
        path: /spec/secretStoreRef/name
        value: fake-secrets

images:
  - name: ghcr.io/team-project-final/synapse-engagement-svc
    newTag: dev-latest
```

- [ ] **Step 3: Add ExternalSecret patch to knowledge-svc dev overlay**

```yaml
# apps/knowledge-svc/overlays/dev/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

namespace: synapse-dev

patches:
  - target:
      kind: Deployment
      name: knowledge-svc
    patch: |
      - op: replace
        path: /spec/replicas
        value: 1
  - target:
      kind: ConfigMap
      name: knowledge-svc-config
    patch: |
      - op: replace
        path: /data/LOG_LEVEL
        value: "DEBUG"
      - op: replace
        path: /data/SPRING_PROFILES_ACTIVE
        value: "dev"
  - target:
      kind: ExternalSecret
      name: knowledge-svc-external-secret
    patch: |
      - op: replace
        path: /spec/secretStoreRef/name
        value: fake-secrets

images:
  - name: ghcr.io/team-project-final/synapse-knowledge-svc
    newTag: dev-latest
```

- [ ] **Step 4: Add ExternalSecret patch to learning-card dev overlay**

```yaml
# apps/learning-card/overlays/dev/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

namespace: synapse-dev

patches:
  - target:
      kind: Deployment
      name: learning-card
    patch: |
      - op: replace
        path: /spec/replicas
        value: 1
  - target:
      kind: ConfigMap
      name: learning-card-config
    patch: |
      - op: replace
        path: /data/LOG_LEVEL
        value: "DEBUG"
      - op: replace
        path: /data/SPRING_PROFILES_ACTIVE
        value: "dev"
  - target:
      kind: ExternalSecret
      name: learning-card-external-secret
    patch: |
      - op: replace
        path: /spec/secretStoreRef/name
        value: fake-secrets

images:
  - name: ghcr.io/team-project-final/synapse-learning-card
    newTag: dev-latest
```

- [ ] **Step 5: Add ExternalSecret patch to learning-ai dev overlay**

```yaml
# apps/learning-ai/overlays/dev/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

namespace: synapse-dev

patches:
  - target:
      kind: Deployment
      name: learning-ai
    patch: |
      - op: replace
        path: /spec/replicas
        value: 1
  - target:
      kind: ConfigMap
      name: learning-ai-config
    patch: |
      - op: replace
        path: /data/LOG_LEVEL
        value: "DEBUG"
  - target:
      kind: ExternalSecret
      name: learning-ai-external-secret
    patch: |
      - op: replace
        path: /spec/secretStoreRef/name
        value: fake-secrets

images:
  - name: ghcr.io/team-project-final/synapse-learning-ai
    newTag: dev-latest
```

- [ ] **Step 6: Verify all 5 kustomize builds**

Run:
```bash
for app in platform-svc engagement-svc knowledge-svc learning-card learning-ai; do
  echo "=== $app ==="
  kustomize build "apps/$app/overlays/dev" > /dev/null && echo "OK" || echo "FAIL"
done
```
Expected: All 5 print "OK".

- [ ] **Step 7: Commit**

```bash
git add apps/*/overlays/dev/kustomization.yaml
git commit -m "feat(overlays): add ExternalSecret secretStoreRef patches for dev"
```

---

## Task 11: Fake SecretStore + ESO kind setup

**Files:**
- Create: `infra/kind/fake-secret-store.yaml`

- [ ] **Step 1: Create Fake ClusterSecretStore manifest**

```yaml
# infra/kind/fake-secret-store.yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: fake-secrets
spec:
  provider:
    fake:
      data:
        - key: synapse/dev/platform-svc/db-password
          value: "fake-dev-platform-db-pw"
        - key: synapse/dev/platform-svc/jwt-secret
          value: "fake-dev-jwt-secret"
        - key: synapse/dev/engagement-svc/db-password
          value: "fake-dev-engagement-db-pw"
        - key: synapse/dev/knowledge-svc/db-password
          value: "fake-dev-knowledge-db-pw"
        - key: synapse/dev/knowledge-svc/s3-access-key
          value: "fake-dev-s3-access-key"
        - key: synapse/dev/learning-card/api-key
          value: "fake-dev-learning-card-api-key"
        - key: synapse/dev/learning-ai/openai-api-key
          value: "fake-dev-openai-api-key"
        - key: synapse/dev/learning-ai/db-password
          value: "fake-dev-learning-ai-db-pw"
```

- [ ] **Step 2: Install ESO on kind via Helm**

Run:
```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update
helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace \
  --set installCRDs=true \
  --wait
```
Expected: 3 pods Running in `external-secrets` namespace.

- [ ] **Step 3: Apply Fake ClusterSecretStore**

Run:
```bash
kubectl apply -f infra/kind/fake-secret-store.yaml
```

- [ ] **Step 4: Verify ClusterSecretStore is Valid**

Run:
```bash
kubectl get clustersecretstore fake-secrets
```
Expected: `STATUS` column shows `Valid`.

- [ ] **Step 5: Commit**

```bash
git add infra/kind/fake-secret-store.yaml
git commit -m "feat(infra): add ESO Fake ClusterSecretStore for kind testing"
```

---

## Task 12: Step 5 kind verification — ESO sync

This is a **user action** task — run on kind cluster after Task 11.

- [ ] **Step 1: Create synapse-dev namespace**

Run:
```bash
kubectl create namespace synapse-dev 2>/dev/null || true
```

- [ ] **Step 2: Apply ExternalSecrets via kustomize**

Run:
```bash
for app in platform-svc engagement-svc knowledge-svc learning-card learning-ai; do
  echo "=== Applying $app ==="
  kustomize build "apps/$app/overlays/dev" | kubectl apply -f - --server-side
done
```

- [ ] **Step 3: Verify ExternalSecret sync status**

Run:
```bash
kubectl get externalsecret -n synapse-dev
```
Expected: 5 ExternalSecrets, all with `STATUS=SecretSynced`.

- [ ] **Step 4: Verify K8s Secrets were created**

Run:
```bash
kubectl get secret -n synapse-dev | grep -E "platform-svc-secret|engagement-svc-secret|knowledge-svc-secret|learning-card-secret|learning-ai-secret"
```
Expected: 5 secrets listed.

- [ ] **Step 5: Verify secret values**

Run:
```bash
kubectl get secret -n synapse-dev platform-svc-secret -o jsonpath='{.data.DATABASE_PASSWORD}' | base64 -d
```
Expected: `fake-dev-platform-db-pw`

- [ ] **Step 6: Run gitleaks scan**

Run:
```bash
gitleaks detect --source . --verbose 2>&1 | tail -5
```
Expected: `0 findings` (Fake values are not real secrets).

---

## Task 13: ApplicationSet Image Updater annotations

**Files:**
- Modify: `argocd/applicationset.yaml`

- [ ] **Step 1: Add Image Updater annotations to ApplicationSet template**

```yaml
# argocd/applicationset.yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: synapse-apps
  namespace: argocd
spec:
  generators:
    - matrix:
        generators:
          - list:
              elements:
                - service: platform-svc
                - service: engagement-svc
                - service: knowledge-svc
                - service: learning-card
                - service: learning-ai
          - list:
              elements:
                - env: dev
  template:
    metadata:
      name: "synapse-{{service}}-{{env}}"
      namespace: argocd
      labels:
        app.kubernetes.io/part-of: synapse
        app.kubernetes.io/component: "{{service}}"
        environment: "{{env}}"
      annotations:
        argocd-image-updater.argoproj.io/image-list: "app=localhost:5001/synapse/{{service}}"
        argocd-image-updater.argoproj.io/app.update-strategy: semver
        argocd-image-updater.argoproj.io/app.allow-tags: "regexp:^[0-9]+\\.[0-9]+\\.[0-9]+$"
        argocd-image-updater.argoproj.io/write-back-method: git
        argocd-image-updater.argoproj.io/write-back-target: kustomization
        argocd-image-updater.argoproj.io/git-branch: main
    spec:
      project: synapse
      source:
        repoURL: https://github.com/team-project-final/synapse-gitops.git
        targetRevision: main
        path: "apps/{{service}}/overlays/{{env}}"
      destination:
        server: https://kubernetes.default.svc
        namespace: "synapse-{{env}}"
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
```

- [ ] **Step 2: Verify YAML is valid**

Run:
```bash
yamllint argocd/applicationset.yaml
```
Expected: No errors (warnings about line length are OK).

- [ ] **Step 3: Commit**

```bash
git add argocd/applicationset.yaml
git commit -m "feat(argocd): add Image Updater annotations to ApplicationSet"
```

---

## Task 14: kind W2 setup script

**Files:**
- Create: `infra/kind/setup-kind-w2.sh`

- [ ] **Step 1: Create comprehensive setup script**

```bash
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
  kind create cluster --name synapse-w2 --config "$SCRIPT_DIR/kind-config.yaml"
fi
kubectl cluster-info --context kind-synapse-w2

echo ""
echo "=== 2/6 Starting local registry ==="
bash "$SCRIPT_DIR/local-registry.sh"

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
```

- [ ] **Step 2: Make script executable**

Run:
```bash
chmod +x infra/kind/setup-kind-w2.sh
```

- [ ] **Step 3: Commit**

```bash
git add infra/kind/setup-kind-w2.sh
git commit -m "feat(infra): add kind W2 full setup script"
```

---

## Task 15: Step 6 kind verification — Image Updater E2E

This is a **user action** task.

- [ ] **Step 1: Run the full setup script (if not done)**

Run:
```bash
bash infra/kind/setup-kind-w2.sh
```

- [ ] **Step 2: Verify Image Updater is running**

Run:
```bash
kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-image-updater
```
Expected: 1 pod Running.

- [ ] **Step 3: Push a new image tag to local registry**

Run:
```bash
docker tag nginx:alpine localhost:5001/synapse/platform-svc:1.0.1
docker push localhost:5001/synapse/platform-svc:1.0.1
echo "Push time: $(date)"
```

- [ ] **Step 4: Wait for Image Updater to detect the new tag (1-2 min)**

Run:
```bash
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-image-updater --tail=20 | grep -i "platform-svc\|update\|new"
```
Expected: Log entries showing the new tag 1.0.1 was detected.

- [ ] **Step 5: Verify deployment image tag was updated**

Run:
```bash
kubectl get deployment -n synapse-dev platform-svc -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null
```
Expected: Image tag changed to `1.0.1`.

- [ ] **Step 6: Check git for write-back commit (if write-back is configured)**

Run:
```bash
git pull 2>/dev/null || true
git log --oneline -5
```
Expected: Image Updater commit if git write-back is working. If not (common on kind without SSH keys), the annotation-based update is still valid.

---

## Task 16: Documentation updates — HISTORY, WORKFLOW, TASK

**Files:**
- Modify: `docs/project-management/history/HISTORY_gitops.md`
- Modify: `docs/project-management/workflow/WORKFLOW_gitops_W2.md`
- Modify: `docs/project-management/task/TASK_gitops.md`

- [ ] **Step 1: Add W2 section to HISTORY**

Append after the W1 section in `docs/project-management/history/HISTORY_gitops.md`:

```markdown
---

## 2026-05-19 ~ 2026-05-23 (W2)

### 의사결정
- **D-009 kind 먼저 → EKS 전환**: 결제수단 verification 미완, 비용 0으로 구조 검증.
- **D-010 ESO Fake provider (kind) → AWS provider (EKS)**: kind에서 ESO 동작 흐름 검증 + overlay 패치로 교체 용이.
- **D-011 로컬 레지스트리 + Image Updater (kind)**: ECR 없이 이미지 자동 반영 E2E 검증 가능.
- **D-012 단일 브랜치 순차 진행**: W1 패턴 일치, Step 간 의존성 자연 처리, 하나의 PR로 리뷰.
- **D-013 ConfigMap은 svc 레포 yml 기반**: 실제 앱 설정과 정합성 보장.
- **D-014 ExternalSecret secretStoreRef를 overlay에서 패치**: kind/EKS 전환 시 구조 변경 없이 값만 교체.

### 산출물
- 디자인 스펙: `docs/superpowers/specs/2026-05-18-w2-dev-deploy-design.md`
- 구현 플랜: `docs/superpowers/plans/2026-05-18-w2-dev-deploy.md`
- kind 인프라: `infra/kind/` (kind-config, local-registry, setup-kind-w2, fake-secret-store)
- 5개 앱 base 보강: ConfigMap + ExternalSecret + envFrom
- dev overlay: ConfigMap patch + ExternalSecret secretStoreRef patch
- ApplicationSet: Image Updater annotations

### 이벤트
- (kind 실증 결과를 여기에 기록)
- (EKS 전환 결과를 여기에 기록)
```

- [ ] **Step 2: Update WORKFLOW W2 checkboxes**

In `docs/project-management/workflow/WORKFLOW_gitops_W2.md`, check off completed items in Step 4 section 1.1~1.4, Step 5 section 1.1~1.4, Step 6 section 1.1~1.4 as work progresses. Update the Status lines at the bottom of each Step section.

This is done incrementally as each Step is verified — update the checkboxes that match completed work.

- [ ] **Step 3: Update TASK Step 4/5/6 Status**

In `docs/project-management/task/TASK_gitops.md`, update Step 4/5/6 status lines:

For Step 4 (line 87): change `[ ] Not Started / [ ] In Progress / [ ] Done` to `[ ] Not Started / [ ] In Progress / [x] Done`

For Step 5 (line 103): same pattern.

For Step 6 (line 119): same pattern.

- [ ] **Step 4: Commit**

```bash
git add docs/project-management/
git commit -m "docs(pm): update W2 HISTORY, WORKFLOW checkboxes, TASK status"
```

---

## Task 17: EKS provider swap (Phase 2 — user action)

This task is done when EKS is available. The engineer swaps kind-specific values to AWS values.

- [ ] **Step 1: Swap ExternalSecret secretStoreRef in all 5 dev overlays**

In each `apps/{app}/overlays/dev/kustomization.yaml`, change the ExternalSecret patch value from `fake-secrets` to `aws-secrets-manager`:

```yaml
    patch: |
      - op: replace
        path: /spec/secretStoreRef/name
        value: aws-secrets-manager
```

- [ ] **Step 2: Swap ApplicationSet image-list annotation**

In `argocd/applicationset.yaml`, replace:
```yaml
argocd-image-updater.argoproj.io/image-list: "app=localhost:5001/synapse/{{service}}"
```
with:
```yaml
argocd-image-updater.argoproj.io/image-list: "app=<ACCOUNT>.dkr.ecr.ap-northeast-2.amazonaws.com/synapse/{{service}}"
```

Replace `<ACCOUNT>` with the actual AWS account ID.

- [ ] **Step 3: Reinstall Image Updater with ECR config**

Run (see `docs/runbooks/step6-image-sync.md` section 6-B for full details):
```bash
helm upgrade argocd-image-updater argo/argocd-image-updater \
  --namespace argocd \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="arn:aws:iam::<ACCOUNT>:role/synapse-dev-image-updater-role" \
  --set config.registries[0].name=ecr \
  --set config.registries[0].api_url="https://<ACCOUNT>.dkr.ecr.ap-northeast-2.amazonaws.com" \
  --set config.registries[0].prefix="<ACCOUNT>.dkr.ecr.ap-northeast-2.amazonaws.com" \
  --set config.registries[0].default=true \
  --set config.argocd.plaintext=true \
  --set "extraArgs[0]=--interval=1m" \
  --wait
```

- [ ] **Step 4: Create AWS ClusterSecretStore**

Follow `docs/runbooks/step5-eso-secrets.md` sections 5-B and 5-C for:
1. AWS Secrets Manager에 8개 시크릿 등록
2. IRSA 설정
3. ClusterSecretStore (AWS provider) 생성

- [ ] **Step 5: Verify PRD W2 checklist**

Run:
```bash
# FR-GO-201
argocd app list

# FR-GO-203
gitleaks detect --source . --verbose 2>&1 | tail -3

# FR-GO-204
kubectl get externalsecret -n synapse-dev
```

- [ ] **Step 6: Commit EKS swap**

```bash
git add apps/*/overlays/dev/kustomization.yaml argocd/applicationset.yaml
git commit -m "feat: swap kind providers to AWS (ESO + ECR) for EKS"
```
