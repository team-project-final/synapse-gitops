# Runbook: image-updater A안 — main 보호 bypass (dev/staging)

> 런북 [`image-updater-ecr-setup.md`](./image-updater-ecr-setup.md) §A의 라이브 실행 절차를 스크립트화.
> **상태**: 비용 0 준비 완료(아래) / 라이브 실행은 조건부 EKS 사이클(과금).
> ⚠️ main `main-protection` ruleset 변경 포함 — 봇만 bypass, 사람은 PR 유지.

## 사전 (비용 0, 완료)
- engagement-svc dev overlay `newTag: 1.0.0` (semver 전략 호환) — `apps/engagement-svc/overlays/dev/kustomization.yaml`에서 핀 완료.
- 전용 봇 PAT(`contents:write`만, fine-grained)를 AWS SM `synapse/gitops/git-token`에 저장 (라이브 직전).

## 라이브 실행 (조건부 사이클 — 과금)

1. **ruleset ID 확인**
   ```bash
   gh api repos/team-project-final/synapse-gitops/rulesets --jq '.[] | "\(.id)\t\(.name)"'
   ```

2. **bypass_actors에 봇만 추가** (사람 직접 push는 계속 PR 필수)
   ```bash
   # 봇 actor_id 확인 후 ruleset.json 준비:
   #   bypass_actors=[{"actor_id":<봇>,"actor_type":"Integration","bypass_mode":"always"}]
   gh api -X PUT repos/team-project-final/synapse-gitops/rulesets/<RULESET_ID> --input ruleset-bypass.json
   ```

3. **ECR 인증 배선** (bring-up image-updater phase) — `argocd-image-updater-config` registries.conf + `credentials: pullsecret:argocd/ecr-creds` (`aws ecr get-login-password` 토큰, 12h 만료).

4. **write-back E2E 검증**
   - ECR engagement-svc 에 상위 semver push: 예 `2.0.0`
   - image-updater 감지 → write-back 커밋(main, 봇 bypass) → ArgoCD sync → dev에 `:2.0.0` 반영 확인.

5. **운영 보강(백로그)** — ECR 토큰 12h 만료 → 갱신 CronJob; registries.conf/pull-secret을 bring-up phase로 자동화.

## prod (W4+) = B안
`git-branch: main:image-updates-<app>` 별도 브랜치 + GH Action(PR 생성 + CI 후 auto-merge). main 보호 유지. ([`image-updater-ecr-setup.md`](./image-updater-ecr-setup.md) §B)
