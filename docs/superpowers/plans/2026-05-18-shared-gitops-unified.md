# Shared W1/W2 + GitOps Phase 2 Unified Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete synapse-shared W1 (AWS infra + Docker Compose) and W2 (Kafka topics + Schema Registry), then transition synapse-gitops to EKS with fully populated ConfigMaps.

**Architecture:** AWS infra via existing terraform in synapse-gitops → Docker Compose already exists (add topic init + Schema BACKWARD) → Kafka topics + Avro schemas in synapse-shared → ConfigMap values flow into gitops overlays → EKS provider swap.

**Tech Stack:** Terraform, Docker Compose, Confluent Kafka/Schema Registry, Avro, Kustomize, ArgoCD, ESO, Helm

---

## File Structure

### synapse-shared — new files

```
src/main/avro/knowledge/NoteCreated.avsc
src/main/avro/knowledge/NoteUpdated.avsc
src/main/avro/learning/ReviewCompleted.avsc
src/main/avro/learning/CardsGenerated.avsc
scripts/create-kafka-topics.sh
```

### synapse-shared — modify

```
docs/project-management/history/HISTORY_team-lead.md    # W1/W2 progress
```

### synapse-gitops — new files

```
scripts/kafka-init/create-topics.sh                      # Docker Compose init script
```

### synapse-gitops — modify

```
docker-compose.yml                                       # Add kafka-init + schema-registry BACKWARD
apps/platform-svc/base/configmap.yaml                    # Add Kafka env vars
apps/engagement-svc/base/configmap.yaml                  # Add Kafka env vars
apps/knowledge-svc/base/configmap.yaml                   # Add Kafka + OpenSearch + Schema Registry
apps/learning-card/base/configmap.yaml                   # Add Kafka env vars
apps/learning-ai/base/configmap.yaml                     # Add Kafka env vars
apps/*/overlays/dev/kustomization.yaml                   # Swap to ECR + aws-secrets-manager
argocd/applicationset.yaml                               # Swap image-list to ECR
docs/project-management/history/HISTORY_gitops.md        # EKS transition results
docs/project-management/task/TASK_gitops.md              # Step 4/5/6 → Done
```

---

## Task 1: Install aws CLI + terraform (user action)

- [ ] **Step 1: Install tools**

Run (PowerShell admin):
```powershell
choco install awscli terraform -y
```

- [ ] **Step 2: Verify**

Run:
```bash
aws --version
terraform version
```
Expected: `aws-cli/2.x`, `Terraform v1.x`

- [ ] **Step 3: Configure AWS credentials**

Run:
```bash
aws configure
# Access Key ID: <from 1Password or IAM console>
# Secret Access Key: <from 1Password or IAM console>
# region: ap-northeast-2
# output: json
```

- [ ] **Step 4: Verify identity**

Run:
```bash
aws sts get-caller-identity
```
Expected: `"Arn": "arn:aws:iam::<ACCOUNT>:user/synapse-admin"`

---

## Task 2: AWS infra provisioning — terraform apply (user action)

Follow existing runbooks sequentially. This task documents the exact flow.

**Repo:** synapse-gitops

- [ ] **Step 1: Create state backend (if not exists)**

Run:
```bash
aws s3api head-bucket --bucket synapse-terraform-state 2>/dev/null \
  && echo "Bucket exists" \
  || aws s3api create-bucket --bucket synapse-terraform-state \
       --region ap-northeast-2 \
       --create-bucket-configuration LocationConstraint=ap-northeast-2

aws dynamodb describe-table --table-name synapse-terraform-locks --region ap-northeast-2 2>/dev/null \
  && echo "Table exists" \
  || aws dynamodb create-table --table-name synapse-terraform-locks \
       --attribute-definitions AttributeName=LockID,AttributeType=S \
       --key-schema AttributeName=LockID,KeyType=HASH \
       --billing-mode PAY_PER_REQUEST --region ap-northeast-2
```

- [ ] **Step 2: Create terraform.tfvars**

