# W2 핸드오프: 다음 세션 이어받기 (v4)

> **최종 갱신**: 2026-05-20 (6차 세션 — SSM Bastion 구성 완료)
> **현재 상태**: EKS private endpoint only + SSM Bastion 접근 구성 완료. aws-auth에 bastion role 등록됨.
> **남은 작업**: ECR 이미지 push (각 서비스팀), ConfigMap endpoint 반영 확인, W3 시작
> **브랜치**: main
> **담당**: @VelkaressiaBlutkrone

---

## 1. 세션별 완료 사항

### 1차 세션 (설계 + kind 검증)

| 작업 | 산출물 |
|---|---|
| W2 설계 스펙 | `docs/superpowers/specs/2026-05-18-w2-dev-deploy-design.md` |
| W2 구현 플랜 | `docs/superpowers/plans/2026-05-18-w2-dev-deploy.md` |
| kind 클러스터 세팅 | `infra/kind/` (kind-config, local-registry, setup-kind-w2, fake-secret-store) |
| 5개 앱 base 보강 | ConfigMap + envFrom + ExternalSecret |
| dev overlay | ConfigMap patch + ExternalSecret secretStoreRef patch |
| ApplicationSet | Image Updater annotations + ImageUpdater CR |
| kind 검증 | Step 4 ✅ Step 5 ✅ Step 6 ✅ (태그 감지 성공) |

### 2차 세션 (shared 통합 + Docker Compose + 가이드)

| 작업 | 산출물 |
|---|---|
| shared+gitops 통합 설계 스펙 | `docs/superpowers/specs/2026-05-18-shared-gitops-unified-plan-design.md` |
| 통합 구현 플랜 | `docs/superpowers/plans/2026-05-18-shared-gitops-unified.md` |
| Docker Compose 보강 | `kafka-init` 서비스 + Schema Registry BACKWARD 정책 |
| Avro 스키마 4개 (shared) | NoteCreated, NoteUpdated, ReviewCompleted, CardsGenerated |
| MSK 토픽 생성 스크립트 (shared) | `scripts/create-kafka-topics.sh` |
| ConfigMap 토픽명 추가 | 4개 앱에 Kafka 토픽 환경변수 |
| Schema Registry 검증 | BACKWARD 정책 ✅ + 비호환 거부 ✅ |
| ArgoCD UI 접속 가이드 | `docs/runbooks/argocd-ui-access.md` |
| EKS 전환 가이드 | `docs/runbooks/w2-eks-transition.md` |
| Terraform 빠른 시작 | `docs/runbooks/w2-terraform-apply-quickstart.md` |

### 5차 세션 (AWS 인프라 재생성 + ConfigMap endpoint 추가)

