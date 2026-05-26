# 로컬 k8s(minikube) 실행 경로 구현 계획 (B)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `local-k8s/` 신규 kustomize(인클러스터 인프라 + 5개 앱 로컬 overlay) + `scripts/minikube-up.sh` + `local-msa-setup.html` §9 부록으로, minikube에서 Synapse MSA를 파드로 띄우는 동작 경로를 만든다.

**Architecture:** EKS용 `apps/<svc>/base`를 재사용하되 로컬 overlay에서 ExternalSecret 삭제·ConfigMap 인프라 호스트를 인클러스터 DNS로·이미지를 로컬 태그로 바꾼다. 인프라(postgres/redis/zookeeper/kafka/opensearch)는 단일 replica Deployment+Service로 클러스터에 함께 배포. 정적 검증은 `kubectl kustomize`, 런타임은 best-effort 스크립트.

**Tech Stack:** Kustomize, Kubernetes, minikube, bash. 검증: `kubectl kustomize`(클러스터 불필요).

**스펙:** `docs/superpowers/specs/2026-05-26-local-k8s-minikube-design.md`

---

## 검증된 사실 (이 값만 사용 — 실제 파일로 확인 완료)

- **ArgoCD 안전**: ApplicationSet은 `{service}×{env: dev/staging/prod}` 명시 list → `local-k8s/`는 동기화 대상 아님.
- **base 이미지**(images 매치 키): `ghcr.io/team-project-final/synapse-<svc>` (5개 동일 패턴: platform-svc, engagement-svc, knowledge-svc, learning-card, learning-ai).
- **secretRef 이름**: `<svc>-secret` (platform-svc-secret, engagement-svc-secret, knowledge-svc-secret, learning-card-secret, learning-ai-secret). deployment의 secretRef는 `optional: true`.
- **컨테이너 포트**: Spring 4개=8080, learning-ai=8090. base Service는 모두 `port:80 → targetPort:(위)`.
- **base configmap에 DATABASE_HOST 없음** → ConfigMap은 strategic-merge로 키 추가/병합.
- **서비스별 dev ConfigMap 인프라 키 / ExternalSecret secretKey:**

| svc | ConfigMap 인프라 키(로컬값으로 설정) | Secret 키(더미값) |
|---|---|---|
| platform-svc | DATABASE_HOST, DATABASE_PORT, DATABASE_NAME, DB_URL, DB_USERNAME, REDIS_HOST, REDIS_PORT, KAFKA_BROKERS | DB_PASSWORD, JWT_SECRET, AES_SECRET_KEY, JWT_PRIVATE_KEY, JWT_PUBLIC_KEY, STRIPE_API_KEY, STRIPE_WEBHOOK_SECRET, GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET, GITHUB_CLIENT_ID, GITHUB_CLIENT_SECRET, APPLE_CLIENT_ID, APPLE_CLIENT_SECRET |
| engagement-svc | DATABASE_HOST, DATABASE_PORT, DATABASE_NAME, SPRING_DATASOURCE_URL, SPRING_DATASOURCE_USERNAME, REDIS_HOST, REDIS_PORT, KAFKA_BROKERS | SPRING_DATASOURCE_PASSWORD |
| knowledge-svc | DATABASE_HOST, DATABASE_PORT, DATABASE_NAME, SPRING_DATASOURCE_URL, SPRING_DATASOURCE_USERNAME, KAFKA_BROKERS, OPENSEARCH_URL | SPRING_DATASOURCE_PASSWORD, S3_ACCESS_KEY |
| learning-card | DATABASE_HOST, DATABASE_PORT, DATABASE_NAME, SPRING_DATASOURCE_URL, SPRING_DATASOURCE_USERNAME, KAFKA_BROKERS | API_KEY, SPRING_DATASOURCE_PASSWORD |
| learning-ai | DATABASE_HOST, DATABASE_PORT, DATABASE_NAME, KAFKA_BROKERS, OPENSEARCH_URL, LEARNING_AI_DATABASE_URL | OPENAI_API_KEY, DATABASE_PASSWORD |

- **이미지 빌드(런타임 스크립트용)**: platform-svc/engagement-svc/knowledge-svc/learning-ai = `Dockerfile` 있음(`docker build`). **learning-card = Dockerfile 없음** → `./gradlew bootBuildImage`로 빌드.
  빌드 컨텍스트: `../synapse-<svc>`(Spring 3개), `../synapse-learning-svc/learning-ai`(learning-ai), `../synapse-learning-svc/learning-card`(learning-card).

