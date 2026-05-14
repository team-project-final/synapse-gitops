# WORKFLOW Guide — AWS 인프라 프로비저닝

> **대상**: 처음 Synapse 인프라 작업을 맡은 개발자
> **기준 문서**: `documents.wiki/18_기술_스택_정의서.md`, `PRD_W1`, `TASK_team-lead`, `WORKFLOW_team-lead_W1`
> **Duration**: 2일
> **Priority**: P0 (PRD_W1 FR-TL-002)
> **ApplicationSet**: 5 서비스 x 3 환경

---

## 1. 먼저 이해할 것

이 작업은 dev 환경에 필요한 AWS 관리형 인프라와 ArgoCD 배포 기반을 만드는 작업이다. 목표는 운영급 최종 인프라가 아니라, 팀원이 4개 백엔드 서비스와 learning-ai 컨테이너를 EKS 위에 올려 통합 개발을 시작할 수 있는 **최소 배포 기반을 확보**하는 것이다.

### 완료 기준

`kubectl get nodes`에서 EKS 노드가 Ready이고, RDS PostgreSQL 16, MSK Kafka, ElastiCache Redis 7, OpenSearch 8.x, ArgoCD 대시보드에 내부 네트워크 기준으로 접속 가능해야 한다.

### 범위 제한

TASK 기준 Scope는 dev 환경 전용 최소 사양이며 **월 $200 이내 비용 제한**이 있다. Production Multi-AZ 고가용성, 모니터링 대시보드, 본격 비용 최적화는 이 Step의 범위가 아니다.

---

## 2. 문서에서 확인할 근거

| 문서 | 확인할 내용 | 작업에 반영할 결정 |
|------|------------|------------------|
| 18_기술_스택_정의서 | EKS, RDS, ElastiCache, MSK, OpenSearch, ECR, ArgoCD ApplicationSet, Schema Registry | AWS 관리형 서비스와 GitOps 배포 구조를 기본값으로 사용 |
| PRD_W1 | FR-TL-002: EKS 클러스터 가동 + RDS/Redis/MSK/OpenSearch 접속 가능 | 접속 테스트 결과를 수용 기준으로 관리 |
| TASK_team-lead | EKS 3 node, RDS db.t3.medium, MSK 3 broker, Redis cache.t3.micro, OpenSearch 1 node dev | 초기 리소스 크기를 최소 사양으로 고정 |
| WORKFLOW_team-lead_W1 | 1.1 ~ 1.8 체크리스트, 1.6/1.9/1.10 N/A | 요구사항 분석, 보안 1/2차 검토, 구현, 접속 테스트 순서로 진행 |
| 09_Git_규칙_정의서 / 보충 문서 | synapse-gitops, ECR, ArgoCD ApplicationSet, Schema Registry 운영 흐름 | 매니페스트는 GitOps 레포에 두고 ArgoCD가 동기화하게 구성 |

---

## 3. 목표 아키텍처

```
Developer / GitHub Actions
        |
        | docker build + ECR push + gitops image tag update
        v
AWS ECR  ---->  synapse-gitops repo  ---->  ArgoCD ApplicationSet
                                             |
                                             v
                                      EKS dev cluster
                                      ├── platform-svc
                                      ├── engagement-svc
                                      ├── knowledge-svc
                                      ├── learning-card
                                      └── learning-ai

Private subnets / VPC internal access
├── RDS PostgreSQL 16
├── MSK Kafka 3.x
├── Schema Registry
├── ElastiCache Redis 7
└── OpenSearch 8.x
```

### ApplicationSet 기준

18번 기술 스택은 `platform-svc`, `engagement-svc`, `knowledge-svc`, `learning-card`, `learning-ai` **5개 배포 대상**과 `dev`, `staging`, `prod` **3개 환경**을 matrix generator로 관리한다고 정의한다.

---

## 4. 리소스 스펙 초안

| 구성 요소 | dev 기준 스펙 | 설계 포인트 | 접속 확인 |
|-----------|-------------|------------|----------|
| EKS | Managed node group 3 nodes | 서비스 5개와 ArgoCD를 올릴 최소 용량. 노드는 private subnet 우선. | `kubectl get nodes` |
| RDS PostgreSQL | PostgreSQL 16, db.t3.medium | 스토리지 암호화, private subnet, EKS 보안 그룹에서만 접근 허용. | psql 또는 앱 health check |
| MSK Kafka | Kafka 3.x, 3 broker | TLS 통신, private broker, Schema Registry 연동 경로 확보. | `kafka-broker-api-versions.sh` |
| Schema Registry | Confluent 7.x 호환 | MSK와 같은 VPC 내부에서 접근. W2에서 BACKWARD 정책 강제 예정. | `GET /subjects` |
| ElastiCache Redis | Redis 7, cache.t3.micro | AUTH 토큰, in-transit encryption, 앱 서브넷 접근 제한. | `redis-cli --tls ping` |
| OpenSearch | OpenSearch 8.x, 1 node dev | dev 검색 검증용. nori 분석기 사용 가능 여부를 생성 전 확인. | `GET /_cluster/health` |
| ArgoCD | EKS 내부 설치 + ApplicationSet | dev autoSync, staging/prod manual sync 전제. | 대시보드 로그인, app sync 상태 |

