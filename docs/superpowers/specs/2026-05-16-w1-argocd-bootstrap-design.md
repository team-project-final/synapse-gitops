# W1 ArgoCD 부트스트랩 마무리 — 설계 (Design Spec)

> **작성일**: 2026-05-16
> **트랙**: gitops
> **담당**: @VelkaressiaBlutkrone
> **대상 주차**: W1 (2026-05-12 ~ 2026-05-16)
> **관련 문서**: [TASK_gitops.md](../../project-management/task/TASK_gitops.md) · [WORKFLOW_gitops_W1.md](../../project-management/workflow/WORKFLOW_gitops_W1.md) · [PRD_W1.md](../../project-management/prd/PRD_W1.md)

---

## 1. 배경

W1 마지막 영업일 시점 점검 결과, Step 1(~20%), Step 2(~50%), Step 3(~20%) 진행. PRD FR-GO-101/102/104/105가 미충족 상태. AWS 크레덴셜이 아직 세팅 안 됐고 도메인도 없으므로, ACM 발급 없이 가능한 path(옵션 2: NLB TCP passthrough + ArgoCD 자체서명 TLS)를 채택하고, ApplicationSet은 PRD 원안(5개) 충실 + 확장 가능 구조(C3)로 정리한다.

## 2. 목표

- W1 Step 1~3의 모든 체크 항목 완료 또는 명시적 후속 조치 합의
- PRD FR-GO-101/103/104/105 충족, FR-GO-102는 "self-signed TLS"로 부분 충족 + W2 마이그레이션 계획 명시
- 사용자(=담당자)가 한 번의 부트스트랩 실행으로 실 환경 적용 완료

## 3. 비목표

- W2 작업 (실 워크로드 manifest, ESO, 이미지 sync, SSO)
- ALB Ingress + ACM + Route53 (도메인 확보 후 W2 초반 마이그레이션)
- webhook 외부 노출 (W1은 polling 3분 간격으로 대체)
- PR diff 코멘트 액션 (W3로 이월)

## 4. 결정 사항

| ID | 결정 | 근거 |
|---|---|---|
| D-001 | 옵션 2 채택 (NLB passthrough + self-signed TLS) | AWS 크레덴셜은 오늘 준비 가능하나 도메인 미확보 → ACM 발급 불가 |
| D-002 | ApplicationSet matrix 유지, env list = [dev]만 (C3) | PRD "5개" 원안 충족 + W3/W4 확장 시 한 줄 추가로 끝 |
| D-003 | controller replicas=1, server replicas=3 | PRD FR-GO-101 문구는 server 3 명시. controller 샤딩은 W3 이상 부하 발생 시 |
| D-004 | redis HA, repoServer 2, applicationSet 2 | HA 의미를 server에 한정하지 않고 의존 컴포넌트 단일 실패점 제거 |
| D-005 | admin 비번 회전 후 AWS Secrets Manager 저장, ESO는 W2 도입 | W1 범위 최소화. Secret 자체는 평문 git 0건 보장 |
| D-006 | RBAC는 admin/readonly 2등급만 | dev 등급은 W2 SSO 연동 후 의미 있음. W1에는 sole admin |
| D-007 | kubeconform 추가, CRD 스키마는 `-ignore-missing-schemas` 경고 처리 | ArgoCD CRD 카탈로그 정비는 W3 Observability 시점 |
| D-008 | main 브랜치 보호 — 필수 체크 강제, reviews는 환경변수 노출 | 단독 작업 시 reviews=0, 팀 합류 시 1로 토글 가능 |

## 5. 아키텍처

```
┌─────────────────────────────────────────────────────────────┐
│ GitHub                                                       │
│  ├─ PR ──> Actions: validate-manifests                       │
│  │         (yamllint + kustomize build + kubeconform)        │
│  └─ main 머지 (보호: 필수 체크 + optional review)            │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ ArgoCD polling (3min)
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ EKS dev 클러스터 (synapse-dev VPC, ap-northeast-2)           │
│                                                              │
│  argocd 네임스페이스                                          │
│    ├─ argocd-server (replicas=3, self-signed TLS)            │
│    ├─ argocd-application-controller (replicas=1)             │
│    ├─ argocd-repo-server (replicas=2)                        │
│    ├─ argocd-applicationset-controller (replicas=2)          │
│    ├─ argocd-redis-ha (replicas=3, sentinel)                 │
│    └─ ApplicationSet: synapse-apps                           │
│         └─ 5 Application (matrix 5svc × [dev])               │
│                                                              │
│  synapse-dev 네임스페이스 (W1은 빈 manifest sync만)            │
└─────────────────────────────────────────────────────────────┘
                              ▲
                              │ TLS passthrough (TCP/443)
                              │
                       [AWS NLB external]
                              ▲
                              │ HTTPS (self-signed 경고 수용)
                              │
                          [브라우저]

Secret 흐름:
  argocd-initial-admin-secret
    └─> bootstrap.sh: argocd account update-password
          └─> AWS Secrets Manager: synapse/argocd/admin (KMS=aws/secretsmanager)
                └─> 초기 secret 삭제
```

