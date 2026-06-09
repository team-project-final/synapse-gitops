# W5 핸드오프: synapse-gitops — 잔여 5건 (윈도우2 완료 후)

> **갱신**: 2026-06-09 · **이전**: 2026-06-08(윈도우2 이관, 현재 stale 해소) · **발표**: 2026-06-15
> **정본 허브**: synapse-shared `HANDOFF_HUB.md`(team-lead 유지)

## 0. 윈도우2 완료 (2026-06-08, PR #145~#152, destroy로 과금0)

#121(prod 외부노출)·#122(IU write-back E2E) **close**. Step11 시뮬 3종+알람 경로·HPA 검증. #126 옵션3(GitHub App 토큰) 라이브. #144(learning-ai aiokafka ssl_context) 신규 발견. 상세: 메모리 `w5-window2-live-complete` / `HISTORY_gitops.md`.

## 1. 잔여 5건 (정본 표)

| # | 항목 | owner | blocker | next-action | 완료조건 | 추적 |
|---|------|-------|---------|-------------|---------|------|
| 1 | Step11 team-lead 따라하기 | team-lead | 가용시간 | 런북만 보고 1택 독립 복구 1회 | Step11 Done | #155 |
| 2 | staging 환경 DB 분리(항목8) | velka | **team-lead 비용 결정** | 전용 DB/인스턴스 terraform | staging≠dev RDS(환경 격리) | #156 |
| 3 | #126 ruleset 축소 | velka | shared `deploy-service.yml` App 전환 동기화 | deploy-service GitHub App 토큰화 후 bypass 축소 | Maintain bypass 제거/축소 | #126 |
| 4 | learning-ai dev 복구 | velka | (앱팀 PR #63 머지·`3774e2e6` bump 완료 — 라이브 확인만 잔여) | 다음 윈도우 sync 후 learning-ai-dev CrashLoop→Running 확인 | #144 close | #144 |
| 5 | dev overlay SHA→semver 핀 | velka | overlay분 없음(PR #158) / ECR 재태그는 윈도우 | overlay 핀(PR #158 머지)→ECR 재태그(윈도우) | 6앱 IU semver 정상(skip 해소) | #157 |

**블로커 분류**: 1·2는 외부(team-lead) 블록 → 이슈/대기 트래킹. 3은 cross-repo(shared)+org admin. 4는 앱팀 수정 완료, 라이브 확인만(윈도우). 5는 overlay분 완결(PR #158), 런타임만 윈도우 의존.

## 2. 다음 라이브 윈도우 선결 절차 (항목5 ECR 재태그)

overlay는 PR #158로 `1.0.0` 핀됨. bring-up/sync 전 ECR에 1.0.0 태그가 없으면 ImagePullBackOff → **6앱 각각 재태그**(현재 박혀있던 digest를 1.0.0으로도 태깅, 동일 digest):

| 앱 | 1.0.0 ← 재태그 대상(직전 SHA/태그) |
|----|-----------------------------------|
| knowledge-svc | dev-latest 가리키던 digest |
| platform-svc | `bc5440144780…` |
| gateway | `9e4f190a37ef…` |
| frontend | `e4532fee2168…` |
| learning-card | `3774e2e6bcf2…` |
| learning-ai | `3774e2e6bcf2…` (= #144 수정 이미지, 앱팀 PR #63) |

```bash
REGION=ap-northeast-2
for pair in "knowledge-svc:dev-latest" "platform-svc:bc5440144780fbaaa53a74e2e6d8baef0b8beafd" \
            "gateway:9e4f190a37efd52abe24c72fb659d98c350f8988" "frontend:e4532fee21683cf88b21937f9b8977d7f9037ad3" \
            "learning-card:3774e2e6bcf216c62eea3578e75a74d1dca00be5" "learning-ai:3774e2e6bcf216c62eea3578e75a74d1dca00be5"; do
  app="${pair%%:*}"; src="${pair##*:}"
  MANIFEST=$(aws ecr batch-get-image --repository-name synapse/$app --image-ids imageTag=$src \
    --region $REGION --query 'images[0].imageManifest' --output text)
  aws ecr put-image --repository-name synapse/$app --image-tag 1.0.0 \
    --image-manifest "$MANIFEST" --region $REGION
done
```
learning-ai의 1.0.0은 #144 수정 이미지 `3774e2e6`에 매핑되므로, 재태그 후 dev sync로 learning-ai-dev CrashLoop→Running 확인 = 항목4 #144 close 절차와 합류.

## 3. 레포 상태

- **OPEN 이슈**: #126·#144 · #155·#156·#157. #91·#92·#120·#121·#122 close.
- **CI**: main 보호(PR + `validate`/diff-comment/parse).
- **설계/플랜**: `docs/superpowers/specs/2026-06-09-w5-remaining-backlog-sha-semver-pin-design.md`, `docs/superpowers/plans/2026-06-09-w5-remaining-backlog-sha-semver-pin.md`.
- **실행 PR**: #158(overlay 핀), 본 PR(추적 문서).