### 로컬 공통 값
namespace `synapse-local` · DB host `postgres`:5432 db/user `synapse`/`synapse` pw `synapse_local` · Redis `redis`:6379 pw `redis_local` · Kafka `kafka:9092` · OpenSearch `http://opensearch:9200`.

---

## 파일 구조

```
local-k8s/
├── namespace.yaml
├── kustomization.yaml          # namespace + infra + secrets + apps/<5>, namespace: synapse-local
├── infra/{kustomization,postgres,redis,zookeeper,kafka,opensearch,kafka-topics-job}.yaml
├── secrets.yaml                # 5 Secret (---)
├── apps/<svc>/kustomization.yaml   # 5개
└── README.md
scripts/minikube-up.sh
docs/local-msa-setup.html        # §9 부록 추가 + 포인터
```

검증용: `kubectl kustomize <dir>`는 클러스터 없이 렌더만 — 모든 정적 검증에 사용.

---

## Task 1: 네임스페이스 + 인클러스터 인프라

**Files:** Create `local-k8s/namespace.yaml`, `local-k8s/infra/{postgres,redis,zookeeper,kafka,opensearch,kafka-topics-job,kustomization}.yaml`

- [ ] **Step 1: namespace.yaml**

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: synapse-local
```

- [ ] **Step 2: infra/postgres.yaml**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata: { name: postgres, labels: { app: postgres } }
spec:
  replicas: 1
  selector: { matchLabels: { app: postgres } }
  template:
    metadata: { labels: { app: postgres } }
    spec:
      containers:
        - name: postgres
          image: postgres:16-alpine
          env:
            - { name: POSTGRES_DB, value: synapse }
            - { name: POSTGRES_USER, value: synapse }
            - { name: POSTGRES_PASSWORD, value: synapse_local }
          ports: [ { containerPort: 5432 } ]
---
apiVersion: v1
kind: Service
metadata: { name: postgres }
spec:
  selector: { app: postgres }
  ports: [ { port: 5432, targetPort: 5432 } ]
```

- [ ] **Step 3: infra/redis.yaml**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata: { name: redis, labels: { app: redis } }
spec:
  replicas: 1
  selector: { matchLabels: { app: redis } }
  template:
    metadata: { labels: { app: redis } }
    spec:
      containers:
        - name: redis
          image: redis:7-alpine
          args: ["redis-server", "--requirepass", "redis_local"]
          ports: [ { containerPort: 6379 } ]
---
apiVersion: v1
kind: Service
metadata: { name: redis }
spec:
  selector: { app: redis }
  ports: [ { port: 6379, targetPort: 6379 } ]
```

- [ ] **Step 4: infra/zookeeper.yaml**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata: { name: zookeeper, labels: { app: zookeeper } }
spec:
  replicas: 1
  selector: { matchLabels: { app: zookeeper } }
  template:
    metadata: { labels: { app: zookeeper } }
    spec:
      containers:
        - name: zookeeper
          image: confluentinc/cp-zookeeper:7.7.0
          env:
            - { name: ZOOKEEPER_CLIENT_PORT, value: "2181" }
            - { name: ZOOKEEPER_TICK_TIME, value: "2000" }
          ports: [ { containerPort: 2181 } ]
---
apiVersion: v1
kind: Service
metadata: { name: zookeeper }
spec:
  selector: { app: zookeeper }
  ports: [ { port: 2181, targetPort: 2181 } ]
```

- [ ] **Step 5: infra/kafka.yaml**  (advertised=kafka:9092 → 인클러스터 연결 OK)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata: { name: kafka, labels: { app: kafka } }
spec:
  replicas: 1
  selector: { matchLabels: { app: kafka } }
  template:
    metadata: { labels: { app: kafka } }
    spec:
      containers:
        - name: kafka
          image: confluentinc/cp-kafka:7.7.0
          env:
            - { name: KAFKA_BROKER_ID, value: "1" }
            - { name: KAFKA_ZOOKEEPER_CONNECT, value: "zookeeper:2181" }
            - { name: KAFKA_LISTENER_SECURITY_PROTOCOL_MAP, value: "PLAINTEXT:PLAINTEXT" }
            - { name: KAFKA_LISTENERS, value: "PLAINTEXT://0.0.0.0:9092" }
            - { name: KAFKA_ADVERTISED_LISTENERS, value: "PLAINTEXT://kafka:9092" }
            - { name: KAFKA_INTER_BROKER_LISTENER_NAME, value: "PLAINTEXT" }
            - { name: KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR, value: "1" }
          ports: [ { containerPort: 9092 } ]
