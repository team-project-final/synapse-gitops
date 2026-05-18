# W2 핸드오프: 다음 세션 이어받기

> **작성일**: 2026-05-18
> **현재 상태**: Phase 1 (kind) 완료, Phase 2 (EKS) 미착수
> **브랜치**: `feat/w2-dev-deploy` (PR #20, open)
> **담당**: @VelkaressiaBlutkrone

---

## 1. 이번 세션에서 완료한 것

### 설계 + 계획
- W2 디자인 스펙 작성: `docs/superpowers/specs/2026-05-18-w2-dev-deploy-design.md`
- 구현 플랜 작성: `docs/superpowers/plans/2026-05-18-w2-dev-deploy.md`
- 2-Phase 전략 확정: kind 먼저 → EKS 전환 (의사결정 D-009 ~ D-014)

### Phase 1 (kind) 구현 — 12 commits on `feat/w2-dev-deploy`

| 커밋 | 내용 |
|---|---|
| `bcc936f` | kind cluster config + local registry script |
| `1540018` | 5개 앱 base에 ConfigMap + envFrom 추가 |
| `23aaf35` | 5개 dev overlay에 ConfigMap patch |
| `20c8492` | 5개 ExternalSecret + dev overlay secretStoreRef patch |
| `e081d37` | Fake SecretStore + ApplicationSet Image Updater annotations + setup script |
| `909850a` | HISTORY W2 섹션 + TASK status |
| `1a06267` | ESO apiVersion v1beta1 → v1 수정 |
| `7cd2906` | kind 검증 결과 + D-015 기록 |
| `56e8eec` | ImageUpdater CR (`useAnnotations: true`) + kind 로컬 레지스트리 overlay |
| `5680d16` | ArgoCD UI 접속 가이드 |

### kind 검증 결과

| Step | 항목 | 결과 |
|---|---|---|
| 4 | kustomize build 5개 앱 | ✅ |
| 4 | ArgoCD 5개 앱 Synced | ✅ |
| 4 | 로컬 레지스트리 이미지 Pod Running | ✅ |
| 5 | ESO Fake provider → SecretSynced 5개 | ✅ |
| 5 | K8s Secret 값 확인 | ✅ |
| 5 | gitleaks 0 findings (W2 관련) | ✅ |
| 6 | ImageUpdater CR useAnnotations | ✅ |
| 6 | 새 태그 감지 (1.0.0 → 1.0.1) | ✅ |
| 6 | git write-back | ⚠️ repo creds 미설정 (EKS에서 해결) |

### 발견 사항 (D-015)
- Image Updater v1.2.0: annotation 기반 → CRD 기반으로 전환됨
- `useAnnotations: true`로 기존 annotation 호환 가능
- `argocd/image-updater.yaml`에 ImageUpdater CR 작성 완료

### 추가 발견 (kind 환경 관련)
- `containerdConfigPatches`가 K8s v1.35.0에서 kubelet 타임아웃 유발 → 단일 노드 + 수동 containerd mirror로 해결
- ESO 최신 버전은 CRD apiVersion `v1`이 기본 (v1beta1 아님)
- kind 노드 내부에서 localhost 레지스트리 접근 시 containerd mirror 설정 필요
- Image Updater helm `api_url` 포트: 컨테이너 내부 5000 (호스트 5001과 다름)

---

## 2. 다음 세션에서 할 것

### Phase 2: EKS 전환 (Day 4~5)

상세 절차: `docs/runbooks/w2-eks-transition.md`

#### 사전 준비 (EKS 전환 전)
1. aws CLI 설치: `choco install awscli -y`
2. terraform 설치: `choco install terraform -y`
3. AWS 결제수단 verification 완료 확인
4. `aws configure` → IAM 자격증명 입력
5. PR #20 main 머지
6. kind 클러스터 정리: `kind delete cluster --name synapse-w2`

#### Day 4: 인프라 + Provider 교체
1. **terraform apply** — EKS + VPC + RDS 등 프로비저닝 (25~45분)
2. **ArgoCD 부트스트랩** — `scripts/bootstrap-argocd.sh`
3. **ESO provider 교체** — AWS Secrets Manager 시크릿 등록 + IRSA + ClusterSecretStore
4. **dev overlay 교체** — `fake-secrets` → `aws-secrets-manager`, `localhost:5001` → ECR
5. **Image Updater 교체** — ECR IRSA + Deploy Key

#### Day 5: 검수 + 문서
1. **PRD W2 검수** — FR-GO-201 ~ FR-GO-206
2. **HISTORY/WORKFLOW/TASK 업데이트**
3. **커밋 + PR 업데이트 + 머지**

---

## 3. Provider 교체 체크리스트

3곳만 변경하면 됩니다:

| # | 파일 | kind 값 | EKS 값 |
|---|---|---|---|
| 1 | `apps/*/overlays/dev/kustomization.yaml` (ExternalSecret patch) | `fake-secrets` | `aws-secrets-manager` |
| 2 | `apps/*/overlays/dev/kustomization.yaml` (images) | `localhost:5001/synapse/{app}` + `"1.0.0"` | `<ACCOUNT>.dkr.ecr.../synapse/{app}` + `dev-latest` |
| 3 | `argocd/applicationset.yaml` (image-list annotation) | `localhost:5001/synapse/{{service}}` | `<ACCOUNT>.dkr.ecr.../synapse/{{service}}` |

sed 명령으로 일괄 교체 가능 — `w2-eks-transition.md` 섹션 3-3, 4-1, 4-2 참조.

---

## 4. 현재 파일 상태 요약

### 신규 생성 파일

```
infra/kind/
├── kind-config.yaml            # kind 클러스터 설정 (단일 노드)
├── local-registry.sh           # 로컬 레지스트리 기동 + 더미 이미지 push
├── setup-kind-w2.sh            # kind 전체 세팅 스크립트
└── fake-secret-store.yaml      # ESO Fake ClusterSecretStore

apps/*/base/configmap.yaml      # 5개 앱 ConfigMap
apps/*/base/externalsecret.yaml # 5개 앱 ExternalSecret (secretStoreRef: TO_BE_PATCHED)

argocd/image-updater.yaml       # ImageUpdater CR (useAnnotations: true)

docs/runbooks/argocd-ui-access.md    # ArgoCD UI 접속 가이드
docs/runbooks/w2-eks-transition.md   # EKS 전환 가이드
docs/superpowers/specs/2026-05-18-w2-dev-deploy-design.md  # 설계 스펙
docs/superpowers/plans/2026-05-18-w2-dev-deploy.md         # 구현 플랜
```

### 수정된 파일

```
apps/*/base/deployment.yaml         # envFrom 추가 (configMapRef + secretRef)
apps/*/base/kustomization.yaml      # configmap.yaml + externalsecret.yaml 추가
apps/*/overlays/dev/kustomization.yaml  # ConfigMap patch + ExternalSecret patch + 이미지 경로
argocd/applicationset.yaml          # Image Updater annotations 추가
docs/project-management/history/HISTORY_gitops.md  # W2 섹션
docs/project-management/task/TASK_gitops.md        # Step 4/5/6 In Progress
```

---

## 5. 주의사항

- **비용**: EKS terraform apply 후 시간당 ~$0.40. 작업 완료 후 반드시 `terraform destroy`
- **dev overlay 이미지**: 현재 kind용 `localhost:5001`로 설정되어 있음. EKS 전환 시 ECR로 교체 필수
- **Image Updater write-back**: Deploy Key + GitHub Ruleset bypass 설정이 필요 (kind에서는 미완)
- **learning-card 포트**: 현재 8080/Spring으로 설정. svc 레포 확인 후 3000/Next.js면 수정 필요
- **ESO apiVersion**: `v1` 사용 (최신 ESO 기준). 이전 버전 ESO를 사용하는 환경이면 `v1beta1`로 복원

---

## 6. 빠른 시작 (다음 세션)

```bash
# 1. 현재 상태 확인
git checkout feat/w2-dev-deploy
git log --oneline -5

# 2. 핸드오프 문서 읽기
cat docs/superpowers/HANDOFF_W2.md

# 3. EKS 전환 가이드 따라가기
cat docs/runbooks/w2-eks-transition.md

# 4. 도구 설치 (미설치 시)
choco install awscli terraform -y

# 5. AWS 인증
aws configure
aws sts get-caller-identity
```
