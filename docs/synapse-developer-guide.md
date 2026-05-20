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