---

## 5. 네트워크와 보안 원칙

### VPC 설계

- 서비스 워커 노드와 데이터 계층은 **private subnet**에 둔다.
- 외부 접근은 Cloudflare/Gateway/Ingress 등 공개 진입점���로 제한한다.
- RDS, MSK, Redis, OpenSearch는 VPC 내부 통신만 허용한다.
- NAT Gateway 비용이 부담되면 dev 범위에서 엔드포인트와 비용을 별도 검토한다.

### Security Group

| Source | Destination | Port | 용도 |
|--------|-------------|------|------|
| EKS 노드 SG | RDS | 5432 | PostgreSQL 접속 |
| EKS 노드 SG | Redis | 6379 | Redis 접속 |
| EKS 노드 SG | MSK broker | 9094 (TLS) | Kafka 통신 |
| EKS 노드 SG | OpenSearch | 443 (HTTPS) | 검��� 엔진 접속 |
| Bastion/VPN/SSM | 전체 | 관리 포트 | 관리자 접속 |

### 금지 사항

- RDS, Redis, MSK, OpenSearch를 인터넷에 직접 공개하지 않는다.
- 임시 테스트를 위해 퍼블릭 접근을 열었다면 작업 완료 전 닫고 보안 검토 결과에 기록한다.

---

## 6. 진행 순서

### Step 1. TASK 시작 (1.1)

- Step Goal / Done When / Scope / Input을 `TASK_team-lead`에서 확인한다.
- PRD_W1의 FR-TL-002를 이 작업의 P0 수용 기준으로 표시한다.
- Duration 2일을 기준으로 구현 범위를 dev 최소 인프라로 제한한다.

### Step 2. 요구사항 분석 (1.2)

- EKS/RDS/MSK/ElastiCache/OpenSearch 스펙을 표로 확정한다.
- ApplicationSet의 5서비스 x 3환경 matrix를 확정한다.
- VPC, private subnet, route table, security group 초안을 작성한다.
- Instructions 초안을 TASK 또는 인프라 README에 반영한다.

### Step 3. Security 1차 검토 (1.3)

- VPC 내부 통신�� 허용하는지 확인한다.
- 보안 그룹 인바운드/아웃바운드 규칙을 리소스별로 적는다.
- IAM Role/Policy는 최소 권한 원칙으로 작성한다.
- 검토 결과를 TASK Constraints에 반영한다.

### Step 4. 인프라 아키텍처 설계 (1.4)

- EKS 3 node 구성을 설계한다.
- RDS PostgreSQL 16 db.t3.medium 구성을 설계한다.
- MSK Kafka 3.x 3 broker와 Schema Registry 배치를 설계한다.
- Redis 7 cache.t3.micro와 OpenSearch 1 node dev 구성을 설계한다.
- 설계 후 실제 예상 소요를 보고 Duration final을 갱신한다.

### Step 5. Security 2차 검토 (1.5)

- RDS at-rest 암호화와 SSL 접속 정책을 확인한다.
- MSK TLS 통신 설정을 확인한다.
- ElastiCache AUTH 토큰과 in-transit encryption을 확인한다.
- 검토 결과를 TASK Constraints에 반영한다.

### Step 6. Terraform/eksctl 구현 (1.7)

- 선택한 도구를 하나로 고정한다. 재현성 기준으로는 **Terraform을 우선** 검토한다.
- EKS, RDS, MSK, Redis, OpenSearch를 순서대로 생성한다.
- ArgoCD를 설치하고 ApplicationSet 5서비스 x 3환경을 구성한다.
- 생성된 엔드포인트와 시크릿은 ��서에는 **플레이스홀더로만** 기록한다.

### Step 7. 접속 테스트 (1.8)

- `kubectl get nodes`에서 Ready를 확인한다.
- RDS, MSK, Redis, OpenSearch 접속 테스트 로그를 남긴다.
- ArgoCD 대시보드 접���과 ApplicationSet 렌더링을 확인한다.
- 팀원 접근 권한 부여와 권한 범위를 확인한다.

---

## 7. 구현 산출물 예시