---
apiVersion: v1
kind: Service
metadata: { name: kafka }
spec:
  selector: { app: kafka }
  ports: [ { port: 9092, targetPort: 9092 } ]
```

- [ ] **Step 6: infra/opensearch.yaml**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata: { name: opensearch, labels: { app: opensearch } }
spec:
  replicas: 1
  selector: { matchLabels: { app: opensearch } }
  template:
    metadata: { labels: { app: opensearch } }
    spec:
      containers:
        - name: opensearch
          image: opensearchproject/opensearch:2.11.0
          env:
            - { name: discovery.type, value: single-node }
            - { name: plugins.security.disabled, value: "true" }
            - { name: OPENSEARCH_JAVA_OPTS, value: "-Xms256m -Xmx256m" }
            - { name: DISABLE_INSTALL_DEMO_CONFIG, value: "true" }
          ports: [ { containerPort: 9200 } ]
---
apiVersion: v1
kind: Service
metadata: { name: opensearch }
spec:
  selector: { app: opensearch }
  ports: [ { port: 9200, targetPort: 9200 } ]
```

- [ ] **Step 7: infra/kafka-topics-job.yaml**  (kafka 준비 대기 후 토픽 5개)

```yaml
apiVersion: batch/v1
kind: Job
metadata: { name: kafka-topics-init }
spec:
  backoffLimit: 10
  template:
    spec:
      restartPolicy: OnFailure
      containers:
        - name: create-topics
          image: confluentinc/cp-kafka:7.7.0
          command: ["/bin/bash","-c"]
          args:
            - |
              until kafka-topics --bootstrap-server kafka:9092 --list >/dev/null 2>&1; do echo "wait kafka..."; sleep 5; done
              for t in platform.auth.user-registered-v1 knowledge.note.note-created-v1 knowledge.note.note-updated-v1 learning.card.review-completed-v1 learning.ai.cards-generated-v1; do
                kafka-topics --bootstrap-server kafka:9092 --create --if-not-exists --topic "$t" --partitions 3 --replication-factor 1
              done
              kafka-topics --bootstrap-server kafka:9092 --list
```

- [ ] **Step 8: infra/kustomization.yaml**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - postgres.yaml
  - redis.yaml
  - zookeeper.yaml
  - kafka.yaml
  - opensearch.yaml
  - kafka-topics-job.yaml
```

- [ ] **Step 9: 정적 렌더 검증**

Run: `kubectl kustomize local-k8s/infra`
Expected: 에러 없이 6개 워크로드(Deployment×5 + Job) + Service×5 YAML 출력. `kubectl kustomize local-k8s/infra | grep -c 'kind: Service'` → 5.

- [ ] **Step 10: 커밋**

```bash
cd /c/workspace/team-project-final/synapse-gitops
git add local-k8s/namespace.yaml local-k8s/infra
git commit -m "feat(local-k8s): 인클러스터 인프라 매니페스트 (postgres/redis/kafka/opensearch/topics)"
```

---

## Task 2: 로컬 평문 Secret 5개

**Files:** Create `local-k8s/secrets.yaml`

- [ ] **Step 1: secrets.yaml** (로컬 더미값 — 커밋 안전)

```yaml
apiVersion: v1
kind: Secret
metadata: { name: platform-svc-secret }
type: Opaque
stringData:
  DB_PASSWORD: synapse_local
  JWT_SECRET: local-jwt-secret-must-be-at-least-256-bits-long-0000000000
  AES_SECRET_KEY: 0123456789abcdef0123456789abcdef
  JWT_PRIVATE_KEY: local-dummy
  JWT_PUBLIC_KEY: local-dummy
  STRIPE_API_KEY: sk_test_mock
  STRIPE_WEBHOOK_SECRET: whsec_mock
  GOOGLE_CLIENT_ID: mock
  GOOGLE_CLIENT_SECRET: mock
  GITHUB_CLIENT_ID: mock
  GITHUB_CLIENT_SECRET: mock
  APPLE_CLIENT_ID: mock
  APPLE_CLIENT_SECRET: mock
---
apiVersion: v1
kind: Secret
metadata: { name: engagement-svc-secret }
type: Opaque
stringData:
  SPRING_DATASOURCE_PASSWORD: synapse_local