Run:
```bash
cp infra/aws/dev/terraform.tfvars.example infra/aws/dev/terraform.tfvars
```
Edit `terraform.tfvars` with actual passwords. See `docs/runbooks/step2-terraform-tfvars.md`.

- [ ] **Step 3: Terraform init + plan + apply**

Run:
```bash
cd infra/aws/dev
terraform init
terraform plan
terraform apply
```
Expected: ~25-45 min. All resources created. See `docs/runbooks/step3-terraform-apply.md` for troubleshooting.

- [ ] **Step 4: Configure kubeconfig**

Run:
```bash
aws eks update-kubeconfig --name synapse-dev --region ap-northeast-2
kubectl get nodes
```
Expected: Nodes in Ready state.

- [ ] **Step 5: Collect endpoints**

Run:
```bash
# RDS
aws rds describe-db-instances --query 'DBInstances[0].Endpoint.Address' --output text

# ElastiCache Redis
aws elasticache describe-cache-clusters --show-cache-node-info \
  --query 'CacheClusters[0].CacheNodes[0].Endpoint.Address' --output text

# MSK Kafka brokers
aws kafka list-clusters-v2 --query 'ClusterInfoList[0].ClusterArn' --output text
# then:
aws kafka get-bootstrap-brokers --cluster-arn <ARN> --query 'BootstrapBrokerStringSaslIam' --output text

# OpenSearch
aws opensearch describe-domain --domain-name synapse-dev \
  --query 'DomainStatus.Endpoint' --output text
```

Save these values — they go into gitops ConfigMaps in Task 7.

- [ ] **Step 6: Record in shared HISTORY**

No commit yet — will batch with other shared updates in Task 5.

---

## Task 3: Docker Compose — add Kafka topic init + Schema Registry BACKWARD

**Repo:** synapse-gitops (docker-compose.yml already exists and is complete)

The existing docker-compose.yml has all 5 app services + infra. Two additions needed:
1. Kafka topic auto-creation init container
2. Schema Registry BACKWARD compatibility setting

- [ ] **Step 1: Create Kafka topic init script**

```bash
#!/usr/bin/env bash
# scripts/kafka-init/create-topics.sh
# Auto-create Kafka topics for local development.
# Called by docker-compose kafka-init service.
set -euo pipefail

BROKER="${KAFKA_BROKER:-kafka:9092}"
TOPICS=(
  "platform.auth.user-registered-v1"
  "knowledge.note.note-created-v1"
  "knowledge.note.note-updated-v1"
  "learning.card.review-completed-v1"
  "learning.ai.cards-generated-v1"
)

echo "Waiting for Kafka to be ready..."
cub kafka-ready -b "$BROKER" 1 60

for topic in "${TOPICS[@]}"; do
  echo "Creating topic: $topic"
  kafka-topics --bootstrap-server "$BROKER" \
    --create --if-not-exists \
    --topic "$topic" \
    --partitions 3 \
    --replication-factor 1 \
    --config retention.ms=604800000 \
    --config cleanup.policy=delete
done

echo "All topics created:"
kafka-topics --bootstrap-server "$BROKER" --list
```

Create file at `scripts/kafka-init/create-topics.sh`.

- [ ] **Step 2: Add kafka-init service + schema-registry BACKWARD to docker-compose.yml**

Add after the `schema-registry` service in `docker-compose.yml`:

```yaml
  kafka-init:
    image: confluentinc/cp-kafka:7.6.1
    container_name: synapse-kafka-init
    platform: linux/amd64
    depends_on:
      kafka:
        condition: service_healthy
    volumes:
      - ./scripts/kafka-init:/scripts
    command: ["bash", "/scripts/create-topics.sh"]
    environment:
      KAFKA_BROKER: kafka:9092
    networks:
      - synapse-net
    restart: "no"
```

Also add `SCHEMA_REGISTRY_SCHEMA_COMPATIBILITY_LEVEL: BACKWARD` to the schema-registry service environment.

- [ ] **Step 3: Verify locally**