## 6. 컴포넌트별 변경

### 6.1 Terraform — `infra/aws/dev/argocd.tf` 재작성

- Helm 차트: `argo/argo-cd@6.7.3` 유지
- `values.yaml` 명시:
  ```yaml
  server:
    replicas: 3
    extraArgs: []   # --insecure 제거
    service:
      type: LoadBalancer
      annotations:
        service.beta.kubernetes.io/aws-load-balancer-type: external
        service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
        service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: ip
        service.beta.kubernetes.io/aws-load-balancer-backend-protocol: ssl
    resources:
      requests: { cpu: 100m, memory: 256Mi }
      limits:   { cpu: 500m, memory: 512Mi }
  controller:
    replicas: 1
    resources:
      requests: { cpu: 200m, memory: 512Mi }
      limits:   { cpu: 1000m, memory: 1Gi }
  repoServer:
    replicas: 2
    resources:
      requests: { cpu: 100m, memory: 256Mi }
  applicationSet:
    replicas: 2
  redis-ha:
    enabled: true
  configs:
    params:
      server.insecure: false
  ```
- terraform 측은 `helm_release.argocd.values = [yamlencode(local.argocd_values)]` 형태로 단일 values 블록 사용 (현재 set 블록 다발 정리)

### 6.2 ArgoCD 부트스트랩 매니페스트 — 신규

- `argocd/bootstrap/rbac-cm.yaml`
  ```yaml
  apiVersion: v1
  kind: ConfigMap
  metadata:
    name: argocd-rbac-cm
    namespace: argocd
  data:
    policy.default: role:readonly
    policy.csv: |
      p, role:admin, applications, *, */*, allow
      p, role:admin, clusters, *, *, allow
      p, role:admin, repositories, *, *, allow
      p, role:admin, projects, *, *, allow
      g, admin, role:admin
  ```
- `argocd/bootstrap/notifications-cm.yaml` — 빈 plate (W3 채움)
- `argocd/projects.yaml` 유지 (현재 정의가 synapse-* namespace로 한정되어 있어 추가 변경 없음, `clusterResourceWhitelist: Namespace`로 충분)

### 6.3 ApplicationSet — `argocd/applicationset.yaml` 수정 (C3)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: synapse-apps
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
  template:
    metadata:
      name: "synapse-{{service}}-{{env}}"
      namespace: argocd
      labels:
        app.kubernetes.io/part-of: synapse
        app.kubernetes.io/component: "{{service}}"
        environment: "{{env}}"
    spec:
      project: synapse
      source:
        repoURL: https://github.com/team-project-final/synapse-gitops.git
        targetRevision: main
        path: "apps/{{service}}/overlays/{{env}}"
      destination:
        server: https://kubernetes.default.svc
        namespace: "synapse-{{env}}"
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
```

`templatePatch` 제거. W3에서 staging 추가 시 `env` list에 한 줄 + auto-sync 분기 재도입.

### 6.4 부트스트랩 스크립트 — `scripts/bootstrap-argocd.sh` 신규

- 입력: 환경 변수 `AWS_REGION`(기본 ap-northeast-2), `CLUSTER_NAME`(기본 synapse-dev)
- 흐름:
  1. 사전 체크: `aws sts get-caller-identity`, `kubectl version --client`, `argocd version --client`, `jq`
  2. `aws eks update-kubeconfig --name $CLUSTER_NAME --region $AWS_REGION`
  3. ArgoCD pod readiness 대기 (`kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=10m`)
  4. NLB 주소 추출: `kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'`
  5. 초기 admin secret 확인 (`argocd-initial-admin-secret`). 없으면 이미 회전된 것 → Secrets Manager 조회로 fallback
  6. 새 비번 생성: `openssl rand -base64 24`
  7. `argocd login $NLB_HOST --username admin --password $INITIAL --insecure --grpc-web`
  8. `argocd account update-password --account admin --current-password $INITIAL --new-password $NEW`
  9. AWS Secrets Manager 저장: `aws secretsmanager create-secret --name synapse/argocd/admin --secret-string "..."` (이미 있으면 `put-secret-value`)
  10. 초기 secret 삭제: `kubectl delete secret argocd-initial-admin-secret -n argocd --ignore-not-found`
  11. AppProject 적용: `kubectl apply -f argocd/projects.yaml`
  12. RBAC ConfigMap 적용: `kubectl apply -f argocd/bootstrap/rbac-cm.yaml`
  13. ApplicationSet 적용: `kubectl apply -f argocd/applicationset.yaml`
  14. 검증: `argocd app list -o name | wc -l`이 5 이상인지
  15. 결과 출력: NLB 주소, Secrets Manager ARN, 5개 Application 이름
