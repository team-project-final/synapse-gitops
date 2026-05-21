# Cross-Repo Work Order Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bootstrap AWS infra, stabilize 5 services to Healthy, create staging overlay, and align both repos' handoff docs for W3.

**Architecture:** Two-repo (synapse-gitops + synapse-shared) sequential work across 6 phases. Infrastructure ops (terraform/kubectl) first, then Kustomize staging overlay, then documentation alignment.

**Tech Stack:** Terraform, AWS (EKS/RDS/MSK/Redis/OpenSearch), Kustomize, ArgoCD, kubectl, git

**Repos:**
- `synapse-gitops`: `C:\workspace\team-project-manager\team-project-final\synapse-gitops`
- `synapse-shared`: `C:\workspace\team-project-manager\team-project-final\synapse-shared`

---

## Task 1: Infrastructure Bootstrap (terraform apply)

**Files:**
- Working dir: `infra/aws/dev/`

- [ ] **Step 1: Initialize and apply terraform**

```powershell
cd C:\workspace\team-project-manager\team-project-final\synapse-gitops\infra\aws\dev
terraform init
terraform apply -auto-approve
```

Expected: ~15-20 min. Creates EKS, RDS, MSK, Redis, OpenSearch, Bastion, ArgoCD.

- [ ] **Step 2: Capture new resource endpoints**

```powershell
terraform output -json
```

Record these values (they change on each apply):
- `bastion_instance_id` — needed for SSM
- `rds_endpoint` — needed for ConfigMap updates
- `redis_endpoint` — needed for ConfigMap updates
- `msk_bootstrap_brokers_tls` — needed for ConfigMap updates
- `opensearch_endpoint` — needed for ConfigMap updates

- [ ] **Step 3: Verify Bastion SSM access**

```powershell
$env:PATH += ";C:\Program Files\Amazon\SessionManagerPlugin\bin"
aws ssm start-session --target <bastion_instance_id> --region ap-northeast-2
```

Once on bastion:
```bash
kubectl get nodes
# Expected: 3 nodes in Ready state
```

- [ ] **Step 4: Verify ArgoCD is running**

On bastion:
```bash
kubectl get pods -n argocd
# Expected: argocd-server, argocd-repo-server, argocd-application-controller all Running

# Get ArgoCD admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

- [ ] **Step 5: Apply ArgoCD project and ApplicationSet**

On bastion:
```bash
kubectl apply -f https://raw.githubusercontent.com/team-project-final/synapse-gitops/main/argocd/projects.yaml
kubectl apply -f https://raw.githubusercontent.com/team-project-final/synapse-gitops/main/argocd/applicationset.yaml
```

- [ ] **Step 6: Setup ESO (External Secrets Operator)**

On bastion:
```bash
# Install ESO via Helm
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace

# Wait for ESO pods
kubectl -n external-secrets get pods
# Expected: All Running

# Apply ClusterSecretStore
kubectl apply -f https://raw.githubusercontent.com/team-project-final/synapse-gitops/main/infra/external-secrets/cluster-secret-store.yaml
```

- [ ] **Step 7: Verify OIDC provider matches ESO IRSA**

On bastion:
```bash
# Check OIDC provider
aws eks describe-cluster --name synapse-dev --query "cluster.identity.oidc.issuer" --output text --region ap-northeast-2