---
apiVersion: v1
kind: Secret
metadata: { name: knowledge-svc-secret }
type: Opaque
stringData:
  SPRING_DATASOURCE_PASSWORD: synapse_local
  S3_ACCESS_KEY: mock
---
apiVersion: v1
kind: Secret
metadata: { name: learning-card-secret }
type: Opaque
stringData:
  API_KEY: mock
  SPRING_DATASOURCE_PASSWORD: synapse_local
---
apiVersion: v1
kind: Secret
metadata: { name: learning-ai-secret }
type: Opaque
stringData:
  OPENAI_API_KEY: sk-mock
  DATABASE_PASSWORD: synapse_local
```

- [ ] **Step 2: 검증** — `kubectl kustomize`로 직접 빌드 불가(단일 파일). 다음 명령으로 YAML 유효성 확인:
Run: `kubectl apply --dry-run=client -f local-k8s/secrets.yaml`
Expected: `secret/... created (dry run)` 5줄, 에러 0. (클러스터 연결 불필요한 client dry-run)

- [ ] **Step 3: 커밋**

```bash
git add local-k8s/secrets.yaml
git commit -m "feat(local-k8s): 로컬 평문 Secret 5개 (더미값)"
```

---

## Task 3: 앱 로컬 overlay 5개

**Files:** Create `local-k8s/apps/{platform-svc,engagement-svc,knowledge-svc,learning-card,learning-ai}/kustomization.yaml`

각 overlay는 base 참조 + ExternalSecret 삭제 + ConfigMap 인프라 키 병합 + 이미지 로컬 태그. (namespace는 Task 4의 top kustomization이 일괄 적용.)

- [ ] **Step 1: apps/platform-svc/kustomization.yaml**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../../apps/platform-svc/base
patches:
  - patch: |
      $patch: delete
      apiVersion: external-secrets.io/v1
      kind: ExternalSecret
      metadata:
        name: platform-svc-external-secret
  - patch: |
      apiVersion: v1
      kind: ConfigMap
      metadata:
        name: platform-svc-config
      data:
        DATABASE_HOST: postgres
        DATABASE_PORT: "5432"
        DATABASE_NAME: synapse
        DB_URL: jdbc:postgresql://postgres:5432/synapse
        DB_USERNAME: synapse
        REDIS_HOST: redis
        REDIS_PORT: "6379"
        KAFKA_BROKERS: kafka:9092
images:
  - name: ghcr.io/team-project-final/synapse-platform-svc
    newName: synapse-platform-svc
    newTag: local
```

- [ ] **Step 2: apps/engagement-svc/kustomization.yaml**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../../apps/engagement-svc/base
patches:
  - patch: |
      $patch: delete
      apiVersion: external-secrets.io/v1
      kind: ExternalSecret
      metadata:
        name: engagement-svc-external-secret
  - patch: |
      apiVersion: v1
      kind: ConfigMap
      metadata:
        name: engagement-svc-config
      data:
        DATABASE_HOST: postgres
        DATABASE_PORT: "5432"
        DATABASE_NAME: synapse
        SPRING_DATASOURCE_URL: jdbc:postgresql://postgres:5432/synapse
        SPRING_DATASOURCE_USERNAME: synapse
        REDIS_HOST: redis
        REDIS_PORT: "6379"
        KAFKA_BROKERS: kafka:9092
images:
  - name: ghcr.io/team-project-final/synapse-engagement-svc
    newName: synapse-engagement-svc
    newTag: local
```

> **주의**: ExternalSecret `metadata.name`은 base마다 다르다. engagement/knowledge/learning-card/learning-ai의 정확한 이름은 각 `apps/<svc>/base/externalsecret.yaml`의 `metadata.name`을 확인해 위 delete 패치에 사용한다(platform은 `platform-svc-external-secret` 확인됨). 패턴은 `<svc>-external-secret`로 보이나 실제 값으로 검증할 것.

- [ ] **Step 3: apps/knowledge-svc/kustomization.yaml**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../../apps/knowledge-svc/base
patches:
  - patch: |
      $patch: delete
      apiVersion: external-secrets.io/v1
      kind: ExternalSecret
      metadata:
        name: knowledge-svc-external-secret
  - patch: |
      apiVersion: v1
      kind: ConfigMap
      metadata:
        name: knowledge-svc-config
      data:
        DATABASE_HOST: postgres
        DATABASE_PORT: "5432"
        DATABASE_NAME: synapse
        SPRING_DATASOURCE_URL: jdbc:postgresql://postgres:5432/synapse
        SPRING_DATASOURCE_USERNAME: synapse
        KAFKA_BROKERS: kafka:9092
        OPENSEARCH_URL: http://opensearch:9200
images:
  - name: ghcr.io/team-project-final/synapse-knowledge-svc
    newName: synapse-knowledge-svc
    newTag: local
```