- 멱등: 각 단계 전에 현재 상태 확인 후 skip
- 실패 시: 실패 step 번호 출력 + 복구 안내

### 6.5 CI 강화 — `.github/workflows/validate-manifests.yml` 보강

- `.yamllint` 신규:
  ```yaml
  extends: default
  rules:
    line-length: { max: 160, level: warning }
    indentation: { spaces: 2 }
    document-start: disable
    truthy: { check-keys: false }   # Kubernetes "on" 키
    comments: { min-spaces-from-content: 1 }
  ```
- 워크플로우 변경:
  - `yamllint -d relaxed` → `yamllint -c .yamllint`
  - 새 step `Kubeconform validate`:
    ```yaml
    - uses: yokawasa/action-setup-kube-tools@v0.11.1
      with:
        kubeconform: '0.6.7'
    - name: Kubeconform validate
      run: |
        failed=0
        for overlay in apps/*/overlays/*/kustomization.yaml; do
          dir="$(dirname "$overlay")"
          kustomize build "$dir" | kubeconform \
            -strict -ignore-missing-schemas \
            -schema-location default \
            -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
            -summary -output text || failed=1
        done
        exit $failed
    ```
  - `concurrency: { group: validate-${{ github.ref }}, cancel-in-progress: true }`
  - 마지막에 `echo "Total: ${SECONDS}s"`

### 6.6 PR / 문서 신규

- `.github/pull_request_template.md` — 변경 범위, 영향 환경(dev/staging/prod), 로컬 검증 결과, ArgoCD sync 영향
- `CONTRIBUTING.md` — 브랜치 네이밍(`feature/<step>-<slug>`), 커밋 메시지 prefix(`feat/fix/chore/docs/ci`), 로컬 검증 명령 3개(kustomize/yamllint/kubeconform)
- `argocd/README.md` — ApplicationSet 구조 + 새 앱 추가 절차 + 트러블슈팅 (Sync 안 됨 / OutOfSync 원인 / RBAC 거부 / self-signed 우회)
- `docs/argocd-tls-migration.md` — 옵션 2 → 옵션 1 마이그레이션(도메인 등록 → Route53 hosted zone → ACM DNS 검증 → Terraform ALB Ingress 추가 → applicationset/projects 변경 없음 → 검증)
- 루트 `README.md` 재작성 — 디렉토리 구조, CI 검증 단계, 부트스트랩 절차 링크, 환경 변수 표

### 6.7 main 브랜치 보호 — `scripts/setup-branch-protection.sh` 신규

- 입력: `REPO`(기본 team-project-final/synapse-gitops), `REVIEWS`(기본 0, 팀 합류 시 1)
- `gh api -X PUT repos/$REPO/branches/main/protection -F ...` 호출
- 룰: required_status_checks=["Validate Kubernetes Manifests"], required_pull_request_reviews.required_approving_review_count=$REVIEWS, enforce_admins=false, allow_force_pushes=false, allow_deletions=false

### 6.8 PM 문서 갱신

- `WORKFLOW_gitops_W1.md` — Step 1~3 체크박스 `[x]` 처리(실제 완료 항목만), Step Status: Done
- `TASK_gitops.md` — W1 Step 1~3 Status: Done
- `HISTORY_gitops.md` — 2026-05-16 의사결정 5건 추가 (D-001 ~ D-005)
- `PRD_W1.md` — 변경 없음 (C3가 원안 충족)

## 7. 사용자 액션 시퀀스 (예상 60분)

| # | 명령 | 예상 시간 |
|---|---|---|
| 1 | `aws configure` (Access key, region=ap-northeast-2) | 5분 |
| 2 | `cd infra/aws/dev && cp terraform.tfvars.example terraform.tfvars && terraform init && terraform apply` | 20~25분 (EKS+NLB) |
| 3 | `aws eks update-kubeconfig --name synapse-dev --region ap-northeast-2` | 1분 |
| 4 | `bash scripts/bootstrap-argocd.sh` | 5분 |
| 5 | 브라우저 `https://<nlb>.elb.amazonaws.com` 접속 + 로그인 + 스크린샷 | 5분 |
| 6 | `REVIEWS=0 bash scripts/setup-branch-protection.sh` | 1분 |
| 7 | 의도적 오류 PR(잘못된 apiVersion) 1건 생성 → CI 실패 확인 → 닫기 | 10분 |
| 8 | HISTORY에 스크린샷/CI 실패 링크 첨부 + PR로 머지 | 5분 |