# Compare with IAM OIDC providers
aws iam list-open-id-connect-providers --region ap-northeast-2
```

If mismatch: terraform created both, so they should match on fresh apply. If not, the OIDC thumbprint in `eks.tf` handles this automatically.

- [ ] **Step 8: Commit — record new endpoints**

Update ConfigMap endpoint values if they changed from previous apply. Check each service's `overlays/dev/kustomization.yaml` and update:
- `DATABASE_HOST` / `DB_URL` / `SPRING_DATASOURCE_URL`
- `REDIS_HOST`
- `KAFKA_BROKERS`
- `OPENSEARCH_URL`
- `LEARNING_AI_DATABASE_URL`

```bash
git add apps/*/overlays/dev/kustomization.yaml
git commit -m "fix(configmap): update dev overlay endpoints after fresh terraform apply"
```

---

## Task 2: Service Stabilization — Diagnose All CrashLoops

**Files:**
- No file changes — diagnostic only

- [ ] **Step 1: Check current application status**

On bastion:
```bash
kubectl get applications -n argocd
# Expected: 5 apps, some may be Progressing/Degraded
```

- [ ] **Step 2: Wait for ArgoCD sync and check pod status**

```bash
kubectl get pods -n synapse-dev
# Expected: 5 pods, knowledge-svc Running, others likely CrashLoopBackOff
```

- [ ] **Step 3: Collect crash logs for each failing service**

```bash
# platform-svc
kubectl logs -n synapse-dev deployment/platform-svc --tail=100

# engagement-svc
kubectl logs -n synapse-dev deployment/engagement-svc --tail=100

# learning-card
kubectl logs -n synapse-dev deployment/learning-card --tail=100

# learning-ai
kubectl logs -n synapse-dev deployment/learning-ai --tail=100
```

Record each error. Known issues from previous session:
- **platform-svc**: `mfa_credentials` table missing — Flyway migration or `ddl-auto: update`
- **engagement-svc**: Flyway completes, then crashes — app config issue
- **learning-card**: Tomcat starts, then crashes — app config issue
- **learning-ai**: health check or DB connection — Python uvicorn issue

- [ ] **Step 4: Verify ExternalSecrets are synced**

```bash
kubectl get externalsecrets -n synapse-dev
# Expected: 5 ExternalSecrets with status SecretSynced

kubectl get secrets -n synapse-dev
# Expected: 5 secrets (platform-svc-secret, engagement-svc-secret, etc.)
```

If ExternalSecrets fail: check ClusterSecretStore status and IRSA configuration.

- [ ] **Step 5: Verify infrastructure connectivity from pods**

```bash
# Test RDS connectivity
kubectl run -n synapse-dev pg-test --rm -it --image=postgres:16 -- \
  psql "postgresql://synapse_admin:<password>@<rds_endpoint>:5432/synapse" -c "SELECT 1"

# Test Redis connectivity
kubectl run -n synapse-dev redis-test --rm -it --image=redis:7-alpine -- \
  redis-cli -h <redis_endpoint> -p 6379 --tls PING
```

---

## Task 3: Service Stabilization — Fix and Redeploy

**Files:**
- Potentially modify: service repo code (synapse-platform-svc, etc.)
- Potentially modify: `apps/*/overlays/dev/kustomization.yaml` or `apps/*/base/configmap.yaml`

Note: Exact fixes depend on Step 2-3 diagnostic results. Below are the known fixes and the general workflow.

- [ ] **Step 1: Fix platform-svc (mfa_credentials table)**

Option A — Change ddl-auto in service repo (`synapse-platform-svc`):
```yaml
# application-dev.yml
spring:
  jpa:
    hibernate:
      ddl-auto: update
```

Option B — Add Flyway migration in service repo.

After fix: build and push to ECR.

```powershell
# From synapse-platform-svc directory
docker build -t 963773969059.dkr.ecr.ap-northeast-2.amazonaws.com/synapse/platform-svc:dev-latest .
aws ecr get-login-password --region ap-northeast-2 | docker login --username AWS --password-stdin 963773969059.dkr.ecr.ap-northeast-2.amazonaws.com
docker push 963773969059.dkr.ecr.ap-northeast-2.amazonaws.com/synapse/platform-svc:dev-latest
```

- [ ] **Step 2: Fix engagement-svc**

Diagnose from logs (Step 2-3). Apply fix in service repo or ConfigMap, then:

```powershell
docker build -t 963773969059.dkr.ecr.ap-northeast-2.amazonaws.com/synapse/engagement-svc:dev-latest .
docker push 963773969059.dkr.ecr.ap-northeast-2.amazonaws.com/synapse/engagement-svc:dev-latest
```

- [ ] **Step 3: Fix learning-card**

Diagnose from logs. Apply fix, then:

```powershell
docker build -t 963773969059.dkr.ecr.ap-northeast-2.amazonaws.com/synapse/learning-card:dev-latest .
docker push 963773969059.dkr.ecr.ap-northeast-2.amazonaws.com/synapse/learning-card:dev-latest
```

- [ ] **Step 4: Fix learning-ai**

Diagnose from logs. Common Python issues: missing env var, asyncpg connection string format, health endpoint path.

```powershell
docker build -t 963773969059.dkr.ecr.ap-northeast-2.amazonaws.com/synapse/learning-ai:dev-latest .
docker push 963773969059.dkr.ecr.ap-northeast-2.amazonaws.com/synapse/learning-ai:dev-latest
```

- [ ] **Step 5: Trigger ArgoCD resync and verify**

On bastion:
```bash
# Restart deployments to pull new images
kubectl rollout restart deployment -n synapse-dev

# Wait and check
kubectl get pods -n synapse-dev -w
# Expected: All 5 pods Running and Ready

kubectl get applications -n argocd
# Expected: All 5 apps Synced / Healthy
```

- [ ] **Step 6: Commit any gitops changes**

If ConfigMap or overlay changes were made:
```bash
git add apps/
git commit -m "fix(configmap): service stabilization fixes for dev environment"
```

---

## Task 4: Terraform State Verification

**Files:**
- Working dir: `infra/aws/dev/`

- [ ] **Step 1: Run terraform plan**

```powershell
cd C:\workspace\team-project-manager\team-project-final\synapse-gitops\infra\aws\dev
terraform plan
```

Expected: `No changes.` or only expected drift (manual ArgoCD config, aws-auth ConfigMap, etc.)

- [ ] **Step 2: If SG drift detected, update vpc.tf**

The existing `vpc.tf` already has SG rules for RDS (5432), Redis (6379), MSK (9092/9094), OpenSearch (443) with `eks_nodes` SG as source. If additional rules were needed in previous session, add them now:

```hcl
# Example: if additional SG rule needed in vpc.tf
resource "aws_security_group_rule" "example_additional" {
  type                     = "ingress"
  from_port                = <port>
  to_port                  = <port>
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_nodes.id
  security_group_id        = aws_security_group.<target>.id
  description              = "<description>"
}
```

- [ ] **Step 3: Apply and re-verify**

```powershell
terraform apply -auto-approve
terraform plan
# Expected: No changes.
```

- [ ] **Step 4: Commit terraform changes**

```bash
git add infra/aws/dev/
git commit -m "fix(terraform): align SG rules with runtime requirements"
```

---

## Task 5: Create Staging Overlay — Directory Structure

**Files:**
- Create: `apps/platform-svc/overlays/staging/kustomization.yaml`
- Create: `apps/engagement-svc/overlays/staging/kustomization.yaml`
- Create: `apps/knowledge-svc/overlays/staging/kustomization.yaml`
- Create: `apps/learning-card/overlays/staging/kustomization.yaml`
- Create: `apps/learning-ai/overlays/staging/kustomization.yaml`

- [ ] **Step 1: Create platform-svc staging overlay**

Create `apps/platform-svc/overlays/staging/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

namespace: synapse-staging

patches:
  - target:
      kind: Deployment
      name: platform-svc
    patch: |
      - op: replace
        path: /spec/replicas
        value: 2
  - target:
      kind: ConfigMap
      name: platform-svc-config
    patch: |
      - op: replace
        path: /data/LOG_LEVEL
        value: "INFO"
      - op: replace
        path: /data/SPRING_PROFILES_ACTIVE
        value: "staging"
      - op: add
        path: /data/DATABASE_HOST
        value: "synapse-dev-postgres.c7emuq20mhyy.ap-northeast-2.rds.amazonaws.com"
      - op: add
        path: /data/DATABASE_PORT
        value: "5432"
      - op: add
        path: /data/DATABASE_NAME
        value: "synapse"
      - op: add
        path: /data/REDIS_HOST
        value: "master.synapse-dev-redis.v6lpdh.apn2.cache.amazonaws.com"
      - op: add
        path: /data/REDIS_PORT
        value: "6379"
      - op: add
        path: /data/KAFKA_BROKERS
        value: "b-1.synapsedevkafka.fark5c.c2.kafka.ap-northeast-2.amazonaws.com:9094,b-2.synapsedevkafka.fark5c.c2.kafka.ap-northeast-2.amazonaws.com:9094"
      - op: add
        path: /data/DB_URL
        value: "jdbc:postgresql://synapse-dev-postgres.c7emuq20mhyy.ap-northeast-2.rds.amazonaws.com:5432/synapse"
      - op: add
        path: /data/DB_USERNAME
        value: "synapse_admin"
  - target:
      kind: ExternalSecret
      name: platform-svc-external-secret
    patch: |
      - op: replace
        path: /spec/secretStoreRef/name
        value: "aws-secrets-manager"

images:
  - name: ghcr.io/team-project-final/synapse-platform-svc
    newName: 963773969059.dkr.ecr.ap-northeast-2.amazonaws.com/synapse/platform-svc
    newTag: dev-latest
```

- [ ] **Step 2: Create engagement-svc staging overlay**

Create `apps/engagement-svc/overlays/staging/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

namespace: synapse-staging

patches:
  - target:
      kind: Deployment
      name: engagement-svc
    patch: |
      - op: replace
        path: /spec/replicas
        value: 2
  - target:
      kind: ConfigMap
      name: engagement-svc-config
    patch: |
      - op: replace
        path: /data/LOG_LEVEL
        value: "INFO"
      - op: replace
        path: /data/SPRING_PROFILES_ACTIVE
        value: "staging"
      - op: add
        path: /data/DATABASE_HOST
        value: "synapse-dev-postgres.c7emuq20mhyy.ap-northeast-2.rds.amazonaws.com"
      - op: add
        path: /data/DATABASE_PORT
        value: "5432"
      - op: add
        path: /data/DATABASE_NAME
        value: "synapse"
      - op: add
        path: /data/REDIS_HOST
        value: "master.synapse-dev-redis.v6lpdh.apn2.cache.amazonaws.com"
      - op: add
        path: /data/REDIS_PORT
        value: "6379"
      - op: add
        path: /data/KAFKA_BROKERS
        value: "b-1.synapsedevkafka.fark5c.c2.kafka.ap-northeast-2.amazonaws.com:9094,b-2.synapsedevkafka.fark5c.c2.kafka.ap-northeast-2.amazonaws.com:9094"
      - op: add
        path: /data/SPRING_DATASOURCE_URL
        value: "jdbc:postgresql://synapse-dev-postgres.c7emuq20mhyy.ap-northeast-2.rds.amazonaws.com:5432/synapse"
      - op: add
        path: /data/SPRING_DATASOURCE_USERNAME
        value: "synapse_admin"
  - target:
      kind: ExternalSecret
      name: engagement-svc-external-secret
    patch: |
      - op: replace
        path: /spec/secretStoreRef/name
        value: "aws-secrets-manager"

images:
  - name: ghcr.io/team-project-final/synapse-engagement-svc
    newName: 963773969059.dkr.ecr.ap-northeast-2.amazonaws.com/synapse/engagement-svc
    newTag: dev-latest
```

- [ ] **Step 3: Create knowledge-svc staging overlay**

Create `apps/knowledge-svc/overlays/staging/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

namespace: synapse-staging

patches:
  - target:
      kind: Deployment
      name: knowledge-svc
    patch: |
      - op: replace
        path: /spec/replicas
        value: 2
  - target:
      kind: ConfigMap
      name: knowledge-svc-config
    patch: |
      - op: replace
        path: /data/LOG_LEVEL
        value: "INFO"
      - op: replace
        path: /data/SPRING_PROFILES_ACTIVE
        value: "staging"
      - op: add
        path: /data/DATABASE_HOST
        value: "synapse-dev-postgres.c7emuq20mhyy.ap-northeast-2.rds.amazonaws.com"
      - op: add
        path: /data/DATABASE_PORT
        value: "5432"
      - op: add
        path: /data/DATABASE_NAME
        value: "synapse"
      - op: add
        path: /data/KAFKA_BROKERS
        value: "b-1.synapsedevkafka.fark5c.c2.kafka.ap-northeast-2.amazonaws.com:9094,b-2.synapsedevkafka.fark5c.c2.kafka.ap-northeast-2.amazonaws.com:9094"
      - op: add
        path: /data/OPENSEARCH_URL
        value: "https://vpc-synapse-dev-qm5l2xdch6nfmkqanpmipou74a.ap-northeast-2.es.amazonaws.com"
      - op: add
        path: /data/SPRING_DATASOURCE_URL
        value: "jdbc:postgresql://synapse-dev-postgres.c7emuq20mhyy.ap-northeast-2.rds.amazonaws.com:5432/synapse"
      - op: add
        path: /data/SPRING_DATASOURCE_USERNAME
        value: "synapse_admin"
  - target:
      kind: ExternalSecret
      name: knowledge-svc-external-secret
    patch: |
      - op: replace
        path: /spec/secretStoreRef/name
        value: "aws-secrets-manager"

images:
  - name: ghcr.io/team-project-final/synapse-knowledge-svc
    newName: 963773969059.dkr.ecr.ap-northeast-2.amazonaws.com/synapse/knowledge-svc
    newTag: dev-latest
```

- [ ] **Step 4: Create learning-card staging overlay**

Create `apps/learning-card/overlays/staging/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

namespace: synapse-staging

patches:
  - target:
      kind: Deployment
      name: learning-card
    patch: |
      - op: replace
        path: /spec/replicas
        value: 2
  - target:
      kind: ConfigMap
      name: learning-card-config
    patch: |
      - op: replace
        path: /data/LOG_LEVEL
        value: "INFO"
      - op: replace
        path: /data/SPRING_PROFILES_ACTIVE
        value: "staging"
      - op: add
        path: /data/DATABASE_HOST
        value: "synapse-dev-postgres.c7emuq20mhyy.ap-northeast-2.rds.amazonaws.com"
      - op: add
        path: /data/DATABASE_PORT
        value: "5432"
      - op: add
        path: /data/DATABASE_NAME
        value: "synapse"
      - op: add
        path: /data/KAFKA_BROKERS
        value: "b-1.synapsedevkafka.fark5c.c2.kafka.ap-northeast-2.amazonaws.com:9094,b-2.synapsedevkafka.fark5c.c2.kafka.ap-northeast-2.amazonaws.com:9094"
      - op: add
        path: /data/SPRING_DATASOURCE_URL
        value: "jdbc:postgresql://synapse-dev-postgres.c7emuq20mhyy.ap-northeast-2.rds.amazonaws.com:5432/synapse"
      - op: add
        path: /data/SPRING_DATASOURCE_USERNAME
        value: "synapse_admin"
  - target:
      kind: ExternalSecret
      name: learning-card-external-secret
    patch: |
      - op: replace
        path: /spec/secretStoreRef/name
        value: "aws-secrets-manager"

images:
  - name: ghcr.io/team-project-final/synapse-learning-card
    newName: 963773969059.dkr.ecr.ap-northeast-2.amazonaws.com/synapse/learning-card
    newTag: dev-latest
```

- [ ] **Step 5: Create learning-ai staging overlay**

Create `apps/learning-ai/overlays/staging/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

namespace: synapse-staging

patches:
  - target:
      kind: Deployment
      name: learning-ai
    patch: |
      - op: replace
        path: /spec/replicas
        value: 2
  - target:
      kind: ConfigMap
      name: learning-ai-config
    patch: |
      - op: replace
        path: /data/LOG_LEVEL
        value: "INFO"
      - op: add
        path: /data/DATABASE_HOST
        value: "synapse-dev-postgres.c7emuq20mhyy.ap-northeast-2.rds.amazonaws.com"
      - op: add
        path: /data/DATABASE_PORT
        value: "5432"
      - op: add
        path: /data/DATABASE_NAME
        value: "synapse"
      - op: add
        path: /data/KAFKA_BROKERS
        value: "b-1.synapsedevkafka.fark5c.c2.kafka.ap-northeast-2.amazonaws.com:9094,b-2.synapsedevkafka.fark5c.c2.kafka.ap-northeast-2.amazonaws.com:9094"
      - op: add
        path: /data/OPENSEARCH_URL
        value: "https://vpc-synapse-dev-qm5l2xdch6nfmkqanpmipou74a.ap-northeast-2.es.amazonaws.com"
      - op: add
        path: /data/LEARNING_AI_DATABASE_URL
        value: "postgresql+asyncpg://synapse_admin@synapse-dev-postgres.c7emuq20mhyy.ap-northeast-2.rds.amazonaws.com:5432/synapse"
  - target:
      kind: ExternalSecret
      name: learning-ai-external-secret
    patch: |
      - op: replace
        path: /spec/secretStoreRef/name
        value: "aws-secrets-manager"

images:
  - name: ghcr.io/team-project-final/synapse-learning-ai
    newName: 963773969059.dkr.ecr.ap-northeast-2.amazonaws.com/synapse/learning-ai
    newTag: dev-latest
```

- [ ] **Step 6: Validate kustomize build for all staging overlays**

```bash
# Requires kustomize CLI
kustomize build apps/platform-svc/overlays/staging > /dev/null && echo "platform-svc OK"
kustomize build apps/engagement-svc/overlays/staging > /dev/null && echo "engagement-svc OK"
kustomize build apps/knowledge-svc/overlays/staging > /dev/null && echo "knowledge-svc OK"
kustomize build apps/learning-card/overlays/staging > /dev/null && echo "learning-card OK"
kustomize build apps/learning-ai/overlays/staging > /dev/null && echo "learning-ai OK"
```

Expected: All 5 print "OK" with no errors.

- [ ] **Step 7: Commit staging overlays**

```bash
git add apps/*/overlays/staging/
git commit -m "feat(staging): add staging overlay for all 5 services