Run:
```bash
docker compose up -d postgres redis zookeeper kafka schema-registry kafka-init
docker compose logs kafka-init
```
Expected: "All topics created:" followed by 5 topic names.

Run:
```bash
curl -s http://localhost:8081/config | jq .
```
Expected: `{"compatibilityLevel":"BACKWARD"}`

- [ ] **Step 4: Commit**

```bash
git add scripts/kafka-init/create-topics.sh docker-compose.yml
git commit -m "feat(compose): add Kafka topic init + Schema Registry BACKWARD policy"
```

---

## Task 4: Avro schemas in synapse-shared

**Repo:** synapse-shared (clone separately)

- [ ] **Step 1: Clone synapse-shared**

Run:
```bash
cd /c/workspace/team-project-manager/team-project-final
gh repo clone team-project-final/synapse-shared
cd synapse-shared
git checkout -b feat/w2-kafka-schemas
```

- [ ] **Step 2: Create NoteCreated.avsc**

```json
{
  "type": "record",
  "name": "NoteCreated",
  "namespace": "com.synapse.knowledge",
  "doc": "Emitted when a new note is created.",
  "fields": [
    {"name": "noteId", "type": "string", "doc": "UUID of the created note"},
    {"name": "userId", "type": "string", "doc": "UUID of the note author"},
    {"name": "tenantId", "type": "string", "doc": "Tenant identifier"},
    {"name": "title", "type": "string", "doc": "Note title"},
    {"name": "createdAt", "type": "string", "doc": "ISO-8601 creation timestamp"}
  ]
}
```

Create at `src/main/avro/knowledge/NoteCreated.avsc`.

- [ ] **Step 3: Create NoteUpdated.avsc**

```json
{
  "type": "record",
  "name": "NoteUpdated",
  "namespace": "com.synapse.knowledge",
  "doc": "Emitted when a note is updated.",
  "fields": [
    {"name": "noteId", "type": "string", "doc": "UUID of the updated note"},
    {"name": "userId", "type": "string", "doc": "UUID of the note author"},
    {"name": "tenantId", "type": "string", "doc": "Tenant identifier"},
    {"name": "title", "type": "string", "doc": "Note title"},
    {"name": "updatedAt", "type": "string", "doc": "ISO-8601 update timestamp"}
  ]
}
```

Create at `src/main/avro/knowledge/NoteUpdated.avsc`.

- [ ] **Step 4: Create ReviewCompleted.avsc**

```json
{
  "type": "record",
  "name": "ReviewCompleted",
  "namespace": "com.synapse.learning",
  "doc": "Emitted when a user completes a flashcard review.",
  "fields": [
    {"name": "cardId", "type": "string", "doc": "UUID of the reviewed card"},
    {"name": "userId", "type": "string", "doc": "UUID of the reviewer"},
    {"name": "tenantId", "type": "string", "doc": "Tenant identifier"},
    {"name": "rating", "type": {"type": "enum", "name": "Rating", "symbols": ["AGAIN", "HARD", "GOOD", "EASY"]}, "doc": "User's difficulty rating"},
    {"name": "nextReviewAt", "type": "string", "doc": "ISO-8601 next review date from SM-2"},
    {"name": "reviewedAt", "type": "string", "doc": "ISO-8601 review timestamp"}
  ]
}
```

Create at `src/main/avro/learning/ReviewCompleted.avsc`.

- [ ] **Step 5: Create CardsGenerated.avsc**

```json
{
  "type": "record",
  "name": "CardsGenerated",
  "namespace": "com.synapse.learning",
  "doc": "Emitted when AI generates flashcards from a note.",
  "fields": [
    {"name": "noteId", "type": "string", "doc": "Source note UUID"},
    {"name": "userId", "type": "string", "doc": "UUID of the requesting user"},
    {"name": "tenantId", "type": "string", "doc": "Tenant identifier"},
    {"name": "cardCount", "type": "int", "doc": "Number of cards generated"},
    {"name": "generatedAt", "type": "string", "doc": "ISO-8601 generation timestamp"}
  ]
}
```

