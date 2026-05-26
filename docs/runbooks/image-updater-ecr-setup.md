# Runbook: ArgoCD Image Updater — ECR 인증 + git write-back (W2 S6)

> **상태**: EKS 설치·ECR 인증·git repo-cred **검증 완료**. write-back E2E는 설계 결정(아래 A/B) 후 완료 가능.
> **검증일**: 2026-05-26 (실 EKS, A2/S6 사이클)

## 구성 (bring-up.sh `image-updater` phase가 자동화)

1. **ECR IRSA** (`infra/aws/dev/image-updater-irsa.tf`): `synapse-dev-image-updater-role` + `AmazonEC2ContainerRegistryReadOnly`, SA `argocd:argocd-image-updater`.
2. **컨트롤러 설치**: `argoproj-labs/argocd-image-updater` **v0.15.2** install.yaml (`stable`/`master` ref는 404 — 버전 핀 필수).
3. **git write-back 자격**: AWS SM `synapse/gitops/git-token`(PAT) → ESO → ArgoCD repository 시크릿(`infra/external-secrets/argocd-repo-externalsecret.yaml`). ESO IAM 정책에 `synapse/gitops/*` 포함 필요.
4. **ECR registry 인증** (수동 — 자동화 미완): IRSA만으로는 레지스트리 Docker API 인증 안 됨("no basic auth credentials"). `argocd-image-updater-config` ConfigMap `registries.conf`에 ECR 등록 + **`credentials: pullsecret:argocd/ecr-creds`** (주의: `pullsecret` — 하이픈 없음). pull-secret은 `aws ecr get-login-password`로 생성한 docker-registry 시크릿. **토큰 12h 만료** → 운영은 토큰 갱신 CronJob 필요(현재 미구현, 테스트는 정적 토큰).

```yaml
# argocd-image-updater-config 의 registries.conf
registries:
  - name: ECR
    prefix: 963773969059.dkr.ecr.ap-northeast-2.amazonaws.com
    api_url: https://963773969059.dkr.ecr.ap-northeast-2.amazonaws.com
    ping: yes
    credentials: pullsecret:argocd/ecr-creds
    credsexpire: 10h
```

## write-back E2E 잔여 블록 2건

### ① overlay 태그가 semver 전략과 불일치
dev overlay가 `newTag: dev-latest`인데 update-strategy=`semver` → "Invalid Semantic Version". semver 전략을 쓰려면 overlay를 semver 태그(예 `1.0.0`)로 핀해야 함. (또는 strategy를 `latest`/`digest`로 변경.)

### ② main 보호 ruleset이 직접 push 거부
image-updater write-back은 `git-branch: main`에 **직접 push**. main `main-protection` ruleset = `pull_request`+`required_status_checks`+`non_fast_forward`, **bypass_actors 비어있음** → 봇 직접 push 거부.

## 해소 방안 비교 (A/B)

| 기준 | A. main 보호 완화 (bypass) | B. PR 기반 write-back |
|---|---|---|
| 방식 | ruleset bypass에 image-updater 전용 봇 추가 | `git-branch: main:image-updates-<app>` 별도 브랜치 → GH Action이 PR+auto-merge |
| 난이도 | 낮음 | 높음 (PR 자동화 구현) |
| 보안 | main에 봇 직접 push(CI/리뷰 우회) | 강함(main PR+CI 유지) |
| "5분 내 반영"(Step6) | 즉시(유리) | PR+CI 지연(auto-merge 필요) |
| 감사성 | 약함 | 강함 |

**권고**: dev/staging은 **A**(전용 최소권한 봇 bypass — 이미지 bump는 저위험 newTag), prod 자동화 도입(W4+) 시 **B**로 격상.

## 완료 절차 (결정 후)
1. A 또는 B 적용
2. dev overlay engagement-svc를 semver 태그로 핀
3. ECR에 상위 semver push → image-updater 감지 → write-back → ArgoCD sync 확인
4. ECR 토큰 갱신 CronJob 추가(운영)