Staging differs from dev:
- namespace: synapse-staging
- replicas: 2
- LOG_LEVEL: INFO
- SPRING_PROFILES_ACTIVE: staging
- Same infra endpoints (shared dev cluster)"
```

---

## Task 6: Update ApplicationSet for Staging

**Files:**
- Modify: `argocd/applicationset.yaml`

- [ ] **Step 1: Add staging to ApplicationSet generators**

Current `argocd/applicationset.yaml` has a matrix generator with only `dev` in the env list. Add `staging` with autoSync disabled.

Replace the ApplicationSet with a version that uses two generators — one for dev (auto sync) and one for staging (manual sync):

```yaml
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
                  autoSync: "true"
                - env: staging
                  autoSync: "false"
  template:
    metadata:
      name: "synapse-{{service}}-{{env}}"
      namespace: argocd
      labels:
        app.kubernetes.io/part-of: synapse
        app.kubernetes.io/component: "{{service}}"
        environment: "{{env}}"
      annotations:
        argocd-image-updater.argoproj.io/image-list: "app=963773969059.dkr.ecr.ap-northeast-2.amazonaws.com/synapse/{{service}}"
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

Note: ArgoCD ApplicationSet template doesn't support conditional syncPolicy per generator element directly. The `autoSync` parameter is stored but syncPolicy in template applies to all. For staging manual sync, we have two options:

**Option A (simpler):** Use a single ApplicationSet and manually disable auto-sync on staging apps after creation via ArgoCD UI/CLI.

**Option B (separate ApplicationSets):** Create a second ApplicationSet for staging with no automated syncPolicy.

Option B is cleaner. Create `argocd/applicationset-staging.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: synapse-apps-staging
  namespace: argocd
spec:
  generators:
    - list:
        elements:
          - service: platform-svc
          - service: engagement-svc
          - service: knowledge-svc
          - service: learning-card
          - service: learning-ai
  template:
    metadata:
      name: "synapse-{{service}}-staging"
      namespace: argocd
      labels:
        app.kubernetes.io/part-of: synapse
        app.kubernetes.io/component: "{{service}}"
        environment: staging
    spec:
      project: synapse
      source:
        repoURL: https://github.com/team-project-final/synapse-gitops.git
        targetRevision: main
        path: "apps/{{service}}/overlays/staging"
      destination:
        server: https://kubernetes.default.svc
        namespace: synapse-staging
      syncPolicy:
        syncOptions:
          - CreateNamespace=true
```

No `automated` block = manual sync only.

- [ ] **Step 2: Keep original applicationset.yaml for dev only (no changes needed)**

The existing `argocd/applicationset.yaml` already generates only dev apps. Leave it as-is.