## 8. PRD 검수 기준 매핑

| FR | 기준 | 충족 방법 | 결과 |
|---|---|---|---|
| FR-GO-101 | argocd-server replicas 3 + CLI 로그인 | Helm values + bootstrap.sh 검증 | ✅ |
| FR-GO-102 | argocd.<도메인> HTTPS + 인증서 valid | self-signed TLS + NLB DNS | ⚠️ 부분(도메인 확보 후 W2 마이그레이션) |
| FR-GO-103 | git push 시 5개 Application 자동 등록 | ApplicationSet matrix 5×[dev] | ✅ |
| FR-GO-104 | 잘못된 apiVersion PR → CI 실패 | kubeconform 추가 + 의도적 오류 PR 검증 | ✅ |
| FR-GO-105 | CI 미통과 시 머지 차단 | setup-branch-protection.sh | ✅ |

## 9. 에러 처리

| 시나리오 | 대응 |
|---|---|
| terraform apply 도중 자원 부족(EKS 노드 그룹 quota) | apply 실패 메시지 보고 AWS Service Quotas 콘솔에서 quota 증설 요청, 본 작업은 매니페스트/CI 만이라도 PR로 먼저 머지 |
| NLB 프로비저닝 5분 이상 | bootstrap.sh `kubectl wait` 10분 타임아웃, 그 이후엔 수동 재시도 안내 |
| ArgoCD admin 비번 회전 중간 실패 | bootstrap.sh 멱등성 — Secrets Manager에 저장된 비번 우선 사용, 없으면 초기 secret로 fallback |
| kubeconform이 ArgoCD CRD를 못 찾음 | `-ignore-missing-schemas`로 경고 처리, 핵심 Kubernetes 리소스는 검증 통과 |
| 사용자가 self-signed 경고를 못 넘김 | argocd/README.md에 브라우저별(Chrome/Edge/Safari) 우회 방법 + `argocd login --insecure` curl 예시 |
| 의도적 오류 PR이 CI를 통과해버림 | 다른 오류 패턴(필수 필드 누락, 잘못된 kind) 추가 시도, kubeconform `-strict` 동작 확인 |

## 10. 리스크 / 한계

| 리스크 | 영향 | 완화 |
|---|---|---|
| self-signed TLS로 인한 PRD FR-GO-102 부분 충족 | 검수 시 지적 | HISTORY에 명시적 기록, W2 옵션 1 마이그레이션 가이드 사전 작성 |
| 단독 작업으로 reviews=0 운영 | 실수 머지 가능성 | 필수 status check는 강제, 팀 합류 시 REVIEWS=1 토글 |
| AWS 크레덴셜 발급 지연 | 사용자 액션 1번에서 막힘 | 디자인의 코드/문서 PR만 먼저 머지하고 사용자 액션 2~8은 발급 즉시 실행 |
| Terraform apply 후 비용 발생 (EKS 1.29 + NLB + 노드그룹) | 월 ~$150 추정 | W2 종료 후 사용 패턴 보고 노드 수 조정, W5 Cost 최적화 단계에서 재검토 |

## 11. 후속 작업 (W2 이월)

- ALB Ingress + ACM + Route53 마이그레이션 (FR-GO-102 완전 충족)
- External Secrets Operator 도입 (PRD W2 FR)
- ArgoCD SSO 연동 (Google/GitHub OIDC)
- ArgoCD webhook + GitHub webhook 외부 노출
- ArgoCD CRD 스키마 카탈로그 정비 → kubeconform `-strict` 강화
- PR diff 코멘트 액션 (kustomize-diff-action)

## 12. 산출물 목록

**신규 (10개)**
- `scripts/bootstrap-argocd.sh`
- `scripts/setup-branch-protection.sh`
- `argocd/bootstrap/rbac-cm.yaml`
- `argocd/bootstrap/notifications-cm.yaml`
- `argocd/README.md`
- `.yamllint`
- `.github/pull_request_template.md`
- `CONTRIBUTING.md`
- `docs/argocd-tls-migration.md`
- `README.md` (재작성)

**수정 (6개)**
- `infra/aws/dev/argocd.tf`
- `argocd/applicationset.yaml`
- `.github/workflows/validate-manifests.yml`
- `docs/project-management/workflow/WORKFLOW_gitops_W1.md`
- `docs/project-management/task/TASK_gitops.md`
- `docs/project-management/history/HISTORY_gitops.md`