Create at `src/main/avro/learning/CardsGenerated.avsc`.

- [ ] **Step 6: Verify Avro compilation**

Run:
```bash
./gradlew clean build --no-daemon
```
Expected: BUILD SUCCESSFUL. Generated Java classes for all 4 new schemas.

- [ ] **Step 7: Create MSK topic creation script**

```bash
#!/usr/bin/env bash
# scripts/create-kafka-topics.sh
# Create Kafka topics on MSK cluster.
# Usage: KAFKA_BROKERS=<broker-list> bash scripts/create-kafka-topics.sh
set -euo pipefail

BROKER="${KAFKA_BROKERS:?Set KAFKA_BROKERS env var}"
REPLICATION="${REPLICATION_FACTOR:-3}"
TOPICS=(
  "platform.auth.user-registered-v1"
  "knowledge.note.note-created-v1"
  "knowledge.note.note-updated-v1"
  "learning.card.review-completed-v1"
  "learning.ai.cards-generated-v1"
)

for topic in "${TOPICS[@]}"; do
  echo "Creating topic: $topic"
  kafka-topics.sh --bootstrap-server "$BROKER" \
    --create --if-not-exists \
    --topic "$topic" \
    --partitions 3 \
    --replication-factor "$REPLICATION" \
    --config retention.ms=604800000 \
    --config cleanup.policy=delete
done

echo "Topics:"
kafka-topics.sh --bootstrap-server "$BROKER" --list
```

Create at `scripts/create-kafka-topics.sh`.

- [ ] **Step 8: Commit + push + PR**

```bash
git add src/main/avro/ scripts/create-kafka-topics.sh
git commit -m "feat(schema): add NoteCreated, NoteUpdated, ReviewCompleted, CardsGenerated Avro schemas + topic creation script"
git push -u origin feat/w2-kafka-schemas
gh pr create --title "feat(w2): Kafka Avro schemas + topic creation script" \
  --body "W2 Step 4: 4 new Avro schemas + MSK topic creation script for 5 topics"
```

---

## Task 5: synapse-shared HISTORY update + W1 closure

**Repo:** synapse-shared

- [ ] **Step 1: Update HISTORY_team-lead.md W1 section**

In `docs/project-management/history/HISTORY_team-lead.md`, update the W1 dashboard:

```markdown
| Step | 내용 | 상태 | 시작일 | 완료일 | 비고 |
|------|------|------|--------|--------|------|
| Step 1 | AWS 인프라 프로비저닝 | Done | 2026-05-19 | 2026-05-19 | gitops terraform apply |
| Step 2 | Docker Compose 4-서비스 구성 | Done | 2026-05-19 | 2026-05-19 | 기존 docker-compose.yml 보강 |
| Step 3 | CI/CD 파이프라인 구성 | Done | 2026-05-12 | 2026-05-16 | ci-java + mirror + schema-check 완성 |
```

And W2 dashboard:

```markdown
| Step | 내용 | 상태 | 시작일 | 완료일 | 비고 |
|------|------|------|--------|--------|------|
| Step 4 | Kafka 토픽 설계 | Done | 2026-05-20 | 2026-05-20 | 5 topics + Avro schemas |
| Step 5 | Schema Registry 구성 | Done | 2026-05-21 | 2026-05-21 | BACKWARD policy |
| Step 6 | Gateway 라우팅 | Not Started | — | — | W3 이월 |
```

Add work log entries under each day.

- [ ] **Step 2: Commit + push**

```bash
git add docs/project-management/history/HISTORY_team-lead.md
git commit -m "docs(pm): update W1/W2 HISTORY with infra + kafka + schema progress"
git push origin feat/w2-kafka-schemas
```

---

## Task 6: Schema Registry BACKWARD verification (user action)

**Repo:** synapse-gitops (Docker Compose)

- [ ] **Step 1: Start infra stack**