- [ ] **Step 3: Apply staging ApplicationSet on bastion**

On bastion:
```bash
kubectl apply -f https://raw.githubusercontent.com/team-project-final/synapse-gitops/main/argocd/applicationset-staging.yaml

# Verify
kubectl get applications -n argocd
# Expected: 10 apps total (5 dev + 5 staging)
# Staging apps should be OutOfSync (manual sync required)
```

- [ ] **Step 4: Manual sync one staging app to verify**

On bastion:
```bash
# Sync one app to verify staging overlay works
argocd app sync synapse-platform-svc-staging

# Check status
argocd app get synapse-platform-svc-staging
kubectl get pods -n synapse-staging
```

- [ ] **Step 5: Commit**

```bash
git add argocd/applicationset-staging.yaml
git commit -m "feat(argocd): add staging ApplicationSet with manual sync policy"
```

---

## Task 7: Update gitops Handoff Document

**Files:**
- Modify: `docs/superpowers/HANDOFF_W2.md`

- [ ] **Step 1: Update HANDOFF_W2.md with current session results**

Update the following sections based on actual results:

1. **Header**: Bump to v7, update date to 2026-05-21
2. **Section 1 (세션별 완료 사항)**: Add 8차 세션 block with:
   - terraform re-apply
   - Service stabilization results (which services fixed, how)
   - staging overlay creation
   - Staging ApplicationSet