- [ ] **Step 4: apps/learning-card/kustomization.yaml**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../../apps/learning-card/base
patches:
  - patch: |
      $patch: delete
      apiVersion: external-secrets.io/v1
      kind: ExternalSecret
      metadata:
        name: learning-card-external-secret
  - patch: |
      apiVersion: v1
      kind: ConfigMap
      metadata:
        name: learning-card-config
      data:
        DATABASE_HOST: postgres
        DATABASE_PORT: "5432"
        DATABASE_NAME: synapse
        SPRING_DATASOURCE_URL: jdbc:postgresql://postgres:5432/synapse
        SPRING_DATASOURCE_USERNAME: synapse
        KAFKA_BROKERS: kafka:9092
images:
  - name: ghcr.io/team-project-final/synapse-learning-card
    newName: synapse-learning-card
    newTag: local
```

- [ ] **Step 5: apps/learning-ai/kustomization.yaml**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../../apps/learning-ai/base
patches:
  - patch: |
      $patch: delete
      apiVersion: external-secrets.io/v1
      kind: ExternalSecret
      metadata:
        name: learning-ai-external-secret
  - patch: |
      apiVersion: v1
      kind: ConfigMap
      metadata:
        name: learning-ai-config
      data:
        DATABASE_HOST: postgres
        DATABASE_PORT: "5432"
        DATABASE_NAME: synapse
        KAFKA_BROKERS: kafka:9092
        OPENSEARCH_URL: http://opensearch:9200
        LEARNING_AI_DATABASE_URL: postgresql://synapse:synapse_local@postgres:5432/synapse
images:
  - name: ghcr.io/team-project-final/synapse-learning-ai
    newName: synapse-learning-ai
    newTag: local
```

- [ ] **Step 6: 각 overlay 정적 검증 + ExternalSecret 제거 확인**

각 서비스에 대해:
Run: `kubectl kustomize local-k8s/apps/platform-svc`
Expected: Deployment/Service/ConfigMap 출력, **ExternalSecret 없음**, 이미지 `synapse-platform-svc:local`, ConfigMap에 `DATABASE_HOST: postgres`.
검증 명령: `kubectl kustomize local-k8s/apps/platform-svc | grep -E 'ExternalSecret|ghcr.io|amazonaws' | wc -l` → **0**.
5개 서비스 모두 동일하게 확인(이름만 교체).

> `$patch: delete`로 ExternalSecret이 제거되지 않으면(드묾), 대안: 해당 overlay에서 base 디렉터리 대신 base의 개별 리소스(`deployment.yaml`,`service.yaml`,`configmap.yaml`)만 `resources`에 나열한다.

- [ ] **Step 7: 커밋**

```bash
git add local-k8s/apps
git commit -m "feat(local-k8s): 앱 5개 로컬 overlay (ExternalSecret 제거·인프라 DNS·로컬 이미지)"
```

---

## Task 4: top-level kustomization + README

**Files:** Create `local-k8s/kustomization.yaml`, `local-k8s/README.md`

- [ ] **Step 1: local-k8s/kustomization.yaml**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: synapse-local
resources:
  - namespace.yaml
  - infra
  - secrets.yaml
  - apps/platform-svc
  - apps/engagement-svc
  - apps/knowledge-svc
  - apps/learning-card
  - apps/learning-ai
```

- [ ] **Step 2: local-k8s/README.md**

```markdown
# local-k8s — minikube로 Synapse MSA 띄우기

EKS용 `apps/`를 로컬용으로 적응한 자립형 kustomize. ArgoCD 동기화 대상 아님.

- 인프라(postgres/redis/kafka/opensearch)를 클러스터에 함께 배포(영속 없음, 단일 replica).
- 앱 5개는 `../apps/<svc>/base` 재사용 + 로컬 overlay(ExternalSecret 삭제·인프라 DNS·로컬 이미지 `synapse-<svc>:local`).
- 시크릿은 로컬 더미값(`secrets.yaml`).

