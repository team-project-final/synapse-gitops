# Incident: ArgoCD Sync 실패

> 대상 환경: ArgoCD (ns `argocd`) — dev/staging auto sync, prod manual
> 관련 실사례: T-020, T-021, T-022, T-070 (`docs/runbooks/troubleshooting-infra.md`)
> CLI 전제: SSM 터널(`scripts/lib/eks-tunnel.sh`) + `argocd --core`, `export ARGOCD_NAMESPACE=argocd`

## 증상

- App이 `OutOfSync` 지속 또는 sync operation `Failed`
- ArgoCD UI 에러 배너 / `argocd app get` 의 CONDITIONS 에러
- IU write-back의 경우: `image-updater-<svc>` 브랜치는 갱신되는데 main에 반영 안 됨

## 진단

```bash
# 1. 실패 앱 식별
argocd app list | grep -vE "Synced.*Healthy"
# 2. 실패 원인 (operation 메시지가 1차 근거)
argocd app get <app> --show-operation
argocd app diff <app>
# 3. 로컬 재현 — manifest 원인인지 즉시 판별
kustomize build apps/<svc>/overlays/<env>
```

빈발 원인 체크리스트:

| # | 에러 패턴 | 원인 (실사례) | 조치 방향 |
|---|---|---|---|
| 1 | `namespaces "<ns>" not found` | 네임스페이스 부재 (T-070) | ns 매니페스트 추가 또는 syncOption `CreateNamespace=true` |
| 2 | `metadata.annotations: Too long` | CRD apply 방식 (T-020) | `--server-side` 적용 |
| 3 | `no matches for kind` | CRD 미설치 (T-021) | 선행 CRD/컨트롤러 설치 확인 (bring-up 페이즈 순서) |
| 4 | server-side `conflict` | 필드 소유권 충돌 (T-022) | `--force-conflicts` 또는 소유자 정리 |
| 5 | AppProject 거부 (`not permitted`) | sourceRepos/destinations 제약 | `argocd proj get <proj>` 로 허용 범위 확인 |
| 6 | kustomize build 실패 | overlay 참조 오류 | 3번 로컬 재현 결과의 에러 라인 수정 |

**IU write-back 미반영** (PR write-back 경로, PR #127):

```bash
# 브랜치는 push됐는가
git ls-remote origin 'image-updater-*'
# PR 자동 생성 워크플로가 돌았는가
gh run list --workflow=image-updater-pr.yml --limit 5
```
- 브랜치 없음 → image-updater Pod 로그 확인 (`kubectl logs -n argocd deploy/argocd-image-updater`) — ECR 자격(`no basic auth credentials`, gitops#122 이력) 여부
- 브랜치 있고 PR 없음 → `GITOPS_TOKEN` 시크릿 만료/권한 확인 (repo Settings → Secrets)

## 조치

1. manifest 원인 → 수정 PR → 머지 → 재sync (`argocd app sync <app>`)
2. 일시 장애(네트워크 등) → `argocd app sync <app> --retry-limit 3`
3. prod는 수동 승인 게이트 유지 — 수정 머지 후에도 **gitops-admin이 명시적으로 sync**

## 에스컬레이션 기준

- 단일 앱 30분 미해결 → L2
- **전 앱 동시 OutOfSync/Unknown** (application-controller·repo-server 장애 의심) → 즉시 L2 + `kubectl get pods -n argocd` 상태 첨부

## 회피 방법

- PR 전 `kustomize build` 로컬 실행 습관 — CI(`validate-manifests.yml`)와 동일 검증
- CRD 포함 인프라는 bring-up 페이즈 순서에 등록 (수동 apply 금지)

## 사후 점검

- [ ] 신규 에러 패턴이면 본 런북 표 + `troubleshooting-infra.md` Discovery Log 추가
- [ ] sync 실패가 잦은 앱은 syncOptions/retry 정책 재검토
