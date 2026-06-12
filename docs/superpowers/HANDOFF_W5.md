# W5 핸드오프: synapse-gitops — 잔여 5건 처리 결과 (2026-06-09 라이브 완료)

> **갱신**: 2026-06-10(#144 close 정합) · **발표**: 2026-06-15
> **정본 허브**: synapse-shared `HANDOFF_HUB.md`(team-lead 유지)

## 0. 경과

- **윈도우2(2026-06-08, PR #145~#152)**: #121·#122 close, Step11 시뮬·HPA, #126 옵션3 라이브, #144 신규 발견.
- **정리 세션(2026-06-09, PR #158~#160)**: 잔여 5건 정본화 + 실행.
- **라이브 윈도우(2026-06-09)**: dev EKS bring-up → 검증 → destroy(63 destroyed·과금0).

## 1. 잔여 5건 — 처리 결과

| # | 항목 | 추적 | 상태 | 근거 |
|---|------|------|------|------|
| 1 | Step11 드릴 | #155 | ✅ **CLOSED** | operator 라이브 드릴(CrashLoop·OOM 재현·복구) |
| 2 | staging DB 분리(항목8) | #156 | ✅ **CLOSED** | 전용 RDS `synapse-staging-postgres`(PR #160), 인스턴스 격리 검증 |
| 3 | #126 ruleset 축소 | #126 | ✅ **CLOSED** | 옵션3 App전환 완료, Maintain bypass 수용(팀 결정) |
| 4 | learning-ai dev 복구 | #144 | ✅ **CLOSED** | learning-svc PR #67 재수정(`9140e597`) — learning-ai 1/1 Running·RESTARTS 0·ssl_context 0건 (2026-06-09 2차 라이브) |
| 5 | dev overlay SHA→semver 핀 | #157 | ✅ **CLOSED** | 핀(PR #158)+ECR 6앱 1.0.0 재태그+라이브 배포 검증 |

## 2. ✅ #144 (CLOSED) — 2차 라이브에서 재수정 검증

1차 라이브에서 `learning-ai:1.0.0`(=`3774e2e6`)이 동일 ssl_context CrashLoop → **앱팀 PR #63 fix 무효** 입증. 원인: `3774e2e6`은 `fix(avro) #64` 빌드라 ssl_context 수정 미포함(**코드 머지 ≠ 빌드 반영**).

**실수정**: `synapse-learning-svc` PR #67 — `app/kafka/ssl_support.py`(`kafka_ssl_context()`=SSL시 `create_ssl_context()`) + producer/consumer `ssl_context=` 전달 + TLS 단위테스트(앱팀이 빠뜨린 검증). CI green → admin 머지 → ECR `learning-ai:9140e597` 푸시 + gitops bump.

**2차 라이브**: `9140e597` 배포 → learning-ai 1/1 Running·RESTARTS 0·Healthy, ssl_context 에러 0건 → **#144 close**.

## 3. 라이브 윈도우 운영 메모 (재발 방지)

- **서비스별 DB 5종 수동 생성**: bring-up은 `synapse_platform`/`engagement`/`knowledge`/`learning`/`ai`를 자동생성 안 함. RDS 새로 뜨면 psql `CREATE DATABASE` 선행(미생성 시 Spring `database does not exist` 크래시). staging 전용 RDS도 동일.
- **selfHeal/ApplicationSet**: resource 패치(limit 등) 즉시 자동원복(드리프트 복구). `set env` override는 3-way merge로 미원복 → 직접 제거.
- **ECR 재태그**: `batch-get-image`→`put-image` 라운드트립은 매니페스트를 재직렬화 → manifest digest는 달라지나 **config·layer는 동일**(컨테이너 바이트 동일). 검증은 config digest 대조로.

## 4. 잔여 후속 (블록/정리)

- **#144**: 앱팀 재수정(위 §2) → 다음 윈도우 재검증.
- **engagement-svc-dev**: overlay가 phantom `1.0.1`(#122 데모 IU bump 잔재, ECR 부재)이라 ImagePullBackOff → `1.0.0` 정정 PR(#161). staging/prod 정상.
- **learning-card-staging**: staging RDS 연결은 정상(DB 무관), 앱레벨 Degraded → 다음 윈도우 `kubectl logs` 조사 (후속 A, 이슈 #164). <!-- ✅ 2026-06-12 close: 콜드스타트 안정화(PR #172) 양 환경 검증 — dev 1/1·staging 2/2 RESTARTS 0. 잔여 readiness 401은 learning-svc#74 -->

## 5. 레포 상태

- **OPEN 이슈**: 0건(#144 포함 W5 잔여 전부 close). 저우선 후속 A/B/C는 별도 이슈 추적(HANDOFF_2026-06-09-followups §2).
- **main HEAD**: PR #160 머지분(staging 전용 RDS). + #161(engagement 정정) 진행.
- **설계/플랜**: `docs/superpowers/specs/2026-06-09-{w5-remaining-backlog-sha-semver-pin,staging-dedicated-rds}-design.md`, `docs/superpowers/plans/2026-06-09-w5-remaining-backlog-sha-semver-pin.md`.
