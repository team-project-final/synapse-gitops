# AWS 인프라 Terraform 구현 — 설계 스펙

> **작성일**: 2026-05-14
> **범위**: synapse-gitops 레포에 dev 환경 Terraform IaC + ArgoCD ApplicationSet 구현
> **브랜치**: `docs/INFRA-001-aws-provisioning-workflow-guide`

---

## 1. 목적

Synapse dev 환경의 AWS 인프라를 Terraform으로 코드화하여 재현 가능한 인프라 프로비저닝을 확보한다. 동시에 ArgoCD ApplicationSet으로 5서비스 x 3환경 GitOps 배포 기반을 구성한다.

---

## 2. 산출물 구조

```
synapse-gitops/
├── infra/aws/dev/
│   ├── main.tf              # provider, backend, locals
│   ├── variables.tf         # 전체 변수 정의
│   ├── outputs.tf           # 엔드포인트 출력
│   ├── vpc.tf               # VPC, subnets, route tables, NAT
│   ├── eks.tf               # EKS cluster + managed node group
│   ├── rds.tf               # PostgreSQL 16
│   ├── msk.tf               # Kafka 3.x
│   ├── redis.tf             # Redis 7
│   ├── opensearch.tf        # OpenSearch 8.x
│   └── argocd.tf            # Helm release
├── argocd/
│   └── applicationset.yaml  # 5서비스 x 3환경 matrix
└── docs/
    └── aws-infra-provisioning-workflow-guide.md
```

---

## 3. 리소스 스펙

| 리소스 | 타입/스펙 | 비용 포인트 |
|--------|----------|------------|
| VPC | 2 AZ, 2 public + 2 private subnets, 1 NAT Gateway | NAT ~$32/mo |
| EKS | 1.29, managed node group 3x t3.medium | ~$73/mo (nodes) + $73 (control plane) |
| RDS | PostgreSQL 16, db.t3.medium, 20GB gp3, encrypted | ~$30/mo |
| MSK | kafka.t3.small, 3 broker, 10GB/broker | ~$0 (MSK Serverless) or ~$60/mo |
| Redis | cache.t3.micro, 1 node, AUTH + TLS | ~$12/mo |
| OpenSearch | t3.small.search, 1 node, 10GB | ~$20/mo |
| **예상 합계** | | **~$200/mo** |

---

## 4. 네트워크 설계

- **VPC CIDR**: `10.0.0.0/16`
- **Public subnets**: `10.0.1.0/24`, `10.0.2.0/24` (NAT GW, ALB)
- **Private subnets**: `10.0.10.0/24`, `10.0.20.0/24` (EKS nodes, 데이터 서비스)
- **NAT Gateway**: 1개 (비용 절감, dev 환경)

### Security Group 규칙

| SG | Inbound | Source |
|----|---------|--------|
| sg-rds | TCP 5432 | sg-eks-nodes |
| sg-redis | TCP 6379 | sg-eks-nodes |
| sg-msk | TCP 9094 (TLS) | sg-eks-nodes |
| sg-opensearch | TCP 443 | sg-eks-nodes |
| sg-eks-nodes | All internal | VPC CIDR |

---

## 5. ApplicationSet 설계

- **Generator**: matrix (services x environments)
- **Services**: platform-svc, engagement-svc, knowledge-svc, learning-card, learning-ai
- **Environments**: dev (autoSync), staging (manual), prod (manual)
- **Source path**: `apps/{{service}}/overlays/{{env}}`
- **Namespace**: `synapse-{{env}}`

---

## 6. 보안 요구사항

- RDS: storage_encrypted = true, SSL 접속 강제
- MSK: TLS-only (in_cluster = false, client_authentication TLS)
- Redis: transit_encryption_enabled = true, auth_token 사용
- OpenSearch: HTTPS 강제, VPC 내부만 접근
- EKS: private endpoint 활성화, public endpoint 제한적 허용 (kubectl 접근용)
- IAM: EKS node role에 최소 권한, IRSA 패턴 권장
- 시크릿: terraform.tfvars에 민감값, .gitignore에 포함, 실제 값은 AWS Secrets Manager

---

## 7. 구현 순서

1. `main.tf` + `variables.tf` — provider, backend, 공통 변수
2. `vpc.tf` — VPC, subnets, IGW, NAT, route tables
3. `eks.tf` — cluster, node group, OIDC provider
4. `rds.tf` — subnet group, parameter group, instance
5. `msk.tf` — cluster, configuration
6. `redis.tf` — subnet group, replication group
7. `opensearch.tf` — domain
8. `argocd.tf` — Helm release
9. `outputs.tf` — 전체 엔드포인트
10. `argocd/applicationset.yaml` — 5x3 matrix