3. **Section 2 (서비스 상태)**: Update all 5 services to current status
4. **Section 3 (다음 세션 작업)**: Update to reflect staging is done, next is E2E + staging promo
5. **Section 4 (체크리스트)**: Check off completed items
6. **Section 7 (PR 현황)**: Add new PRs
7. **Section 9 (Bastion 접속 정보)**: Update Instance ID if changed

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/HANDOFF_W2.md
git commit -m "docs: handoff v7 — service stabilization + staging overlay"
```

---

## Task 8: Shared Repo — Branch Cleanup

**Files:**
- Working dir: `C:\workspace\team-project-manager\team-project-final\synapse-shared`

- [ ] **Step 1: Check branch merge status**

```bash
cd C:\workspace\team-project-manager\team-project-final\synapse-shared

# chore/w2w3-ops-prep: 5 commits ahead — ops scripts, guides, handoff updates
git log --oneline main..chore/w2w3-ops-prep

# feat/w2-kafka-schemas: 3 commits ahead — Gradle wrapper, Avro schemas
git log --oneline main..feat/w2-kafka-schemas
```

Check if PRs exist:
```bash
gh pr list --state all --head chore/w2w3-ops-prep
gh pr list --state all --head feat/w2-kafka-schemas
```

- [ ] **Step 2: Handle chore/w2w3-ops-prep**

This branch has PR #4 already merged. The local branch has 5 commits that were squash-merged.

```bash
git branch -D chore/w2w3-ops-prep
git push origin --delete chore/w2w3-ops-prep 2>/dev/null || echo "Remote already deleted"
```

- [ ] **Step 3: Handle feat/w2-kafka-schemas**

Check if PR exists and is merged:
```bash
gh pr list --state all --head feat/w2-kafka-schemas
```

If merged:
```bash
git branch -D feat/w2-kafka-schemas
git push origin --delete feat/w2-kafka-schemas 2>/dev/null || echo "Remote already deleted"
```

If NOT merged and content is needed: create PR first, then delete after merge.

- [ ] **Step 4: Prune stale remote refs**

```bash
git remote prune origin
git branch -a
# Expected: only main + remotes/origin/main (+ remotes/origin/dev if kept)
```

- [ ] **Step 5: Commit — no commit needed (branch operations only)**

---

## Task 9: Shared Repo — Update Handoff and Guides

**Files:**
- Modify: `docs/project-management/HANDOFF_2026-05-19.md` (in synapse-shared)
- Modify: `docs/guides/ARGOCD_DEPLOY_VERIFICATION.md` (in synapse-shared)
- Modify: `docs/guides/TEAM_CHECKLIST_W3.md` (in synapse-shared)

- [ ] **Step 1: Update HANDOFF document**

In `docs/project-management/HANDOFF_2026-05-19.md`, add a new section for 05-21 session:

```markdown
### 완료: 05-21 세션 (8차)