Run:
```bash
docker compose up -d postgres redis zookeeper kafka schema-registry kafka-init
```

- [ ] **Step 2: Verify BACKWARD policy**

Run:
```bash
curl -s http://localhost:8081/config | jq .
```
Expected: `{"compatibilityLevel":"BACKWARD"}`

- [ ] **Step 3: Register a test schema**

Run:
```bash
curl -s -X POST http://localhost:8081/subjects/platform.auth.user-registered-v1-value/versions \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  -d '{"schema": "{\"type\":\"record\",\"name\":\"UserRegistered\",\"namespace\":\"com.synapse.platform\",\"fields\":[{\"name\":\"userId\",\"type\":\"string\"},{\"name\":\"email\",\"type\":\"string\"},{\"name\":\"tenantId\",\"type\":\"string\"},{\"name\":\"registeredAt\",\"type\":\"string\"}]}"}'
```
Expected: `{"id":1}`

- [ ] **Step 4: Verify backward-incompatible change is rejected**

Run:
```bash
curl -s -X POST http://localhost:8081/compatibility/subjects/platform.auth.user-registered-v1-value/versions/latest \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  -d '{"schema": "{\"type\":\"record\",\"name\":\"UserRegistered\",\"namespace\":\"com.synapse.platform\",\"fields\":[{\"name\":\"userId\",\"type\":\"string\"}]}"}'
```
Expected: `{"is_compatible":false}` (removed required fields)

- [ ] **Step 5: Tear down**

Run:
```bash
docker compose down
```

---

## Task 7: gitops ConfigMap update with real values

**Repo:** synapse-gitops

After Task 2 (endpoints collected) and Task 4 (topics confirmed), update the base ConfigMaps with real infrastructure values.

- [ ] **Step 1: Update platform-svc ConfigMap**

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
  KAFKA_TOPIC_USER_REGISTERED: "platform.auth.user-registered-v1"
```

- [ ] **Step 2: Update engagement-svc ConfigMap**

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

- [ ] **Step 3: Update knowledge-svc ConfigMap**

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
  KAFKA_TOPIC_NOTE_CREATED: "knowledge.note.note-created-v1"
  KAFKA_TOPIC_NOTE_UPDATED: "knowledge.note.note-updated-v1"
```

- [ ] **Step 4: Update learning-card ConfigMap**

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
  KAFKA_TOPIC_REVIEW_COMPLETED: "learning.card.review-completed-v1"
```

- [ ] **Step 5: Update learning-ai ConfigMap**

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
  KAFKA_TOPIC_CARDS_GENERATED: "learning.ai.cards-generated-v1"
```

- [ ] **Step 6: Add infra endpoints to dev overlay patches**

For each of the 5 apps' `overlays/dev/kustomization.yaml`, add infrastructure endpoint patches. Example for platform-svc — add to the ConfigMap patch:

```yaml
      - op: add
        path: /data/KAFKA_BROKERS
        value: "<MSK_BROKER_ENDPOINT>"
      - op: add
        path: /data/DATABASE_HOST
        value: "<RDS_ENDPOINT>"
      - op: add
        path: /data/REDIS_HOST
        value: "<ELASTICACHE_ENDPOINT>"
```

Replace `<MSK_BROKER_ENDPOINT>`, `<RDS_ENDPOINT>`, `<ELASTICACHE_ENDPOINT>` with values from Task 2 Step 5.

Similar for knowledge-svc (add `OPENSEARCH_URL`, `SCHEMA_REGISTRY_URL`), learning-ai (add `DATABASE_HOST`), etc.

- [ ] **Step 7: Verify kustomize build**

Run:
```bash
for app in platform-svc engagement-svc knowledge-svc learning-card learning-ai; do
  echo "=== $app ==="
  kubectl kustomize "apps/$app/overlays/dev" > /dev/null 2>&1 && echo "OK" || echo "FAIL"
done
```
Expected: All 5 print "OK".

- [ ] **Step 8: Commit**