### Terraform 디렉터리

```
infra/aws/dev/
├── main.tf
├── variables.tf
├── outputs.tf
├── vpc.tf
├── eks.tf
├── rds.tf
├── msk.tf
├── redis.tf
├── opensearch.tf
└── argocd.tf
```

### 접속 정보 문서

```
docs/infra/dev-access.md
├── cluster name
├── region
├── kubectl setup
├── internal endpoints placeholder
├── required IAM groups
├── smoke test commands
└── troubleshooting
```

### 시크릿 관리

실제 DB 비밀번호, Redis AUTH 토큰, ArgoCD admin password, AWS access key를 문서나 Git에 남기지 않는다. 공유 문서에는 `<RDS_ENDPOINT>`, `<REDIS_AUTH_TOKEN>` 같은 플레이스홀더만 둔다.

---

## 8. ApplicationSet 골격

> 실제 repo URL, namespace, path는 synapse-gitops 구조에 맞춘다. dev는 자동 동기화, staging/prod는 수동 승인을 전제로 둔다.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: synapse-services
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
                - env: prod
                  autoSync: "false"
  template:
    metadata:
      name: '{{service}}-{{env}}'
    spec:
      project: synapse
      source:
        repoURL: https://github.com/team-project-final/synapse-gitops.git
        targetRevision: main
        path: apps/{{service}}/overlays/{{env}}
      destination:
        server: https://kubernetes.default.svc
        namespace: synapse-{{env}}
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
```

> **주의**: 위 YAML은 구조 설명용이다. `autoSync: false` 환경에서 자동 sync 블록을 조건부로 제거하려면 실제 ApplicationSet 템플릿 기능과 팀의 ArgoCD 버전에 맞춰 별도 검증한다.

---

## 9. Smoke Test 명령

### Kubernetes

```bash
aws eks update-kubeconfig --name synapse-dev --region ap-northeast-2
kubectl get nodes
kubectl get pods -A
kubectl get applications -n argocd
```

### Data Services

```bash
# RDS PostgreSQL
psql "host=<RDS_ENDPOINT> port=5432 dbname=<DB> user=<USER> sslmode=require"

# Redis
redis-cli -h <REDIS_ENDPOINT> -p 6379 --tls -a <TOKEN> ping

# OpenSearch
curl -k https://<OPENSEARCH_ENDPOINT>/_cluster/health

# MSK Kafka
kafka-broker-api-versions.sh --bootstrap-server <MSK_BOOTSTRAP>
```

---

## 10. PR 또는 작업 보고서에 포함할 산출물

- [ ] 인프라 구성도 또는 리소스 목록
- [ ] VPC / subnet / route / security group 설계표
- [ ] Terraform 또는 eksctl 설정 파일
- [ ] ArgoCD ApplicationSet YAML
- [ ] 접속 정보 문서 또는 .env.example 업데이트
- [ ] RDS/MSK/Redis/OpenSearch/ArgoCD smoke test 로그
- [ ] 팀원 접근 권한 부여 내역
- [ ] 비용 제한과 남은 리스크

---

## 11. 최종 체크리스트

| # | 항목 | 상태 |
|---|------|------|
| 1 | TASK Step Goal / Done When / Scope / Input 확인 | [ ] |
| 2 | PRD_W1 FR-TL-002 확인 | [ ] |
| 3 | Duration 2일 기준 범위 확정 | [ ] |
| 4 | EKS/RDS/MSK/Redis/OpenSearch 스펙 확정 | [ ] |
| 5 | ApplicationSet 5서비스 x 3환경 요건 확인 | [ ] |
| 6 | VPC/서브넷/보안그룹 설계 완료 | [ ] |
| 7 | VPC 내부 통신만 허용 | [ ] |
| 8 | IAM 최소 권한 적용 | [ ] |
| 9 | RDS at-rest/in-transit 암호화 확인 | [ ] |
| 10 | MSK TLS 통신 확인 | [ ] |
| 11 | Redis AUTH 토큰 확인 | [ ] |
| 12 | Terraform 또는 eksctl 구현 완료 | [ ] |
| 13 | kubectl nodes Ready 확인 | [ ] |
| 14 | RDS 접속 테스트 완료 | [ ] |
| 15 | MSK 브로커 접속 테스트 완료 | [ ] |
| 16 | Redis 접속 테스트 완료 | [ ] |
| 17 | OpenSearch 접속 테스트 완료 | [ ] |
| 18 | ArgoCD 대시보드 접근 테스트 완료 | [ ] |
| 19 | 팀원 접근 권한 부여 확인 | [ ] |

> **N/A 처리**: 1.6 / 1.9 / 1.10은 인프라 작업으로 해당 없음