## 빠른 시작
\`\`\`bash
bash scripts/minikube-up.sh
\`\`\`

## 정적 렌더 확인(클러스터 불필요)
\`\`\`bash
kubectl kustomize local-k8s
\`\`\`

자세한 절차/트러블슈팅: docs/local-msa-setup.html §9.
```

- [ ] **Step 3: 전체 렌더 + 금지 문자열 검증**

Run: `kubectl kustomize local-k8s > /tmp/local-k8s-render.yaml; echo "exit=$?"`
Expected: exit=0.
검증:
- `grep -c 'kind: Deployment' /tmp/local-k8s-render.yaml` → 10 (인프라 5 + 앱 5)
- `grep -c 'namespace: synapse-local' /tmp/local-k8s-render.yaml` → 다수(모든 네임스페이스드 리소스)
- `grep -E 'ExternalSecret|ghcr.io|amazonaws|rds.amazonaws|TO_BE_PATCHED' /tmp/local-k8s-render.yaml | wc -l` → **0**
- `grep -E 'synapse-(platform-svc|engagement-svc|knowledge-svc|learning-card|learning-ai):local' /tmp/local-k8s-render.yaml | wc -l` → 5

- [ ] **Step 4: 커밋**

```bash
git add local-k8s/kustomization.yaml local-k8s/README.md
git commit -m "feat(local-k8s): top kustomization(synapse-local) + README"
```

---

## Task 5: 기동 스크립트 scripts/minikube-up.sh

**Files:** Create `synapse-gitops/scripts/minikube-up.sh`

- [ ] **Step 1: 스크립트 작성** (멱등; 형제 레포가 `../`에 있다고 가정)

```bash
#!/usr/bin/env bash
set -euo pipefail
# Synapse MSA를 minikube에 기동. 형제 레포가 ../synapse-* 에 클론되어 있어야 함.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"          # synapse-gitops
SIB="$(cd "$ROOT/.." && pwd)"                      # team-project-final

echo "==> 1) minikube 시작"
minikube status >/dev/null 2>&1 || minikube start --driver=docker --memory=6144 --cpus=4

echo "==> 2) 이미지 빌드 + minikube 적재"
build_docker() { # <name> <context>
  docker build -t "$1:local" "$2"
  minikube image load "$1:local"
}
build_docker synapse-platform-svc   "$SIB/synapse-platform-svc"
build_docker synapse-engagement-svc "$SIB/synapse-engagement-svc"
build_docker synapse-knowledge-svc  "$SIB/synapse-knowledge-svc"
build_docker synapse-learning-ai    "$SIB/synapse-learning-svc/learning-ai"
# learning-card: Dockerfile 없음 → Spring Boot bootBuildImage 사용
( cd "$SIB/synapse-learning-svc/learning-card" && ./gradlew bootBuildImage --imageName=synapse-learning-card:local )
minikube image load synapse-learning-card:local

echo "==> 3) 매니페스트 적용"
kubectl apply -k "$ROOT/local-k8s"

echo "==> 4) 롤아웃 대기"
kubectl -n synapse-local rollout status deploy/postgres --timeout=120s
for d in platform-svc engagement-svc knowledge-svc learning-card learning-ai; do
  kubectl -n synapse-local rollout status "deploy/$d" --timeout=300s || true
done

cat <<'EOF'
==> 완료. 접근(별도 터미널에서 port-forward):
  kubectl -n synapse-local port-forward svc/platform-svc   8080:80
  kubectl -n synapse-local port-forward svc/engagement-svc 8082:80
  kubectl -n synapse-local port-forward svc/knowledge-svc  8083:80
  kubectl -n synapse-local port-forward svc/learning-card  8084:80
  kubectl -n synapse-local port-forward svc/learning-ai    8000:80
그 다음: curl http://localhost:8080/actuator/health , 브라우저로 http://localhost:8000/docs
상태: kubectl -n synapse-local get pods
EOF
```

- [ ] **Step 2: 문법 검증**

Run: `bash -n scripts/minikube-up.sh; echo "syntax=$?"`
Expected: syntax=0 (실행은 런타임 — docker/minikube 필요, best-effort).

- [ ] **Step 3: 커밋**

```bash
git add scripts/minikube-up.sh
git commit -m "feat(local-k8s): minikube-up.sh — 빌드/적재/적용/포트포워드"
```

---

## Task 6: §9 부록 문서 + 포인터

**Files:** Modify `synapse-gitops/docs/local-msa-setup.html`

- [ ] **Step 1: §9 섹션 추가**