| 작업 | 상태 | PR |
|------|:----:|-----|
| terraform re-apply (인프라 재기동) | ✅ | — |
| 4개 서비스 CrashLoop 해결 (5/5 Healthy) | ✅ | [gitops#XX] |
| terraform state 검증 (plan clean) | ✅ | — |
| staging overlay 생성 (5개 서비스) | ✅ | [gitops#XX] |
| staging ApplicationSet 추가 | ✅ | [gitops#XX] |
| synapse-shared 브랜치 정리 | ✅ | — |
```

Update 미해결 항목:
- ~~staging 오버레이 미생성~~ → ✅ 완료
- Add: 팀원 Kafka 구현 완료 대기 (W3)

- [ ] **Step 2: Update ARGOCD_DEPLOY_VERIFICATION.md**

Update the staging section with actual namespace and verification commands:

Add after the existing staging section:
```markdown
### Staging 환경 현황 (2026-05-21 갱신)

staging overlay 생성 완료. ApplicationSet: `synapse-apps-staging` (수동 Sync).

```bash
# Staging 앱 상태 확인
kubectl get applications -n argocd -l environment=staging

# Staging 수동 Sync
argocd app sync synapse-<service>-staging

# Staging Pod 확인
kubectl get pods -n synapse-staging
```
```

- [ ] **Step 3: Update TEAM_CHECKLIST_W3.md**

Add a note about current infrastructure state:

```markdown
## 현재 인프라 상태 (2026-05-21 갱신)

- dev 환경: 5/5 서비스 Healthy
- staging 환경: overlay 생성 완료, 수동 Sync 대기
- Bastion Instance ID: `<new_instance_id>`
- ArgoCD 접속: SSM 포트 포워딩 → http://localhost:9090
```

- [ ] **Step 4: Commit**

```bash
cd C:\workspace\team-project-manager\team-project-final\synapse-shared
git add docs/
git commit -m "docs: update handoff + guides — 8차 세션 반영 (서비스 안정화 + staging)"
```

---

## Task 10: Cross-Repo Verification and W3 Plan

**Files:**
- No new files — verification only

- [ ] **Step 1: Cross-check handoff documents**

Verify these match between both repos:

| Item | gitops HANDOFF_W2.md | shared HANDOFF_2026-05-19.md |
|------|---------------------|------------------------------|
| Service status | 5/5 Healthy | 5/5 Healthy |
| Staging status | Created, manual sync | Created, manual sync |
| Bastion Instance ID | Same value | Same value |
| Next steps | E2E + staging promo | E2E + staging promo |

- [ ] **Step 2: Verify ArgoCD final state**

On bastion:
```bash
# Dev apps
kubectl get applications -n argocd -l environment=dev
# Expected: 5 apps, all Synced/Healthy

# Staging apps
kubectl get applications -n argocd -l environment=staging
# Expected: 5 apps, OutOfSync (manual sync pending)

# All pods
kubectl get pods -n synapse-dev
kubectl get pods -n synapse-staging
```

- [ ] **Step 3: Push all gitops changes**

```bash
cd C:\workspace\team-project-manager\team-project-final\synapse-gitops
git push origin main
```

- [ ] **Step 4: Push all shared changes**

```bash
cd C:\workspace\team-project-manager\team-project-final\synapse-shared
git push origin main
```

- [ ] **Step 5: Terraform destroy (cost management)**

```powershell
cd C:\workspace\team-project-manager\team-project-final\synapse-gitops\infra\aws\dev
terraform destroy -auto-approve
```

Expected: All resources destroyed. S3 state bucket + DynamoDB lock table are preserved (managed separately).

---

## Summary: Phase → Task Mapping

| Phase | Tasks | Description |
|-------|-------|-------------|
| Phase 0: 인프라 기동 | Task 1 | terraform apply + bastion + ArgoCD + ESO |
| Phase 1: 서비스 안정화 | Task 2, 3 | Diagnose CrashLoops + fix + redeploy |
| Phase 2: terraform 정리 | Task 4 | Verify plan clean, fix drift if any |
| Phase 3: staging overlay | Task 5, 6 | Create 5 overlays + staging ApplicationSet |
| Phase 4: shared 정비 | Task 8, 9 | Branch cleanup + docs update |
| Phase 5: 통합 검증 | Task 7, 10 | Handoff update + cross-verify + destroy |
