# W5 잔여 백로그 정리 + dev overlay SHA→semver 핀 — 설계

> **작성**: 2026-06-09 · **상태**: 설계 승인됨 · **다음**: writing-plans
> **정본 추적**: `docs/superpowers/HANDOFF_W5.md`(갱신 대상) + GH 이슈

## 1. 목적

W5 윈도우2 라이브 완주(2026-06-08, PR #145~#152) 이후 남은 잔여 5건을 **추적 가능한 정본으로 정리**하고, 그중 외부 블로커가 없는 **항목5(dev overlay SHA→semver 핀)의 즉시 실행분을 착수**한다.

성격이 다른 5건이 메모리·HANDOFF·이슈에 흩어져 있어, 단일 정본 표 + GH 이슈로 가시화하는 것이 1차 목표다. 동시에 비용 0으로 지금 끝낼 수 있는 overlay 핀은 미루지 않고 실행한다.

## 2. 잔여 5건 (정본 표)

| # | 항목 | owner | blocker | next-action | 완료조건 | 추적 |
|---|------|-------|---------|-------------|---------|------|
| 1 | Step11 team-lead 따라하기 | team-lead | 가용시간 | 런북만 보고 1택 독립 복구 1회 | Step11 Done | 신규 이슈 |
| 2 | staging 환경 DB 분리(항목8) | velka | **team-lead 비용 결정** | 전용 DB/인스턴스 terraform | 환경 격리(staging≠dev RDS) | 신규 이슈 |
| 3 | #126 ruleset 축소 | velka | shared `deploy-service.yml` App 전환 동기화 | deploy-service를 GitHub App 토큰화 후 bypass 축소 | Maintain bypass 제거/축소 | #126 |
| 4 | learning-ai dev 복구 | 앱팀→velka | **앱팀 PR #63 수정 이미지** | 수정 이미지 ECR push→overlay bump | #144 close(dev Healthy) | #144 |
| 5 | dev overlay SHA→semver 핀 | velka | overlay분 없음 / ECR 재태그는 라이브 윈도우 | overlay 핀(이번 PR) → ECR SHA→1.0.0 재태그(윈도우) | 6앱 IU `semver` 정상(skip 해소) | 신규 이슈 |

**블로커 분류**: 1·2·4는 외부(team-lead·앱팀)에 블록되어 코드로 지금 끝낼 수 없음 → 이슈/대기로 트래킹. 3은 cross-repo(shared)+org admin 수반. 5는 overlay분이 이 레포에서 단독 완결 가능(런타임 반영만 윈도우 의존).

## 3. 실행분 — dev overlay SHA→semver 핀

### 3.1 배경

`argocd/applicationset.yaml`은 IU(argocd-image-updater)를 `update-strategy: semver` + `allow-tags: regexp:^[0-9]+\.[0-9]+\.[0-9]+$`로 설정한다. semver 전략은 kustomization의 현재 `newTag`를 semver로 파싱해 ECR 후보 태그와 비교하는데, 현재 태그가 SHA(40자) 또는 `dev-latest`면 `Invalid Semantic Version`으로 **skip**된다. engagement-svc만 `1.0.0`으로 핀되어 정상.

### 3.2 변경 대상 (6개 `apps/<app>/overlays/dev/kustomization.yaml`)

| 앱 | 현재 newTag | 변경 후 | 주석 |
|----|-------------|---------|------|
| knowledge-svc | `dev-latest` | `1.0.0` | 공용 문구(engagement 동일) |
| platform-svc | `bc5440144780fbaaa53a74e2e6d8baef0b8beafd` | `1.0.0` | 공용 |
| gateway | `9e4f190a37efd52abe24c72fb659d98c350f8988` | `1.0.0` | 공용 |
| frontend | `e4532fee21683cf88b21937f9b8977d7f9037ad3` | `1.0.0` | 공용 |
| learning-card | `acafc06b6fc6ec1bcb076f0ccb4487ad29da9274` | `1.0.0` | 공용 |
| **learning-ai** | `acafc06b6fc6ec1bcb076f0ccb4487ad29da9274` | `1.0.0` | **#144 연결 주석** |

- engagement-svc는 이미 `1.0.0` → 무변경. 베이스 버전은 전부 **`1.0.0`**으로 통일(engagement 패턴).
- prod/staging overlay는 **건드리지 않음**. dev ApplicationSet(`applicationset.yaml`)만 IU 대상이며, prod/staging은 별도 ApplicationSet(`applicationset-prod/staging.yaml`)이라 범위 확산 방지.

### 3.3 주석 규약

공용 5개 주석(engagement 기존 문구 정합):
```yaml
images:
  - name: ghcr.io/team-project-final/synapse-<app>
    newName: 963773969059.dkr.ecr.ap-northeast-2.amazonaws.com/synapse/<app>
    # image-updater A안: semver update-strategy 호환 위해 semver 베이스라인으로 핀 (was <SHA|dev-latest>).
    # ECR에 1.0.0 태그 존재 필요 — 다음 라이브 윈도우에서 SHA→1.0.0 재태그
    # (aws ecr batch-get-image | put-image, 동일 digest) 선결. 미선결 시 sync 후 ImagePullBackOff.
    newTag: 1.0.0
```

learning-ai 전용 주석(#144 결합):
```yaml
    # image-updater A안: semver 베이스라인 핀 (was acafc06b…).
    # 단, ECR 1.0.0은 #144(aiokafka ssl_context CrashLoop) 수정 이미지(앱팀 PR #63)에 재태그할 것.
    # 현재 acafc06b digest는 CrashLoop이므로 그 digest로 재태그 금지.
    newTag: 1.0.0
```

### 3.4 런타임 리스크와 완화

overlay를 `1.0.0`으로 바꾸면 ArgoCD가 다음 sync에서 `ECR/<app>:1.0.0`을 당긴다. ECR엔 현재 SHA 태그만 존재하므로 **1.0.0이 없으면 ImagePullBackOff**. 클러스터는 현재 destroy(과금0) 상태라 지금 커밋 자체는 무해하나, **다음 bring-up 전 ECR 재태그가 선결**이다.

완화: (a) 각 overlay 주석에 선결 조건 명시, (b) HANDOFF_W5 윈도우 절차에 `aws ecr batch-get-image|put-image` 재태그 단계 추가, (c) 신규 이슈5를 ECR 재태그 완료까지 open 유지. learning-ai는 #144 수정 이미지 의존이므로 재태그 대상 digest가 다름.

### 3.5 검증 (비용 0)

- 변경한 6개 각각 `kustomize build apps/<app>/overlays/dev` 성공.
- CI `validate`(kubeconform strict + yamllint) 통과.
- 클러스터 sync/ImagePull 검증은 다음 라이브 윈도우(ECR 재태그 후). 이번 PR 범위 아님.

## 4. 추적 아티팩트

1. **`docs/superpowers/HANDOFF_W5.md` 갱신** — 현재 윈도우2 이전 작성분(stale: #121/#122를 open으로 표기하나 close됨). 윈도우2 완료 반영 + §2 잔여 5건 정본 표로 재작성.
2. **`docs/project-management/task/TASK_gitops.md`** — 머리말 또는 Step12 꼬리에 "잔여 5건 = HANDOFF_W5 표" 한 줄 동기화.
3. **GH 이슈 신규 3개**(이슈 없는 1·2·5):
   - `[ops] Step11 Done 조건: team-lead 런북 따라하기 1회` — async, `on-call.md`/`W5_WINDOW_2.md` Phase5 참조.
   - `[infra] staging 환경 DB 분리 (항목8) — team-lead 비용 결정 선행` — `2026-06-08-w3-w4-incomplete-audit-design.md` §4 참조.
   - `[ops] dev overlay SHA/dev-latest → semver 핀 + ECR 재태그 (6앱)` — 이번 PR이 overlay분 부분 해소, ECR 재태그는 open 유지.
4. 기존 #144·#126과 상호 참조.

## 5. 전달 구성 (2 PR + 이슈)

- **PR1** `fix/sha-semver-pin-dev-overlays`: overlay 6파일(이슈5 참조). → PR → main(보호: PR+`validate`). ArgoCD가 main sync(반영은 윈도우 ECR 재태그 후).
- **PR2** `docs/w5-remaining-backlog`: HANDOFF_W5 + TASK_gitops + 본 spec 문서.
- **이슈 3개**: `gh issue create`로 별도 생성.

배포 워크플로 정합: 이 레포는 `fix/*`·`docs/*` 피처브랜치 → PR → main이 표준이며 ArgoCD는 `targetRevision: main`. main 직접 푸시는 하지 않는다.

## 6. 범위 밖 (YAGNI)

- prod/staging overlay 핀 — IU 대상 아님, 범위 확산 방지.
- ECR 재태그 실제 실행 — 라이브 윈도우(과금) 필요, 이번 비용0 범위 밖. 절차만 핸드오프에 기록.
- 항목 1·2·3·4의 실행 — 외부 블로커. 이슈/대기로 트래킹만.
- IU update-strategy 변경(digest 등) — 팀 전략(semver) 유지, 변경은 별건.