```bash
git add apps/*/base/configmap.yaml apps/*/overlays/dev/kustomization.yaml
git commit -m "feat(apps): add Kafka topic + infra endpoint env vars to ConfigMaps"
```

---

## Task 8: EKS provider swap + deploy

**Repo:** synapse-gitops

Follow `docs/runbooks/w2-eks-transition.md` sections 3-4.

- [ ] **Step 1: Swap ExternalSecret secretStoreRef (5 overlays)**

Run:
```bash
for app in platform-svc engagement-svc knowledge-svc learning-card learning-ai; do
  sed -i 's/value: fake-secrets/value: aws-secrets-manager/g' \
    "apps/$app/overlays/dev/kustomization.yaml"
done
```

- [ ] **Step 2: Swap image paths to ECR (5 overlays)**

Run:
```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
for app in platform-svc engagement-svc knowledge-svc learning-card learning-ai; do
  sed -i "s|newName: localhost:5001/synapse/$app|newName: ${ACCOUNT_ID}.dkr.ecr.ap-northeast-2.amazonaws.com/synapse/$app|g" \
    "apps/$app/overlays/dev/kustomization.yaml"
  sed -i 's|newTag: "1.0.0"|newTag: dev-latest|g' \
    "apps/$app/overlays/dev/kustomization.yaml"
done
```

- [ ] **Step 3: Swap ApplicationSet annotation to ECR**

Run:
```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
sed -i "s|localhost:5001/synapse|${ACCOUNT_ID}.dkr.ecr.ap-northeast-2.amazonaws.com/synapse|g" \
  argocd/applicationset.yaml
```

- [ ] **Step 4: Setup ESO with AWS provider**

Follow `docs/runbooks/w2-eks-transition.md` section 3 (IRSA + ClusterSecretStore + Secrets Manager secrets).

- [ ] **Step 5: Setup Image Updater with ECR**

Follow `docs/runbooks/w2-eks-transition.md` section 4 (IRSA + helm upgrade + Deploy Key).

- [ ] **Step 6: Apply ImageUpdater CR**

Run:
```bash
kubectl apply -f argocd/image-updater.yaml
```

- [ ] **Step 7: Verify all 5 apps**

Run:
```bash
argocd app list
kubectl get externalsecret -n synapse-dev
kubectl get pods -n synapse-dev
```
Expected: 5 apps Synced, ExternalSecrets SecretSynced, Pods Running (or ImagePullBackOff if ECR images not yet pushed by svc teams).

- [ ] **Step 8: Commit**

```bash
git add apps/ argocd/
git commit -m "feat: swap kind providers to AWS (ESO + ECR) for EKS"
```

---

## Task 9: PRD W2 verification + documentation

**Repo:** synapse-gitops

- [ ] **Step 1: Run PRD checklist**

Run:
```bash
# FR-GO-201
argocd app list

# FR-GO-203
gitleaks detect --source . --no-git --verbose 2>&1 | tail -5

# FR-GO-204
kubectl get externalsecret -n synapse-dev
```

- [ ] **Step 2: Update HISTORY with EKS results**

In `docs/project-management/history/HISTORY_gitops.md`, replace `(EKS 전환 결과를 여기에 기록)` with actual results.

- [ ] **Step 3: Update TASK status to Done**

In `docs/project-management/task/TASK_gitops.md`, change Step 4/5/6 status from `[x] In Progress` to `[x] Done`.

- [ ] **Step 4: Commit + push**

```bash
git add docs/
git commit -m "docs(pm): finalize W2 — HISTORY EKS results + TASK Done"
git push origin feat/w2-dev-deploy
```

---

## Task 10: Clean up kind cluster (user action)

- [ ] **Step 1: Delete kind cluster**

Run:
```bash
kind delete cluster --name synapse-w2
```

- [ ] **Step 2: Stop local registry**

Run:
```bash
docker rm -f kind-registry 2>/dev/null
```

- [ ] **Step 3: Verify**

Run:
```bash
kind get clusters
docker ps | grep registry
```
Expected: No clusters, no registry container.
