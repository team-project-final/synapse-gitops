# Synapse Developer Guide

> Synapse 프로젝트에 합류한 개발자가 전체 구조를 이해하고, 로컬 개발부터 EKS 배포까지의 흐름을 따라갈 수 있는 올인원 가이드입니다.
>
> **대상**: 주니어 이상 백엔드 개발자 (Spring Boot, Docker 기본 경험)
> **전제 지식**: Java, Git, Docker 기본 사용법

---

## 1. 프로젝트 개요

> 이 섹션에서 알 수 있는 것: Synapse가 무엇이고, 어떤 구조로 되어 있는가.

### Synapse란?

Synapse는 **학습 노트 기반 지식 관리 + AI 학습 카드 생성** 플랫폼입니다. 사용자가 노트를 작성하면, AI가 자동으로 학습 카드를 생성하고, 복습 스케줄을 관리합니다.

### 전체 아키텍처

```
사용자 (브라우저)
    │
    ▼
┌─────────────────┐
│  Gateway (8080)  │  ← Spring Cloud Gateway, Redis 세션
└────────┬────────┘
         │ 라우팅
    ┌────┴────┬────────────┬────────────┬──────────────┐
    ▼         ▼            ▼            ▼              ▼
┌────────┐ ┌──────────┐ ┌──────────┐ ┌────────────┐ ┌──────────┐
│Platform│ │Engagement│ │Knowledge │ │Learning    │ │Learning  │
│  Svc   │ │   Svc    │ │   Svc    │ │  Card      │ │   AI     │
│ (8081) │ │  (8082)  │ │  (8083)  │ │  (8084)    │ │  (8090)  │
└───┬────┘ └────┬─────┘ └────┬─────┘ └─────┬──────┘ └────┬─────┘
    │           │            │              │             │
    └───────────┴────────────┴──────────────┴─────────────┘
                             │
        ┌────────────────────┼────────────────────┐
        ▼                    ▼                    ▼
   ┌─────────┐        ┌──────────┐         ┌──────────┐
   │PostgreSQL│        │  Kafka   │         │  Redis   │
   │  (5432)  │        │ (9092)   │         │  (6379)  │
   └─────────┘        └──────────┘         └──────────┘
                            │
                      ┌─────┴─────┐
                      ▼           ▼
               ┌──────────┐ ┌──────────┐
               │ Schema   │ │OpenSearch│
               │ Registry │ │  (9200)  │
               └──────────┘ └──────────┘
```

### 레포 구성

| 레포 | 역할 | 핵심 기술 |
|---|---|---|
| **synapse-gitops** | K8s 매니페스트 + Terraform IaC + ArgoCD 설정 | Kustomize, Terraform, ArgoCD |
| **synapse-shared** | Avro 스키마 + 공통 라이브러리 + 로컬 인프라 (Docker Compose) | Avro 1.11, Kafka, Gradle |
| **synapse-gateway** | API Gateway — 라우팅, 세션 관리, 인증 | Spring Cloud Gateway, Redis |
| **synapse-platform-svc** | 사용자 인증, 계정 관리 | Spring Boot 4, Java 21 |
| **synapse-engagement-svc** | 사용자 활동 추적, 알림 | Spring Boot 4, Java 21 |
| **synapse-knowledge-svc** | 노트 CRUD, 검색 | Spring Boot 4, Java 21, OpenSearch |
| **synapse-learning-card** | 학습 카드 관리, 복습 스케줄 | Spring Boot 4, Java 21 |
| **synapse-learning-ai** | AI 기반 카드 자동 생성 | Python 3.11, FastAPI |

> **왜 이렇게 나뉘어 있나요?** 각 서비스가 독립적으로 배포되어야 하기 때문입니다. 하나의 서비스를 수정해도 다른 서비스에 영향을 주지 않습니다. gitops 레포는 "무엇을 배포할지"를 관리하고, 각 서비스 레포는 "비즈니스 로직"을 담당합니다.

---

## 2. 기술 스택

> 이 섹션에서 알 수 있는 것: 프로젝트에서 어떤 기술을 쓰고, 왜 그 기술을 선택했는가.

### 언어 및 프레임워크

| 기술 | 버전 | 용도 | 선택 이유 |
|---|---|---|---|
| Java | 21 (Temurin) | 백엔드 서비스 | LTS, Virtual Threads 지원 |
| Spring Boot | 4.x | 웹 프레임워크 | 생태계, 자동 설정, Actuator |
| Spring Cloud Gateway | WebFlux 기반 | API Gateway | 비동기 라우팅, Redis 세션 통합 |
| Python | 3.11 | AI 서비스 (learning-ai) | ML 라이브러리 생태계 |
| Gradle | Kotlin DSL | 빌드 도구 | 멀티모듈, Avro 코드 생성 플러그인 |

### 데이터 및 메시징

