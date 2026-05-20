# W2 핸드오프: 다음 세션 이어받기 (v2)

> **최종 갱신**: 2026-05-19 (4차 세션 — EKS 실배포 완료)
> **현재 상태**: W2 전 Task 완료. EKS에 ArgoCD + ESO + 5개 앱 배포됨. ExternalSecret 5개 SecretSynced.
> **남은 작업**: ConfigMap endpoint 추가 (RDS/MSK/OpenSearch 재생성 후), ECR 이미지 push (각 서비스팀)
> **브랜치**: main (PR #20, #21 모두 머지 완료)
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
| 7 | ConfigMap 토픽명 추가 | ✅ 완료 | endpoint는 인프라 재생성 후 추가 |
| 8 | EKS provider swap | ✅ 완료 | ESO→AWS SM, 이미지→ECR, ClusterSecretStore 추가 |
| 9 | PRD W2 검수 + 문서 | ✅ 완료 | FR-GO-201~206 전항목 EKS 실증 완료 (202 제외: 도메인 미확보) |
| 10 | kind 클러스터 정리 | ✅ 완료 | `kind delete cluster --name synapse-w2` |
| 11 | EKS 실배포 | ✅ 완료 | ArgoCD HA + ESO + IRSA + AWS SM 8개 시크릿 + 5개 앱 Synced |

---

## 3. 다음 세션 작업 순서

```
Task 2: terraform apply
  ├── 가이드: docs/runbooks/w2-terraform-apply-quickstart.md
  ├── AWS 자격증명 설정
  ├── State Backend 확인
  ├── terraform.tfvars 생성
  ├── terraform apply (~30분)
  └── endpoint 수집 (RDS, Redis, MSK, OpenSearch)
       ↓
Task 7 보충: ConfigMap dev overlay에 endpoint 값 추가
  ├── DATABASE_HOST, REDIS_HOST, KAFKA_BROKERS, OPENSEARCH_URL
  └── SCHEMA_REGISTRY_URL
       ↓
Task 8: EKS provider swap
  ├── 가이드: docs/runbooks/w2-eks-transition.md
  ├── ExternalSecret: fake-secrets → aws-secrets-manager
  ├── 이미지 경로: localhost:5001 → ECR
  ├── ApplicationSet annotation: localhost:5001 → ECR
  ├── ESO AWS provider (IRSA + ClusterSecretStore)
  ├── Image Updater ECR (IRSA + Deploy Key)
  └── ImageUpdater CR 적용
       ↓
Task 5: shared HISTORY 갱신
       ↓
Task 9: PRD W2 검수 (FR-GO-201~206) + 문서 갱신
       ↓
Task 10: kind 클러스터 정리
```

---

## 4. 사전 조건 체크리스트 (다음 세션 시작 시)

```
[ ] AWS 결제수단 verification 완료 확인
[ ] aws configure 완료 (aws sts get-caller-identity → synapse-admin)
[ ] terraform version → v1.x 확인
[ ] gitops 레포: git checkout feat/w2-dev-deploy && git pull
[ ] shared PR #2 머지 여부 확인 (머지 안 됐으면 먼저 머지)
[ ] SSM Session Manager Plugin 설치 (로컬)
[ ] aws-auth ConfigMap에 bastion role 등록
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
| `docs/superpowers/plans/2026-05-18-shared-gitops-unified.md` | 통합 구현 플랜 (10 tasks) |

### Provider 교체 대상 파일

| 파일 | 변경 내용 |
|---|---|
| `apps/*/overlays/dev/kustomization.yaml` | `fake-secrets` → `aws-secrets-manager` + `localhost:5001` → ECR + endpoint 추가 |
| `argocd/applicationset.yaml` | `localhost:5001` → ECR |

---

## 6. 발견 사항 기록 (다음 세션에서 주의)

| ID | 내용 | 영향 |
|---|---|---|
| D-017 | EKS private endpoint — 로컬 helm/kubectl 접근 불가 | ✅ SSM Bastion 구성 완료. `docs/runbooks/bastion-ssm-access.md` 참조 |
| D-015 | Image Updater v1.2.0: annotation → CRD 기반 | `argocd/image-updater.yaml`에 CR 작성 완료. `useAnnotations: true`로 기존 annotation 호환 |
| — | ESO apiVersion `v1beta1` → `v1` | 이미 수정 완료 |
| — | kind `containerdConfigPatches` K8s v1.35.0 비호환 | 단일 노드 + 수동 mirror로 해결. EKS에서는 해당 없음 |
| — | Image Updater helm `api_url` 포트 | kind 내부 5000 vs 호스트 5001. EKS에서는 ECR endpoint 사용 |
| — | Schema Registry 포트 8081 충돌 | Docker Compose에서 8085로 변경 완료 |
| — | learning-card 포트/헬스체크 | 현재 8080/Spring. svc 레포 확인 후 3000/Next.js면 수정 필요 |

---

## 7. PR 현황

| 레포 | PR | 브랜치 | 상태 |
|---|---|---|---|
| synapse-gitops | [#20](https://github.com/team-project-final/synapse-gitops/pull/20) | `feat/w2-dev-deploy` | Open |
| synapse-shared | [#2](https://github.com/team-project-final/synapse-shared/pull/2) | `feat/w2-kafka-schemas` | Open |

---

## 8. 비용 관리

- terraform apply 후 시간당 ~$0.40 발생
- 작업 완료 후 반드시: `cd infra/aws/dev && terraform destroy -auto-approve`
- S3 state bucket + DynamoDB lock table은 삭제하지 않음 (다음 apply에 필요, 비용 거의 없음)

---

## 9. 빠른 시작 (다음 세션)

```bash
# 1. gitops 레포 최신화
cd /c/workspace/team-project-manager/team-project-final/synapse-gitops
git checkout feat/w2-dev-deploy
git pull

# 2. 핸드오프 확인
cat docs/superpowers/HANDOFF_W2.md

# 3. terraform 가이드 따라가기
cat docs/runbooks/w2-terraform-apply-quickstart.md

# 4. terraform apply
cd infra/aws/dev
terraform init && terraform plan && terraform apply

# 5. endpoint 수집 후 EKS 전환
cat docs/runbooks/w2-eks-transition.md
```
