# 통합 작업계획: synapse-shared W1/W2 + synapse-gitops W2 Phase 2

> **기간**: 2026-05-19 ~ 2026-05-23 (5 영업일)
> **담당**: @VelkaressiaBlutkrone (두 레포 모두)
> **레포**: [synapse-shared](https://github.com/team-project-final/synapse-shared) + [synapse-gitops](https://github.com/team-project-final/synapse-gitops)

---

## 1. 배경

synapse-gitops W2 Phase 1 (kind 검증)은 완료. Phase 2 (EKS 전환)를 진행하려면 synapse-shared의 밀린 W1 작업(AWS 인프라 + Docker Compose)과 W2 작업(Kafka 토픽 + Schema Registry)이 선행되어야 한다.

두 레포를 동일 인물이 관리하므로, 하나의 통합 일정으로 순차 진행한다.

## 2. 전체 일정

| 날짜 | 레포 | 작업 | 산출물 |
|---|---|---|---|
| Day 1 AM (월) | shared | Step 1: AWS 인프라 프로비저닝 (gitops terraform apply) | EKS + RDS + MSK + Redis + OpenSearch 가동 |
| Day 1 PM (월) | shared | Step 2: Docker Compose 4서비스 + 인프라 컴포넌트 | `docker-compose.yml` + `.env.example` |
| Day 2 AM (화) | shared | Step 3 HISTORY 갱신 + W1 마무리 PR | shared W1 완료 |
| Day 2 PM (화) | shared | W2 Step 4: Kafka 토픽 설계 + 생성 스크립트 | 토픽 목록 + Avro 스키마 + 생성 스크립트 |
| Day 3 AM (수) | shared | W2 Step 5: Schema Registry BACKWARD 정책 | 호환성 정책 + 검증 |
| Day 3 PM (수) | gitops | Phase 2 시작: ConfigMap 값 확정 + provider 교체 | ESO → AWS, 이미지 → ECR |
| Day 4 (목) | gitops | EKS 5개 앱 배포 + Image Updater + Deploy Key | 5개 앱 Synced + Healthy |
| Day 5 (금) | gitops | PRD W2 검수 + 문서 갱신 + PR 머지 | W2 완료 |

### 브랜치 전략

```
synapse-shared:  feat/w1-w2-infra-compose → main (PR)
synapse-gitops:  feat/w2-dev-deploy (기존 PR #20) → main
```

### 레포 간 데이터 흐름

```
shared Step 1 (terraform apply)
  → EKS 클러스터 + MSK + RDS 가동
  → 접속 정보 확보 (endpoints, ports)
      ↓
shared Step 2 (Docker Compose)
  → .env.example에 로컬 endpoint
  → 팀원 로컬 개발 환경 제공
      ↓
shared W2 Step 4 (Kafka 토픽)
  → 토픽 이름 확정
      ↓
shared W2 Step 5 (Schema Registry)
  → SCHEMA_REGISTRY_URL 확정
      ↓
gitops Phase 2 (EKS 전환)
  → 위에서 확정된 값으로 ConfigMap 완성
  → provider 교체 → EKS 배포
```

---

## 3. shared W1 Step 1 — AWS 인프라 프로비저닝

### 3-1. 실행 방법

terraform 코드는 `synapse-gitops/infra/aws/dev/`에 있다. gitops 레포 디렉토리에서 실행하되, 결과를 shared HISTORY에 기록.

### 3-2. 사전 준비

| 항목 | 명령 |
|---|---|
| aws CLI | `choco install awscli -y` |
| terraform | `choco install terraform -y` |
| AWS 자격증명 | `aws configure` → synapse-admin |
| 결제수단 verification | AWS 콘솔에서 확인 |

### 3-3. 프로비저닝 대상

| 자원 | terraform 파일 | 예상 비용/시간 |
|---|---|---|
| VPC + Subnet | `vpc.tf` | ~$0, 2분 |
| EKS 클러스터 + 노드 | `eks.tf` | ~$0.18/시간, 15분 |
| RDS PostgreSQL 16 | `rds.tf` | ~$0.02/시간, 10분 |
| ElastiCache Redis 7 | `redis.tf` | ~$0.02/시간, 5분 |
| MSK Kafka | `msk.tf` | ~$0.10/시간, 20분 |
| OpenSearch | `opensearch.tf` | ~$0.04/시간, 10분 |
| ArgoCD (Helm) | `argocd.tf` | EKS 위에 설치 |

총 소요: ~25~45분, 시간당 ~$0.40

### 3-4. 산출물

- EKS kubeconfig 설정
- 각 자원 endpoint 수집 (RDS host, MSK brokers, Redis host, OpenSearch URL)
- 이 endpoint들이 Step 2의 `.env.example`과 gitops ConfigMap에 들어감

### 3-5. 기존 Runbook 활용

- `docs/runbooks/step1-aws-account-setup.md`
- `docs/runbooks/step2-terraform-tfvars.md`
- `docs/runbooks/step3-terraform-apply.md`

---

## 4. shared W1 Step 2 — Docker Compose

### 4-1. 구성 대상

| 서비스 | 이미지 | 포트 | 의존성 |
|---|---|---|---|
| platform-svc | 각 svc 레포 Dockerfile | 8080 | postgres, redis, kafka |
| engagement-svc | 각 svc 레포 Dockerfile | 8081 | postgres, redis, kafka |
| knowledge-svc | 각 svc 레포 Dockerfile | 8082 | postgres, kafka, opensearch |
| learning-card | 각 svc 레포 Dockerfile | 8083 | postgres, kafka |
| learning-ai | 각 svc 레포 Dockerfile | 8000 | postgres |
| postgres | postgres:16 | 5432 | — |
| redis | redis:7-alpine | 6379 | — |
| kafka (KRaft) | confluentinc/cp-kafka | 9092 | — |
| schema-registry | confluentinc/cp-schema-registry | 8085 | kafka |
| opensearch | opensearchproject/opensearch:2 | 9200 | — |

### 4-2. Docker Compose 위치

gitops 레포의 기존 `docker-compose.yml`을 보강한다.

### 4-3. `.env.example`

```
# DB
POSTGRES_HOST=localhost
POSTGRES_PORT=5432
POSTGRES_DB=synapse
POSTGRES_USER=synapse
POSTGRES_PASSWORD=changeme

# Kafka
KAFKA_BROKERS=localhost:9092
SCHEMA_REGISTRY_URL=http://localhost:8085

# Redis
REDIS_HOST=localhost
REDIS_PORT=6379

# OpenSearch
OPENSEARCH_URL=http://localhost:9200
```

### 4-4. 검증 기준

```
✅ docker compose up → 인프라 컴포넌트 모두 healthy
✅ 각 svc는 Dockerfile 있으면 함께 기동, 없으면 인프라만 기동
✅ 팀원 온보딩: clone → cp .env.example .env → docker compose up → 작동
```

---

## 5. shared W2 Step 4 — Kafka 토픽 설계 + 생성

### 5-1. 토픽 목록

네이밍 패턴: `{서비스}.{도메인}.{이벤트}-v{N}` (규칙 08-kafka-event 준수)

| 토픽 | 프로듀서 | 컨슈머 |
|---|---|---|
| `platform.auth.user-registered-v1` | platform-svc | engagement-svc, learning-card |
| `knowledge.note.note-created-v1` | knowledge-svc | learning-ai |
| `knowledge.note.note-updated-v1` | knowledge-svc | learning-ai, opensearch indexer |
| `learning.card.review-completed-v1` | learning-card | engagement-svc (XP 적립) |
| `learning.ai.cards-generated-v1` | learning-ai | learning-card |

### 5-2. 토픽 설정 (dev)

| 항목 | 값 | 이유 |
|---|---|---|
| 파티션 | 3 | dev 최소 구성 |
| 복제 팩터 | 1 (dev) / 3 (prod) | dev는 단일 브로커 가능 |
| retention.ms | 604800000 (7일) | dev 충분 |
| cleanup.policy | delete | 기본 |

### 5-3. 산출물

- Docker Compose에 토픽 자동 생성 init 컨테이너 추가
- MSK 토픽 생성 스크립트 (`scripts/create-kafka-topics.sh`)
- Avro 스키마 추가 (`src/main/avro/` — NoteCreated, ReviewCompleted 등)
- gitops ConfigMap 반영 값 확정

### 5-4. gitops 연결 포인트

토픽 확정 후 gitops ConfigMap에 추가:

```yaml
# 앱별 ConfigMap
KAFKA_BROKERS: "<MSK_BROKERS>"
KAFKA_TOPIC_USER_REGISTERED: "platform.auth.user-registered-v1"
KAFKA_TOPIC_NOTE_CREATED: "knowledge.note.note-created-v1"
KAFKA_TOPIC_REVIEW_COMPLETED: "learning.card.review-completed-v1"
KAFKA_TOPIC_CARDS_GENERATED: "learning.ai.cards-generated-v1"
```

---

## 6. shared W2 Step 5 — Schema Registry BACKWARD 정책

### 6-1. 정책

| 항목 | 값 |
|---|---|
| 글로벌 호환성 | BACKWARD |
| 필드 추가 | 허용 (default 필수) |
| 필드 삭제 | 거부 |
| 타입 변경 | 거부 |

### 6-2. Docker Compose 설정

```yaml
schema-registry:
  image: confluentinc/cp-schema-registry:7.7.0
  environment:
    SCHEMA_REGISTRY_KAFKASTORE_BOOTSTRAP_SERVERS: kafka:29092
    SCHEMA_REGISTRY_HOST_NAME: schema-registry
    SCHEMA_REGISTRY_SCHEMA_COMPATIBILITY_LEVEL: BACKWARD
  ports:
    - "8085:8081"
```

### 6-3. 기존 + 추가 Avro 스키마

기존: `CloudEventEnvelope.avsc`, `UserRegistered.avsc`, `TenantId.avsc`, `UserId.avsc`

추가:
- `knowledge/NoteCreated.avsc`
- `knowledge/NoteUpdated.avsc`
- `learning/ReviewCompleted.avsc`
- `learning/CardsGenerated.avsc`

### 6-4. gitops 연결 포인트

```yaml
SCHEMA_REGISTRY_URL: "<Schema Registry URL>"
```

---

## 7. gitops Phase 2 — ConfigMap 확정 + EKS 전환

### 7-1. ConfigMap 최종 값 (shared 완료 후 확정)

**base ConfigMap에 추가할 공통 키:**

| 키 | 소스 | 대상 앱 |
|---|---|---|
| `KAFKA_BROKERS` | Step 1 MSK endpoint | platform, engagement, knowledge, learning-card |
| `SCHEMA_REGISTRY_URL` | Step 5 확정 | knowledge, learning-card |
| `DATABASE_HOST` | Step 1 RDS endpoint | platform, engagement, knowledge, learning-ai |
| `REDIS_HOST` | Step 1 ElastiCache endpoint | platform, engagement |
| `OPENSEARCH_URL` | Step 1 OpenSearch endpoint | knowledge |

**앱별 추가 키 (dev overlay patch):**

| 앱 | 추가 키 |
|---|---|
| platform-svc | `KAFKA_TOPIC_USER_REGISTERED` |
| knowledge-svc | `KAFKA_TOPIC_NOTE_CREATED`, `KAFKA_TOPIC_NOTE_UPDATED` |
| learning-card | `KAFKA_TOPIC_REVIEW_COMPLETED` |
| learning-ai | `KAFKA_TOPIC_CARDS_GENERATED` |

### 7-2. Provider 교체

3곳 교체 (상세: `docs/runbooks/w2-eks-transition.md`):

| # | 대상 | kind 값 | EKS 값 |
|---|---|---|---|
| 1 | ExternalSecret secretStoreRef | `fake-secrets` | `aws-secrets-manager` |
| 2 | 이미지 경로 | `localhost:5001` | ECR |
| 3 | ApplicationSet annotation | `localhost:5001` | ECR |

### 7-3. PRD 검수

| FR | 검수 | shared 의존 |
|---|---|---|
| FR-GO-201 | 5개 앱 Synced + Healthy | ECR 이미지 (svc 담당자) |
| FR-GO-202 | 헬스체크 200 | 앱 기동 |
| FR-GO-203 | gitleaks 0 findings | 독립 |
| FR-GO-204 | ExternalSecret SecretSynced | AWS Secrets Manager |
| FR-GO-205 | 이미지 자동 반영 | ECR + CI/CD |
| FR-GO-206 | git log 이력 | Deploy Key |

FR-GO-201/202는 ECR에 실제 이미지가 필요. svc 담당자의 이미지 push가 선행이거나, nginx 더미로 구조 검증 우선 수행.

---

## 8. 의사결정 요약

| ID | 결정 | 이유 |
|---|---|---|
| D-016 | shared W1 먼저 → gitops W2 Phase 2 순차 | 인프라 + Kafka + Schema가 확정되어야 ConfigMap 완성 가능 |
| D-017 | Docker Compose는 gitops 기존 파일 보강 | 이미 존재하는 파일 활용 |
| D-018 | Kafka 토픽 5개 + BACKWARD 정책 | PRD W2 의존성 맵 기반 최소 토픽 목록 |
| D-019 | 레포별 브랜치 분리 관리 | 각 레포 PR 히스토리 깔끔, 역할 명확 |