`#next` 섹션의 닫는 `</section>` **뒤**(즉 `</main>` 직전)에 아래를 삽입한다. (현재 #next가 마지막 섹션이므로, `    <section id="next">...</section>` 블록 종료 직후.)

```html
    <section id="k8s"><h2 class="sec"><span class="num">9</span>(고급) 로컬 k8s(minikube)로 띄우기</h2>
      <p>docker compose(<a href="#path1">§3</a>/<a href="#path2">§4</a>) 대신 <strong>minikube 로컬 쿠버네티스</strong>에서 5개 서비스를 파드로 띄우는 경로입니다. <code>local-k8s/</code> kustomize가 EKS용 매니페스트를 로컬용으로 적응합니다(ExternalSecret 제거·인프라 인클러스터·로컬 이미지). <strong>Gateway는 포함되지 않습니다</strong>(매니페스트 없음 — 서비스 직접 접근).</p>

      <div class="step"><input type="checkbox" id="k8s-1"><label for="k8s-1">1. 선행 도구</label></div>
      <div class="code">minikube version
kubectl version --client
docker --version</div>

      <div class="step"><input type="checkbox" id="k8s-2"><label for="k8s-2">2. 한 번에 기동(빌드+적재+적용)</label></div>
      <p>형제 레포(<a href="#clone">§2</a>의 7개)가 클론돼 있어야 합니다. learning-card는 Dockerfile이 없어 스크립트가 <code>bootBuildImage</code>로 빌드합니다(최초 다소 느림).</p>
      <div class="code">cd C:\workspace\team-project-final\synapse-gitops
bash scripts/minikube-up.sh</div>

      <div class="step"><input type="checkbox" id="k8s-3"><label for="k8s-3">3. 파드 상태 확인</label></div>
      <div class="code">kubectl -n synapse-local get pods</div>

      <div class="step"><input type="checkbox" id="k8s-4"><label for="k8s-4">4. 접근 — port-forward(서비스별 별도 터미널)</label></div>
      <div class="code">kubectl -n synapse-local port-forward svc/platform-svc 8080:80
kubectl -n synapse-local port-forward svc/learning-ai   8000:80</div>
      <p>그 다음 <code>curl http://localhost:8080/actuator/health</code>, 브라우저로 <code>http://localhost:8000/docs</code>. 사용법은 <a href="#usage">§5</a>와 동일(단 Gateway 없음 → 서비스 직접).</p>

      <details class="deep"><summary>정적 렌더만 먼저 확인하려면 (심화)</summary>
        <div class="body">클러스터 없이 매니페스트가 올바른지 보려면 <code>kubectl kustomize local-k8s</code>. 인프라 5개 + 앱 5개 Deployment가 <code>synapse-local</code> 네임스페이스로 렌더되고 ExternalSecret/ghcr/AWS 호스트가 없어야 정상입니다.</div>
      </details>
      <details class="deep"><summary>트러블슈팅 (심화)</summary>
        <div class="body"><strong>ImagePullBackOff</strong>: 이미지가 minikube에 적재 안 됨 → <code>minikube image ls | grep synapse</code> 확인, 없으면 <code>minikube image load synapse-&lt;svc&gt;:local</code> 재실행. <strong>검색/카프카 OOM·CrashLoop</strong>: <code>minikube start</code> 메모리를 올리세요(예: <code>--memory=6144</code>). <strong>토픽 미생성</strong>: <code>kubectl -n synapse-local logs job/kafka-topics-init</code>. <strong>compose와 동시 실행 금지</strong>: 포트 충돌 — 한쪽을 내리세요.</div>
      </details>
      <details class="deep"><summary>compose 경로와 무엇이 다른가? (심화)</summary>
        <div class="body">compose 경로(①/②)는 인프라를 호스트 컨테이너로 띄우지만, 이 경로는 인프라까지 <strong>클러스터 안</strong>에 띄워 파드가 서비스 DNS(<code>postgres</code>,<code>kafka</code> 등)로 통신합니다. 실 배포(EKS)와 더 가까운 형태를 로컬에서 체험할 수 있습니다.</div>
      </details>
    </section>
```

- [ ] **Step 2: §8(다음 단계)에 포인터 1줄 추가**

`#next` 섹션의 마지막 `<ul>...</ul>` 안(또는 첫 문단 뒤)에 아래 항목을 추가:

```html
        <li><a href="#k8s">(고급) 로컬 k8s(minikube)로 띄우기 — §9</a> · docker compose 대신 쿠버네티스로 5개 서비스 기동</li>
```

- [ ] **Step 3: 렌더 검증**

정적 서버(`cd docs && python -m http.server 51300 --bind 127.0.0.1`) 후 playwright로 `http://localhost:51300/local-msa-setup.html` 접속:

```js
() => {
  var s=document.getElementById('k8s');
  return {
    exists: !!s,
    num: s.querySelector('.num').textContent,
    steps: s.querySelectorAll('.step').length,
    codeBlocks: s.querySelectorAll('.code').length,
    deeps: s.querySelectorAll('details.deep').length,
    tocHasK8s: !!document.querySelector('nav.toc a[data-target="k8s"]'),
    pointer: !!document.querySelector('#next a[href="#k8s"]'),
    badges: Array.from(document.querySelectorAll('main section[id] .num')).map(n=>n.textContent)
  };
}
// Expected: exists true, num "9", steps 4, codeBlocks 4, deeps 3, tocHasK8s true,
//           pointer true, badges ["0","1","2","3","4","5","6","7","8","9"]
```
이어서 `browser_console_messages` level error → favicon 외 0건.

- [ ] **Step 4: 커밋**

```bash
git add docs/local-msa-setup.html
git commit -m "docs(guide): §9 (고급) 로컬 k8s(minikube)로 띄우기 부록 + 포인터"
```

---

## Task 7: 최종 정적 검증 + (best-effort 런타임)

**Files:** 없음(검증만; 필요 시 수정·커밋)

- [ ] **Step 1: 전체 정적 검증 재실행**

```bash
kubectl kustomize local-k8s > /tmp/final.yaml && echo "render OK"
grep -c 'kind: Deployment' /tmp/final.yaml   # 10
grep -E 'ExternalSecret|ghcr.io|amazonaws|TO_BE_PATCHED' /tmp/final.yaml | wc -l   # 0
grep -E 'synapse-[a-z-]+:local' /tmp/final.yaml | wc -l   # 5
```
Expected: render OK, Deployment 10, 금지문자열 0, 로컬이미지 5.

- [ ] **Step 2: (가능 시) 런타임 best-effort**

Docker 데몬이 가용하면 `bash scripts/minikube-up.sh` 실행 후 `kubectl -n synapse-local get pods`로 Ready 확인. 데몬 불가 시 생략하고 정적 검증을 완료 기준으로 한다(스펙 §9). 런타임에서 실패가 나오면 원인을 기록하되, 이미지 빌드 시간/환경 제약은 차단 사유로 보지 않는다.

- [ ] **Step 3: 마무리 커밋(수정 있었을 때만)**

```bash
git add -A local-k8s docs/local-msa-setup.html scripts/minikube-up.sh
git commit -m "fix(local-k8s): 정적 검증 반영 수정"
```
(Step 1이 그대로 통과했다면 생략.)

---

## Self-Review (작성자 체크리스트 결과)

**1. 스펙 커버리지:** §3 구조→Task 1·3·4 파일 구조 일치. §4 앱 패치(ExternalSecret 삭제·인프라 DNS·로컬 이미지·Secret)→Task 2(Secret)+Task 3(overlay). §5 인프라→Task 1. §6 스크립트→Task 5. §7 접근(port-forward)→Task 5 출력+Task 6 §9. §8 문서→Task 6. §9 검증(정적 kustomize/런타임 best-effort)→각 Task 검증 단계+Task 7. §2 비목표(Gateway/ArgoCD/Ingress)→미포함 명시.

**2. 플레이스홀더 스캔:** ConfigMap/Secret 키·값은 검증된 표에서 실값으로 확정. ExternalSecret delete의 metadata.name은 platform 확인됨 + 나머지는 "각 base externalsecret.yaml로 검증" 지시(Task 3 Step 2 주의). TBD 없음.

**3. 타입/이름 일관성:** namespace `synapse-local`, Secret 이름 `<svc>-secret`(deployment secretRef와 일치), ConfigMap 이름 `<svc>-config`, 이미지 매치 `ghcr.io/team-project-final/synapse-<svc>`→`synapse-<svc>:local`(5개), 인프라 Service DNS(postgres/redis/kafka/zookeeper/opensearch)가 Task 1↔3↔5 전반 일치. Deployment 총 10개(인프라 5+앱 5)가 Task 4·7 기대값과 일치. §9 섹션 id `k8s`, 배지 9, 코드블록 4·step 4·deeps 3가 Task 6 검증과 일치.