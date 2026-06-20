# Contributing — synapse-gitops

## 브랜치 네이밍
- `feature/<step>-<slug>` — 신규 기능 (예: `feature/w1-argocd-bootstrap-finalize`)
- `fix/<issue>-<slug>` — 버그 수정
- `docs/<slug>` — 문서만
- `ci/<slug>` — CI/CD만
- `chore/<slug>` — 기타

## 커밋 메시지
Conventional Commits 형식:
- `feat(<scope>): ...` — 새 기능
- `fix(<scope>): ...` — 수정
- `chore(<scope>): ...` — 잡일
- `docs(<scope>): ...` — 문서
- `ci(<scope>): ...` — CI/CD
- scope: `argocd`, `infra`, `apps`, `scripts`, `ci`, `pm`

## 로컬 검증 (PR 올리기 전 필수)

### 사전 도구 설치
```bash
# macOS
brew install kustomize yamllint kubeconform
# Linux
curl -sSL https://github.com/yannh/kubeconform/releases/download/v0.6.7/kubeconform-linux-amd64.tar.gz | tar xz
sudo mv kubeconform /usr/local/bin/
pip install yamllint
```

### 검증 명령
```bash
# 0) Phase D release-hardening contract check (PowerShell)
pwsh -File scripts/verify-phase-d-release-hardening.ps1

# 1) YAML lint
yamllint -c .yamllint apps/ argocd/ infra/

# 2) Kustomize build (모든 overlay)
for o in apps/*/overlays/*/kustomization.yaml; do
  kustomize build "$(dirname "$o")" > /dev/null && echo "OK: $o"
done

# 3) Kubeconform 스키마 검증
for o in apps/*/overlays/*/kustomization.yaml; do
  kustomize build "$(dirname "$o")" | kubeconform \
    -strict -ignore-missing-schemas -summary -output text
done

# 4) Terraform (해당 시)
cd infra/aws/dev && terraform fmt -check && terraform validate

# 5) Shell script (해당 시)
bash -n scripts/*.sh
```

## PR 절차
1. `main`에서 브랜치 생성
2. 작은 단위 commit (한 PR에 평균 5~10 commit)
3. 로컬 검증 통과 확인
4. PR 생성 (템플릿 따라 작성)
5. CI 통과 + 리뷰 통과 → 머지

## 새 앱 추가
[argocd/README.md](./argocd/README.md) 참조.

## 문제 해결
- CI 실패: `yamllint` / `kustomize build` / `kubeconform` 출력에서 파일+라인 확인 후 수정
- ArgoCD sync 실패: `argocd app get synapse-<svc>-<env>` → conditions 확인
- TLS 경고: 옵션 2 self-signed라 정상. [docs/argocd-tls-migration.md](./docs/argocd-tls-migration.md)에서 옵션 1로 마이그레이션 절차 참조
