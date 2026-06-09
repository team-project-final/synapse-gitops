# W5 핸드오프: synapse-gitops — 잔여 5건 처리 결과 (2026-06-09 라이브 완료)

> **갱신**: 2026-06-09(라이브 윈도우 후) · **발표**: 2026-06-15
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
| 4 | learning-ai dev 복구 | #144 | ⚠️ **OPEN** | **라이브가 앱팀 PR #63 fix 무효 입증** — 아래 §2 |
| 5 | dev overlay SHA→semver 핀 | #157 | ✅ **CLOSED** | 핀(PR #158)+ECR 6앱 1.0.0 재태그+라이브 배포 검증 |

## 2. ⚠️ #144 (유일 OPEN) — 앱팀 재수정 대기

라이브 검증에서 `learning-ai:1.0.0`(=`3774e2e6`, 앱팀 PR #63 빌드, digest `sha256:0a4dec…b8f479025942`)이 **동일 ssl_context 에러로 CrashLoop**:
```
notification_producer.py:61  AIOKafkaProducer(...) → ValueError: `ssl_context` is mandatory if security_protocol=='SSL'
```
에러 라인이 55→61로 이동(코드 변경됨)했으나 ssl_context가 여전히 producer에 전달 안 됨 → **PR #63 fix 불완전**.

**다음 액션(앱팀)**: `ssl.create_default_context()`를 AIOKafkaProducer/Consumer에 **실제 전달** + **SSL 경로 E2E 테스트**(PLAINTEXT 아닌 실 SSL) → 새 이미지 빌드 → gitops bump → 라이브 재검증 → #144 close. 상세 버그리포트: #144 코멘트.

**gitops 측**: overlay 핀(1.0.0) + ECR 재태그는 정상(의도 이미지 배포 확인). 문제는 이미지 자체.

## 3. 라이브 윈도우 운영 메모 (재발 방지)

- **서비스별 DB 5종 수동 생성**: bring-up은 `synapse_platform`/`engagement`/`knowledge`/`learning`/`ai`를 자동생성 안 함. RDS 새로 뜨면 psql `CREATE DATABASE` 선행(미생성 시 Spring `database does not exist` 크래시). staging 전용 RDS도 동일.
- **selfHeal/ApplicationSet**: resource 패치(limit 등) 즉시 자동원복(드리프트 복구). `set env` override는 3-way merge로 미원복 → 직접 제거.
- **ECR 재태그**: `batch-get-image`→`put-image` 라운드트립은 매니페스트를 재직렬화 → manifest digest는 달라지나 **config·layer는 동일**(컨테이너 바이트 동일). 검증은 config digest 대조로.

## 4. 잔여 후속 (블록/정리)

- **#144**: 앱팀 재수정(위 §2) → 다음 윈도우 재검증.
- **engagement-svc-dev**: overlay가 phantom `1.0.1`(#122 데모 IU bump 잔재, ECR 부재)이라 ImagePullBackOff → `1.0.0` 정정 PR(#161). staging/prod 정상.
- **learning-card-staging**: staging RDS 연결은 정상(DB 무관), 앱레벨 Degraded → 다음 윈도우 `kubectl logs` 조사.

## 5. 레포 상태

- **OPEN 이슈**: #144만. #126·#155·#156·#157·#91·#92·#120·#121·#122 close.
- **main HEAD**: PR #160 머지분(staging 전용 RDS). + #161(engagement 정정) 진행.
- **설계/플랜**: `docs/superpowers/specs/2026-06-09-{w5-remaining-backlog-sha-semver-pin,staging-dedicated-rds}-design.md`, `docs/superpowers/plans/2026-06-09-w5-remaining-backlog-sha-semver-pin.md`.