| 기술 | 용도 | 왜? |
|---|---|---|
| PostgreSQL 16 | 주 데이터베이스 | ACID, JSON 지원, 안정성 |
| Redis 7 | 세션 스토어 + 캐시 | Gateway 세션 공유, 빠른 응답 |
| Apache Kafka | 서비스 간 비동기 메시징 | 이벤트 기반 아키텍처, 순서 보장 |
| Schema Registry | Avro 스키마 관리 | 스키마 진화 + 호환성 검증 |
| OpenSearch | 전문 검색 | 노트 검색, 엘라스틱 호환 |

### 인프라 및 배포

| 기술 | 용도 | 왜? |
|---|---|---|
| AWS EKS | 컨테이너 오케스트레이션 | 관리형 K8s, IRSA 지원 |
| Terraform | IaC (인프라 코드화) | 재현 가능한 인프라 |
| ArgoCD | GitOps 배포 | Git = 배포 상태의 진실의 원천 |
| Kustomize | K8s 매니페스트 관리 | base + overlay로 환경별 설정 |
| ECR | 컨테이너 이미지 저장소 | EKS 통합, IAM 인증 |
| External Secrets Operator | 시크릿 동기화 | AWS SM → K8s Secret 자동 |

### Kafka 이벤트 흐름

서비스 간 통신은 Kafka 토픽을 통한 **이벤트 기반 아키텍처**입니다. 모든 이벤트는 Avro 스키마로 정의됩니다.

```
platform-svc ──UserRegistered──→ engagement-svc
                                  (사용자 활동 초기화)

knowledge-svc ──NoteCreated────→ learning-ai
               ──NoteUpdated───→ learning-ai
                                  (AI 카드 생성 요청)

learning-ai ───CardsGenerated──→ learning-card
                                  (생성된 카드 저장)

learning-card ─ReviewCompleted─→ engagement-svc
                                  (복습 완료 기록)
```

> **왜 Avro인가요?** JSON보다 작고 빠르며, 스키마 진화(schema evolution)를 지원합니다. 새 필드를 추가해도 기존 컨슈머가 깨지지 않습니다 (BACKWARD 호환).

---

## 3. 로컬 개발 환경 세팅

> 이 섹션에서 알 수 있는 것: 내 PC에서 서비스를 돌리려면 뭘 설치하고 어떤 명령을 실행하는가.

### 사전 요구사항

시작하기 전에 아래 도구들이 설치되어 있어야 합니다.