| 작업 | 산출물 |
|---|---|
| terraform apply (AWS 인프라 재생성) | VPC, EKS, RDS, MSK, Redis, OpenSearch — 잔존 리소스 import 포함 |
| ConfigMap endpoint 추가 | 5개 앱 dev overlay에 서비스별 선별 매핑 (PR #23) |
| kustomize build 검증 | 5개 앱 전체 빌드 성공 |

### 6차 세션 (SSM Bastion 구성)

| 작업 | 산출물 |
|---|---|
| SSM Bastion 설계 스펙 | `docs/superpowers/specs/2026-05-20-ssm-bastion-design.md` |
| SSM Bastion 구현 플랜 | `docs/superpowers/plans/2026-05-20-ssm-bastion.md` |
| Bastion Terraform 리소스 | `infra/aws/dev/bastion.tf` (IAM Role + SG + EC2) |
| EKS public endpoint 비활성화 | `eks.tf` — private only |
| SSM 접근 런북 | `docs/runbooks/bastion-ssm-access.md` |
| aws-auth ConfigMap 등록 | bastion role → `system:masters` |
| SSM 접속 검증 | kubectl get nodes ✅ (2 nodes Ready) |

---

## 2. 현재 상태 (태스크별)

| Task | 내용 | 상태 | 비고 |
|---|---|---|---|
| 1 | aws CLI + terraform 설치 | ✅ 완료 | choco 설치 |
| 2 | terraform apply (AWS 인프라) | ✅ 완료 | 다른 PC에서 이미 완료. 중복 생성분 destroy 정리 |
| 3 | Docker Compose 보강 | ✅ 완료 | kafka-init + BACKWARD |
| 4 | Avro 스키마 (shared) | ✅ 완료 | shared PR #2 → main 머지 |
| 5 | shared HISTORY 갱신 | ✅ 완료 | W2 Step 4-5 기록 |
| 6 | Schema Registry 검증 | ✅ 완료 | BACKWARD + 비호환 거부 |
| 7 | ConfigMap 토픽명 + endpoint 추가 | ✅ 완료 | 토픽명 + RDS/Redis/MSK/OpenSearch endpoint 반영 (PR #23) |
| 8 | EKS provider swap | ✅ 완료 | ESO→AWS SM, 이미지→ECR, ClusterSecretStore 추가 |
| 9 | PRD W2 검수 + 문서 | ✅ 완료 | FR-GO-201~206 전항목 EKS 실증 완료 (202 제외: 도메인 미확보) |
| 10 | kind 클러스터 정리 | ✅ 완료 | `kind delete cluster --name synapse-w2` |
| 11 | EKS 실배포 | ✅ 완료 | ArgoCD HA + ESO + IRSA + AWS SM 8개 시크릿 + 5개 앱 Synced |
| 12 | SSM Bastion 구성 | ✅ 완료 | PR #24 + #25 머지. EKS private only + aws-auth 등록 |

---

## 3. 다음 세션 작업 순서

```
1. ArgoCD sync + Pod 검증
   ├── SSM으로 bastion 접속
   ├── ArgoCD가 ConfigMap 변경 감지 → 자동 sync
   ├── 5개 앱 Pod 환경변수에 endpoint 반영 확인
   │     kubectl exec <pod> -- env | grep DATABASE_HOST
   └── Pod 정상 기동 확인 (actuator/health 200)
        ↓
2. ECR 이미지 push (각 서비스팀)
   ├── AWS credential 공유 완료 (synapse-admin, AdministratorAccess)
   ├── ECR 로그인: aws ecr get-login-password ... | docker login ...
   ├── 이미지 태그: 963773969059.dkr.ecr.ap-northeast-2.amazonaws.com/synapse/<svc>:dev-latest
   └── push 후 Image Updater 자동 반영 확인 (5분 이내)
        ↓
3. terraform state 정리 (선택)
   ├── EKS/NodeGroup/OIDC import 후 drift 발생 (replace 예정)
   └── terraform plan 확인 후 필요 시 state rm + re-import
        ↓
4. W3 시작 준비
   ├── Step 7: staging overlay 작성
   ├── Step 8: Observability 스택 (Prometheus + Grafana + Loki)
   └── 비용 관리: 작업 완료 후 terraform destroy 필수
```

---

## 4. 사전 조건 체크리스트 (다음 세션 시작 시)

```
[x] AWS 결제수단 verification 완료
[x] aws configure 완료 (aws sts get-caller-identity → synapse-admin)
[x] terraform apply 완료 (RDS/MSK/Redis/OpenSearch/Bastion 생성됨)
[x] SSM Session Manager Plugin 설치 (로컬)
[x] aws-auth ConfigMap에 bastion role 등록
[ ] ArgoCD sync 후 Pod 환경변수 반영 확인
[ ] ECR 이미지 push (각 서비스팀)
```

---

## 5. 핵심 파일 위치

### 가이드 문서 (순서대로 참조)

| 순서 | 문서 | 용도 |
|---|---|---|
| 1 | `docs/runbooks/w2-terraform-apply-quickstart.md` | terraform apply 전체 절차 |
| 2 | `docs/runbooks/w2-eks-transition.md` | EKS provider swap 절차 |
| 3 | `docs/runbooks/argocd-ui-access.md` | ArgoCD UI 접속 |
| 4 | `docs/runbooks/bastion-ssm-access.md` | Bastion SSM 접근 절차 |

### 설계/계획 문서

| 문서 | 내용 |
|---|---|
| `docs/superpowers/specs/2026-05-18-w2-dev-deploy-design.md` | gitops W2 설계 |
| `docs/superpowers/specs/2026-05-18-shared-gitops-unified-plan-design.md` | shared+gitops 통합 설계 |
| `docs/superpowers/specs/2026-05-20-ssm-bastion-design.md` | SSM Bastion 설계 |
| `docs/superpowers/plans/2026-05-18-shared-gitops-unified.md` | 통합 구현 플랜 (10 tasks) |
| `docs/superpowers/plans/2026-05-20-ssm-bastion.md` | SSM Bastion 구현 플랜 (6 tasks) |

### Provider 교체 대상 파일

| 파일 | 변경 내용 |
|---|---|
| `apps/*/overlays/dev/kustomization.yaml` | `fake-secrets` → `aws-secrets-manager` + `localhost:5001` → ECR + endpoint 추가 |
| `argocd/applicationset.yaml` | `localhost:5001` → ECR |

---

## 6. 발견 사항 기록 (다음 세션에서 주의)

| ID | 내용 | 영향 |
|---|---|---|
| D-015 | Image Updater v1.2.0: annotation → CRD 기반 | `argocd/image-updater.yaml`에 CR 작성 완료. `useAnnotations: true`로 기존 annotation 호환 |
| D-016 | terraform state drift: EKS/NodeGroup/OIDC import 후 replace 예정 | `terraform plan`에서 3 destroy 표시. state rm + re-import 또는 EKS 재생성 필요 |
| D-017 | EKS private endpoint — 로컬 helm/kubectl 접근 불가 | ✅ SSM Bastion 구성 완료. `docs/runbooks/bastion-ssm-access.md` 참조 |
| D-019 | AL2023 최소 AMI에 SSM Agent 미포함 | User Data에 `dnf install -y amazon-ssm-agent` 추가로 해결 (PR #25) |
| D-020 | Bastion SG egress 443-only → DNS(53) 차단 | egress all outbound으로 변경. 보안은 ingress 0개로 유지 (PR #25) |
| — | ESO apiVersion `v1beta1` → `v1` | 이미 수정 완료 |
| — | Schema Registry 포트 8081 충돌 | Docker Compose에서 8085로 변경 완료 |
| — | learning-card 포트/헬스체크 | 현재 8080/Spring. svc 레포 확인 후 3000/Next.js면 수정 필요 |

---

## 7. PR 현황

| 레포 | PR | 브랜치 | 상태 |
|---|---|---|---|
| synapse-gitops | [#20](https://github.com/team-project-final/synapse-gitops/pull/20) | `feat/w2-dev-deploy` | Merged |
| synapse-gitops | [#21](https://github.com/team-project-final/synapse-gitops/pull/21) | `feat/w2-dev-deploy` | Merged |
| synapse-gitops | [#22](https://github.com/team-project-final/synapse-gitops/pull/22) | `docs/w2-eks-deploy-update` | Merged |
| synapse-gitops | [#23](https://github.com/team-project-final/synapse-gitops/pull/23) | `feat/w2-configmap-endpoints` | Merged |
| synapse-gitops | [#24](https://github.com/team-project-final/synapse-gitops/pull/24) | `feat/w2-ssm-bastion` | Merged |
| synapse-gitops | [#25](https://github.com/team-project-final/synapse-gitops/pull/25) | `fix/bastion-ssm-agent` | Merged |
| synapse-shared | [#2](https://github.com/team-project-final/synapse-shared/pull/2) | `feat/w2-kafka-schemas` | Open |

---

## 8. Bastion 접속 정보

| 항목 | 값 |
|---|---|
| **Instance ID** | `i-08399527c6f112cee` |
| **Instance Type** | t3.micro |
| **IAM Role** | `synapse-dev-bastion-role` |
| **도구** | kubectl v1.36.1, helm v3.21.0 |
| **EKS 인증** | aws-auth `system:masters` 등록됨 |

### 접속 방법

```powershell
# PowerShell
$env:PATH += ";C:\Program Files\Amazon\SessionManagerPlugin\bin"
aws ssm start-session --target i-08399527c6f112cee --region ap-northeast-2
```

```bash
# Bash
aws ssm start-session --target i-08399527c6f112cee --region ap-northeast-2
```

---

## 9. AWS Endpoint 요약

| 서비스 | Endpoint |
|---|---|
| **RDS** | `synapse-dev-postgres.c7emuq20mhyy.ap-northeast-2.rds.amazonaws.com:5432` |
| **Redis** | `master.synapse-dev-redis.v6lpdh.apn2.cache.amazonaws.com:6379` |
| **MSK** | `b-1.synapsedevkafka.fark5c.c2.kafka.ap-northeast-2.amazonaws.com:9094,b-2.synapsedevkafka.fark5c.c2.kafka.ap-northeast-2.amazonaws.com:9094` |
| **OpenSearch** | `https://vpc-synapse-dev-qm5l2xdch6nfmkqanpmipou74a.ap-northeast-2.es.amazonaws.com` |
| **EKS** | `synapse-dev` (ap-northeast-2, private endpoint only) |
| **ECR** | `963773969059.dkr.ecr.ap-northeast-2.amazonaws.com/synapse/<svc>` |

---

## 10. 비용 관리

- terraform apply 후 시간당 ~$0.40 발생 (bastion t3.micro 추가: ~$0.01/hr)
- 작업 완료 후 반드시: `cd infra/aws/dev && terraform destroy -auto-approve`
- S3 state bucket + DynamoDB lock table은 삭제하지 않음 (다음 apply에 필요, 비용 거의 없음)

---

## 11. 빠른 시작 (다음 세션)

```bash
# 1. gitops 레포 최신화
cd /c/workspace/team-project-manager/team-project-final/synapse-gitops
git checkout main && git pull

# 2. 핸드오프 확인
cat docs/superpowers/HANDOFF_W2.md

# 3. bastion 접속
aws ssm start-session --target i-08399527c6f112cee --region ap-northeast-2

# 4. kubectl 확인
kubectl get pods -A
kubectl get configmap -n synapse-dev -o yaml | grep DATABASE_HOST

# 5. 비용 관리 — 작업 완료 후 반드시
cd infra/aws/dev && terraform destroy -auto-approve
```
