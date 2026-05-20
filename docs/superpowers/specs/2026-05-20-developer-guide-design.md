# Synapse Developer Guide 설계 스펙

> **작성일**: 2026-05-20
> **범위**: gitops / shared / gateway를 아우르는 단일 올인원 개발자 가이드
> **산출물**: `docs/synapse-developer-guide.md`

---

## 1. 목적

Synapse 프로젝트에 합류한 개발자가 하나의 문서에서 프로젝트 전체 구조를 이해하고, 로컬 개발부터 EKS 배포까지의 흐름을 따라갈 수 있도록 한다. 기존 23개 런북 + 3개 가이드가 분산되어 있어 "어디부터 읽어야 하는지" 모르는 문제를 해결한다.

---

## 2. 대상 독자

- **주 대상**: 주니어 이상 백엔드 개발자 (Spring Boot, Docker 기본 경험 있음)
- **설명 수준**: 신입이 읽어도 "왜" 이렇게 하는지 이해할 수 있는 수준
- **전제 지식**: Java, Git, Docker 기본 사용법

---

## 3. 문서 위치 및 형태

- **위치**: `docs/synapse-developer-guide.md` (gitops 레포)
- **형태**: 단일 마크다운 파일 (올인원)
- **기존 문서와의 관계**: 흐름 설명 후 기존 런북으로 "상세는 여기" 링크. 중복 작성하지 않음.

---

## 4. 목차 구조 (10개 섹션)

### 4.1 프로젝트 개요

이 섹션에서 알 수 있는 것: Synapse가 무엇이고, 어떤 구조로 되어 있는가.

내용:
- Synapse 프로젝트 한 줄 설명
- 전체 아키텍처 다이어그램 (ASCII art)
  - 사용자 → Gateway → 5개 서비스 → RDS/Redis/Kafka/OpenSearch
- 레포 구성표

| 레포 | 역할 | 기술 |
|---|---|---|
| synapse-gitops | K8s 매니페스트 + Terraform IaC + ArgoCD | Kustomize, Terraform, ArgoCD |
| synapse-shared | Avro 스키마 + 공통 라이브러리 + 로컬 인프라 | Avro, Docker Compose, Gradle |
| synapse-gateway | API Gateway | Spring Cloud Gateway, Java 21 |
| synapse-*-svc | 도메인 서비스 | Spring Boot, Java 21 |

### 4.2 기술 스택

이 섹션에서 알 수 있는 것: 프로젝트에서 사용하는 기술과 그 이유.

내용:
- 언어/프레임워크: Java 21, Spring Boot 4.x, Spring Cloud Gateway
- 메시징: Apache Kafka + Confluent Schema Registry + Avro
- 데이터: PostgreSQL, Redis, OpenSearch
- 인프라: AWS EKS, Terraform, ArgoCD, Kustomize
- 시크릿: AWS Secrets Manager + External Secrets Operator
- 이벤트 흐름 다이어그램 (4개 Kafka 토픽의 producer → consumer 관계)

### 4.3 로컬 개발 환경 세팅

이 섹션에서 알 수 있는 것: 내 PC에서 서비스를 돌리려면 뭘 설치하고 어떤 명령을 실행하는가.

내용:
- 사전 요구사항 체크리스트 (JDK 21, Docker, AWS CLI, Gradle, kubectl, helm)
- shared 레포의 Docker Compose로 로컬 인프라 실행
  ```
  cd synapse-shared && docker compose up -d
  ```
- 서비스별 로컬 실행 (Gradle bootRun)
- Gateway 연동 확인
- → 상세 링크: `docs/docker-compose-workflow-guide.md`

### 4.4 레포별 역할과 구조

이 섹션에서 알 수 있는 것: 각 레포 안에 뭐가 있고, 내가 뭘 수정해야 하는가.

내용:
- synapse-shared 디렉토리 구조 + 핵심 파일 설명
  - `src/main/avro/` — Avro 스키마 정의
  - `scripts/` — 토픽 생성, 스키마 등록
  - `docker-compose.yml` — 로컬 인프라
- synapse-gateway 디렉토리 구조
  - 라우팅 설정, Redis 세션
- synapse-gitops 디렉토리 구조
  - `apps/` — 5개 서비스 × 3개 환경 Kustomize
  - `argocd/` — ApplicationSet
  - `infra/aws/dev/` — Terraform
  - `docs/runbooks/` — 운영 런북

### 4.5 GitOps 배포 흐름

이 섹션에서 알 수 있는 것: 내 코드가 어떻게 EKS에 배포되는가.