| 도구 | 확인 명령 | 설치 (Windows) |
|---|---|---|
| JDK 21 | `java -version` | `choco install temurin21` |
| Docker Desktop | `docker --version` | [공식 다운로드](https://www.docker.com/products/docker-desktop/) |
| Gradle | `gradle --version` | `choco install gradle` (또는 `./gradlew` 사용) |
| Git | `git --version` | `choco install git` |
| AWS CLI v2 | `aws --version` | `choco install awscli` |
| kubectl | `kubectl version --client` | `choco install kubernetes-cli` |

### Step 1: 레포 클론

```bash
cd /c/workspace/team-project-manager/team-project-final
git clone https://github.com/team-project-final/synapse-shared.git
git clone https://github.com/team-project-final/synapse-gateway.git
git clone https://github.com/team-project-final/synapse-gitops.git
```

### Step 2: 로컬 인프라 실행

synapse-shared 레포에 전체 로컬 인프라가 Docker Compose로 정의되어 있습니다.

```bash
cd synapse-shared
docker compose up -d
```

이 명령 하나로 아래 서비스들이 모두 실행됩니다:

| 서비스 | 포트 | 용도 |
|---|---|---|
| PostgreSQL | 5432 | 데이터베이스 |
| Redis | 6379 | 세션 스토어 + 캐시 |
| Kafka (+ Zookeeper) | 9092 | 메시징 |
| Schema Registry | 8086 | Avro 스키마 관리 |
| OpenSearch | 9200 | 전문 검색 |
| kafka-init | — | Kafka 토픽 자동 생성 (실행 후 종료) |

실행 확인:

```bash
# 전체 컨테이너 상태 확인
docker compose ps

# Kafka 토픽 확인
docker exec -it kafka kafka-topics --list --bootstrap-server localhost:9092

# PostgreSQL 접속 확인
docker exec -it postgres psql -U synapse_admin -d synapse -c "SELECT 1"
```

### Step 3: 서비스 로컬 실행

각 서비스 레포에서 Gradle로 실행합니다.

```bash
# Gateway
cd synapse-gateway
./gradlew bootRun

# 또는 서비스 레포 (예: platform-svc)
cd synapse-platform-svc
./gradlew bootRun
```

Gateway가 8080에서 실행되면, 각 서비스로의 라우팅이 동작합니다.

### Step 4: 동작 확인

```bash
# Gateway health check
curl http://localhost:8080/actuator/health

# 서비스 health check (Gateway 경유 또는 직접)
curl http://localhost:8081/actuator/health
```

> 📎 **상세 가이드**: [Docker Compose Workflow Guide](docker-compose-workflow-guide.md)

---

## 4. 레포별 역할과 구조

> 이 섹션에서 알 수 있는 것: 각 레포 안에 뭐가 있고, 내가 뭘 수정해야 하는가.

### synapse-shared — 공통 스키마 + 로컬 인프라

"모든 서비스가 공유하는 것"을 담는 레포입니다.

```
synapse-shared/
├── src/main/avro/              # Avro 스키마 정의
│   ├── platform/
│   │   └── UserRegistered.avsc
│   ├── knowledge/
│   │   ├── NoteCreated.avsc
│   │   └── NoteUpdated.avsc
│   ├── learning/
│   │   ├── CardsGenerated.avsc
│   │   └── ReviewCompleted.avsc
│   └── shared/
│       ├── CloudEventEnvelope.avsc
│       ├── TenantId.avsc
│       └── UserId.avsc
├── scripts/                    # 자동화 스크립트
│   ├── create-kafka-topics.sh     # Kafka 토픽 생성
│   ├── register-schema.ps1       # Schema Registry에 스키마 등록
│   ├── check-schema-compatibility.ps1  # 스키마 호환성 검증
│   ├── kafka-e2e-test.sh         # Kafka E2E 테스트
│   └── seed-test-data.sh         # 테스트 데이터 시딩
├── docker-compose.yml          # 로컬 인프라 전체
├── build.gradle.kts            # Avro 컴파일 + Maven publish
└── .env.example                # 환경변수 템플릿
```

> **핵심 규칙**: Avro 스키마를 변경할 때는 반드시 **BACKWARD 호환**을 유지해야 합니다. 기존 필드를 삭제하거나 타입을 변경하면 Schema Registry가 거부합니다. 새 필드를 추가할 때는 `default` 값을 반드시 지정하세요.

### synapse-gateway — API Gateway

외부 트래픽을 받아 각 서비스로 라우팅하는 진입점입니다.

```
synapse-gateway/
├── src/main/
│   ├── java/com/synapse/gateway/   # Gateway 설정 + 필터
│   └── resources/
│       └── application.yml          # 라우팅 규칙, Redis 설정
├── build.gradle.kts                 # Spring Cloud Gateway 의존성
└── Dockerfile                       # 컨테이너 빌드
```

핵심 설정 (`application.yml`):
- 서버 포트: 8080
- Redis: `SPRING_DATA_REDIS_HOST` / `PORT` / `PASSWORD` 환경변수
- Actuator: `/actuator/health`, `/actuator/gateway` 노출

### synapse-gitops — 배포 매니페스트 + 인프라

"무엇을 어디에 배포할지"를 관리하는 레포입니다. 코드가 아니라 **선언적 설정**이 담겨 있습니다.

```
synapse-gitops/
├── apps/                           # 5개 서비스 K8s 매니페스트
│   ├── platform-svc/
│   │   ├── base/                      # 공통 (Deployment, Service, ConfigMap, ExternalSecret)
│   │   └── overlays/
│   │       ├── dev/                   # dev 환경 패치 (endpoint, 이미지 경로)
│   │       ├── staging/               # staging 환경 패치
│   │       └── prod/                  # prod 환경 패치
│   ├── engagement-svc/  (같은 구조)
│   ├── knowledge-svc/   (같은 구조)
│   ├── learning-card/   (같은 구조)
│   └── learning-ai/     (같은 구조)
├── argocd/                         # ArgoCD 설정
│   ├── applicationset.yaml            # 5서비스 × 3환경 자동 생성
│   └── projects.yaml                  # AppProject 정의
├── infra/
│   ├── aws/dev/                    # Terraform IaC
│   │   ├── main.tf, vpc.tf, eks.tf, rds.tf, msk.tf, redis.tf, opensearch.tf
│   │   ├── bastion.tf                 # SSM Bastion EC2
│   │   └── outputs.tf, variables.tf
│   ├── external-secrets/              # ClusterSecretStore
│   └── kind/                          # 로컬 KinD 클러스터 (테스트용)
├── docs/                           # 가이드 + 런북
│   ├── synapse-developer-guide.md     # ← 이 문서
│   └── runbooks/                      # 23개 운영 런북
└── .github/workflows/              # CI (kustomize build 검증)
```

> **왜 overlay인가요?** 같은 서비스를 dev / staging / prod에 배포할 때, 대부분의 설정(Deployment spec, 포트 등)은 동일하고, 환경마다 다른 것(DB endpoint, 이미지 경로, 리소스 제한)만 다릅니다. base에 공통을 두고, overlay에 차이만 패치하면 중복 없이 관리할 수 있습니다.
