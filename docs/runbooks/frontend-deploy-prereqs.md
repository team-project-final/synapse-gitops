# Runbook: 서비스 ECR 배포 선행조건 (frontend 사례)

> **상태**: frontend 적용 검증 — #2 무조치(와일드카드 신뢰정책), #3 repo-level 시크릿으로 해소.
> **작성일**: 2026-06-07
> **대상**: 새 `synapse-*` 서비스에 `deploy.yml`(shared `deploy-service.yml@main` 호출)을 붙일 때 공통 적용.

## 배경

각 서비스 레포의 `.github/workflows/deploy.yml`은 `synapse-shared/.github/workflows/deploy-service.yml@main`을 호출한다. 이 재사용 워크플로는 `main` push 시:

1. OIDC로 AWS 역할(`AWS_ROLE_ARN`) assume
2. ECR 로그인 → `docker build` → `${ECR}/${ecr_repository}:<commit-sha>` 와 `:dev-latest` push
3. `synapse-gitops` clone → `apps/<gitops_app>/overlays/dev/kustomization.yaml`의 `.images[0].newTag`를 commit SHA로 bump → push

따라서 **이미지 태그는 commit SHA**이고, **이 CI가 직접 gitops dev overlay를 갱신**한다(= argocd-image-updater의 semver 경로와는 별개. image-updater는 ECR의 semver 태그를 감시하지만, 이 CI 경로는 SHA로 직접 write-back).

빌드는 plain `docker build`라 빌드 도구 무관 — JVM(gradle)이든 Flutter(web)든 Dockerfile만 있으면 동작한다.

## 선행조건 3종

`deploy.yml`을 머지하기 전(또는 첫 실행 실패를 감수하고 직후) 아래가 갖춰져야 한다.

### #1 ECR 리포 생성 (수동)

ECR 리포는 Terraform으로 관리되지 않는다(`infra/`에 `aws_ecr_repository` 없음) → **수동 생성**.

```bash
aws ecr create-repository --repository-name synapse/<svc> --region ap-northeast-2
# 예: synapse/frontend
```

없으면 `Build and push image` 단계가 `repository does not exist`로 실패한다.

### #2 GHA OIDC 역할 신뢰정책

`AWS_ROLE_ARN`이 가리키는 역할: **`synapse-gha-deploy-role`** (account `963773969059`).
신뢰정책 `sub` 조건이 해당 레포의 OIDC 토큰을 허용해야 한다. 확인:

```bash
aws iam get-role --role-name synapse-gha-deploy-role \
  --query 'Role.AssumeRolePolicyDocument.Statement[].Condition' --output json
```

현재(2026-06-07) 값:

```json
{
  "StringEquals": { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" },
  "StringLike":   { "token.actions.githubusercontent.com:sub": "repo:team-project-final/synapse-*:*" }
}
```

`synapse-*` **와일드카드**이므로 **모든 `synapse-` 접두 레포는 자동 포함** → 신규 `synapse-*` 서비스는 **#2 조치 불필요**.
(개별 나열 방식으로 바뀌었다면, 기존 목록 누락 없이 `repo:team-project-final/synapse-<svc>:*`를 추가해 `aws iam update-assume-role-policy --role-name synapse-gha-deploy-role --policy-document file://trust.json`.)

실패 시 증상: `Configure AWS credentials (OIDC)` 단계가 `Not authorized to perform sts:AssumeRoleWithWebIdentity`.

### #3 시크릿 (`AWS_ROLE_ARN`, `GITOPS_TOKEN`)

`deploy.yml`은 `secrets: inherit`로 호출하므로, 호출 레포에서 두 시크릿이 보여야 한다. **repo-level 시크릿이 동명 org 시크릿보다 우선**한다.

| 시크릿 | 출처 | 비고 |
|---|---|---|
| `AWS_ROLE_ARN` | org-level (기본). org admin 권한 없으면 **repo-level로 대체 가능** | 값 = `arn:aws:iam::963773969059:role/synapse-gha-deploy-role` |
| `GITOPS_TOKEN` | repo-level (각 svc에 등록됨) | fine-grained PAT, `contents:write on synapse-gitops`, 90일 회전(SECRETS.md) |

**org admin인 경우** — org 시크릿 범위에 레포 포함 확인/추가:
```bash
gh auth refresh -h github.com -s admin:org      # org admin 계정만 통과
gh secret list --org team-project-final          # AWS_ROLE_ARN Visibility 확인
#  All repositories → 자동 포함 / Selected → 아래로 추가
gh api -X PUT /orgs/team-project-final/actions/secrets/AWS_ROLE_ARN/repositories/$(gh api /repos/team-project-final/synapse-<svc> --jq .id)
```

**org admin이 아닌 경우(권장 폴백)** — repo-level 시크릿으로 설정(repo admin이면 가능):
```bash
gh secret set AWS_ROLE_ARN --repo team-project-final/synapse-<svc> \
  --body "arn:aws:iam::963773969059:role/synapse-gha-deploy-role"
gh secret list --repo team-project-final/synapse-<svc>   # AWS_ROLE_ARN, GITOPS_TOKEN 둘 다 확인
```

> ⚠️ **함정**: `--body "...role/$ROLE"`처럼 셸 변수를 쓰는데 변수가 미설정이면 `arn:...:role/`(역할명 누락)로 **조용히 저장**된다(gh는 성공으로 표시, 값은 되읽기 불가). **전체 ARN을 리터럴로** 넣을 것. 의심되면 그냥 다시 set 하면 된다(idempotent).

## 검증 (머지 직후)

`workflow_dispatch`는 워크플로가 `main`에 있어야 활성화되므로 사전 dry-run 불가 → **머지 후 첫 실행**으로 확인.

```bash
gh run watch -R team-project-final/synapse-<svc> \
  "$(gh run list -R team-project-final/synapse-<svc> -w Deploy -L1 --json databaseId --jq '.[0].databaseId')"
```

단계별 매핑: `Configure AWS credentials`→#2, `Build and push image`→#1, `Bump gitops image tag`→#3(`GITOPS_TOKEN`). 통과 시 gitops `apps/<svc>/overlays/dev/kustomization.yaml`에 `deploy: bump <svc> to <sha>` 커밋이 생긴다.

## frontend 적용 결과 (2026-06-07)

- #1 ECR `synapse/frontend` 생성 — 완료
- #2 신뢰정책 — `synapse-*` 와일드카드라 무조치
- #3 `GITOPS_TOKEN` 기존 존재 / `AWS_ROLE_ARN` repo-level 설정(org admin 부재) — 완료
- 워크플로 PR #22(`synapse-frontend`) — 위 충족 후 머지 시 dev 배포 트리거

> 관련: `image-updater-ecr-setup.md`(in-cluster image-updater 경로), shared `deploy-service.yml`, `SECRETS.md`. dev EKS 미가동 시 배포는 재프로비저닝 시점에 발현.