내용:
- 배포 파이프라인 다이어그램 (ASCII art):
  ```
  코드 PR → CI 빌드 → Docker 이미지 → ECR push
       → ArgoCD Image Updater 감지 → Kustomize overlay 갱신
       → ArgoCD 자동 sync → EKS Pod 교체
  ```
- Kustomize overlay 설명 (base + dev/staging/prod)
- ConfigMap: 환경별 설정값 (DB endpoint, Kafka broker 등)
- ExternalSecret: AWS Secrets Manager에서 시크릿 자동 동기화
- → 상세 링크: step4, step5, step6 런북

### 4.6 AWS 인프라

이 섹션에서 알 수 있는 것: AWS에 뭐가 있고, Terraform으로 어떻게 관리하는가.

내용:
- 인프라 구성도 (ASCII art):
  ```
  VPC 10.0.0.0/16
  ├── Public Subnet: Bastion (SSM), NAT Gateway
  └── Private Subnet: EKS Nodes, RDS, Redis, MSK, OpenSearch
  ```
- 리소스 목록 + 용도 테이블
- Terraform 사용법 (init → plan → apply → destroy)
- 비용 주의사항 (~$0.40/hr, 작업 후 반드시 destroy)
- → 상세 링크: w2-terraform-apply-quickstart.md

### 4.7 EKS 접근 (Bastion SSM)

이 섹션에서 알 수 있는 것: EKS 클러스터에 어떻게 접근하고 kubectl을 사용하는가.

내용:
- EKS가 private endpoint인 이유 (보안)
- SSM Session Manager로 Bastion 접속
- kubectl / helm 기본 명령어
- → 상세 링크: bastion-ssm-access.md

### 4.8 시크릿 관리

이 섹션에서 알 수 있는 것: DB 비밀번호 같은 시크릿이 어떻게 Pod에 전달되는가.

내용:
- 흐름: AWS Secrets Manager → ClusterSecretStore → ExternalSecret → K8s Secret → Pod env
- 새 시크릿 추가 시 해야 할 것 (3단계)
- → 상세 링크: step5-eso-secrets.md

### 4.9 자주 하는 작업 (레시피)

이 섹션에서 알 수 있는 것: 일상적인 작업의 step-by-step.

내용:
- 새 환경변수 추가하기 (ConfigMap patch)
- 새 Kafka 토픽 추가하기 (shared scripts + ConfigMap)
- ECR에 이미지 push하기 (docker build → tag → push)
- ArgoCD에서 앱 상태 확인하기 (bastion 경유)
- Avro 스키마 변경하기 (BACKWARD 호환 필수)

### 4.10 트러블슈팅 + 런북 인덱스

이 섹션에서 알 수 있는 것: 문제가 생겼을 때 어디를 보면 되는가.

내용:
- 자주 만나는 에러 5가지 + 원인 + 해결
  - Pod ImagePullBackOff → ECR 이미지 미존재 또는 인증 실패
  - Pod CrashLoopBackOff → 환경변수 누락 또는 DB 연결 실패
  - ArgoCD OutOfSync → Git 레포 접근 실패 또는 CRD 미설치
  - SSM 접속 불가 → Instance 중지 또는 SG/IAM 문제
  - ExternalSecret SecretSyncError → IRSA 권한 또는 시크릿 경로 불일치
- 전체 런북 인덱스 (23개 + 3개 가이드)

---

## 5. 작성 원칙

1. 각 섹션 시작에 **"이 섹션에서 알 수 있는 것"** 한 줄 요약
2. 명령어는 **복붙 가능한 코드블록**으로 제공
3. "왜"를 설명한 뒤 "어떻게"를 설명 (신입 친화적)
4. 기존 런북과 중복 최소화 — 흐름 설명 후 "상세는 여기" 링크
5. 아키텍처 다이어그램은 ASCII art (외부 도구 불필요)
6. 한국어 작성, 명령어/코드는 영어 그대로

---

## 6. 기존 문서 참조 맵

| 가이드 섹션 | 링크할 기존 문서 |
|---|---|
| 4.3 로컬 개발 | `docs/docker-compose-workflow-guide.md` |
| 4.5 배포 흐름 | `docs/runbooks/step4-dev-overlay.md`, `step5-eso-secrets.md`, `step6-image-sync.md` |
| 4.6 AWS 인프라 | `docs/runbooks/w2-terraform-apply-quickstart.md`, `docs/aws-infra-provisioning-workflow-guide.md` |
| 4.7 Bastion | `docs/runbooks/bastion-ssm-access.md` |
| 4.8 시크릿 | `docs/runbooks/step5-eso-secrets.md` |
| 4.10 런북 인덱스 | 전체 23개 런북 + 3개 가이드 |
