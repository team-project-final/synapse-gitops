# Design: W4 잔여 2일 — MSK terraform 편입(TLS-only) + 정리·마감

> **작성**: 2026-06-02 · **owner**: @VelkaressiaBlutkrone (gitops) · **상태**: 설계 승인
> **기간**: 잔여 실작업일 06-04·06-05 (06-03 지방선거 제외) + 06-02 오프라인 준비
> **선행 점검**: 전체 브랜치 점검 + W4 일정 확인 (이 문서의 동기)
> **관련**: shared `KAFKA_AUTH_MATRIX.md`, `MSK_TOPIC_SETUP.md`, `W4_DAY1_POST_APPLY.md`, gitops `infra/aws/dev/msk.tf`, `WORKFLOW_gitops_W4.md`

---

## 1. 배경 & 동기

전체 브랜치/일정 점검 결과:

- **브랜치**: `fetch --prune` 후 원격은 `main` 단독. 로컬 브랜치 4개는 전부 main 대비 stale(3개 머지 완료, `docs/unified-handoff-hub-spoke`는 1커밋이 main과 내용 동일 → 무손실 삭제 가능). 로컬 `main`은 origin 대비 7 behind.
- **일정**: W4 Step 9/10 모두 Done(FR-401~408 라이브 증명, 06-01). 잔여 = team-lead 사인오프 2건(사람 의존) + 의도적 이월(실도메인 W1, image-updater E2E W2).
- **결정적 제약**: dev 클러스터가 `terraform destroy`로 내려가 있음(과금 차단). 라이브 의존 작업은 재-apply(=과금) 없이는 실행 불가.

shared 문서 점검에서 본격 작업 1건이 드러남: **MSK 토픽·인증의 terraform 편입**. 현재 `msk.tf`는 클러스터+configuration만 선언하고 (a) 9개 토픽은 bastion 수동 스크립트로 생성, (b) 인증 모델 미결(`BootstrapBrokerStringSaslIam=null`). shared가 "결정 필요"로 플래그한 항목이다. 이 작업이 **라이브 기동을 1회 요구**하는 유일한 드라이버다.

## 2. 목표 & 비목표

**목표**

1. MSK 인증 모델을 **TLS-only로 확정**하고 문서(KAFKA_AUTH_MATRIX)를 정렬한다.
2. 9개 Kafka 토픽을 **terraform 선언 관리**로 전환해 bastion 수동 단계를 제거한다.
3. 1회 라이브 window에서 토픽 terraform을 검증하고, 비용 0의 기회로 image-updater E2E(A5)도 라이브 검증한다.
4. git 정리·W4 마감 패키지·shared 정합·W5 스코핑을 비용 0으로 봉합한다.

**비목표 (명시적 범위 밖)**

- **A안(SASL/IAM) 전환** — 5개 Spring 서비스 코드(`aws-msk-iam-auth` 의존성)·IRSA·타 owner 조율이 필요. W5+ 백로그로 문서화만.
- **실도메인 의존 3항목**(ACM/DNS/ArgoCD UI/webhook) — 도메인 부재로 이월 유지.
- **타 서비스 코드**(engagement 스키마 비호환 등) — 타 owner 소관.
- **브로커 주소 자동화(2-3)** — 옵션, 코어 아님.

## 3. 인증 모델 결정 — B (TLS-only)

### 3.1 결정

dev/staging/prod MSK는 **TLS(9094) 암호화만 유지**, SASL/IAM 미활성. 토픽 인가는 **SG/네트워크 경계**로 제어(per-topic IAM 미사용).

### 3.2 근거 (A vs B 비교)

| 항목 | **B: TLS-only (채택)** | A: SASL/IAM |
|---|---|---|
| `msk.tf` 변경 | 없음 (현 TLS 유지) | `client_authentication.sasl.iam=true` |
| 서비스 config | 현행 9094 그대로 동작 | 9098 + security.protocol/sasl 추가 |
| 서비스 **코드** | 변경 없음 | `aws-msk-iam-auth` 의존성 ×5 (타 owner) |
| IRSA/IAM Policy | 불필요 | 서비스별 5개 정책+IRSA |
| 토픽 TF provider 인증 | TLS 단순 연결 | AWS_MSK_IAM 기본 미지원(까다로움) |
| 토픽 인가 단위 | SG/네트워크 경계 | per-topic 최소권한 |
| 2일·클러스터다운·캡스톤 적합성 | **높음 (gitops 단독 완결)** | 낮음 (타 owner·라이브·코드변경) |

shared 문서는 A를 "권장"으로 적었으나, 그 판단은 A가 **서비스 코드/라이브러리 변경 + 5개 서비스 타 owner 의존**임이 드러나기 전이다. 클러스터 다운·서비스 미배포·캡스톤 잔여 봉합이라는 현 맥락에서 per-topic 최소권한의 가치는 회수되기 어렵고, B가 gitops 단독으로 2일 내 완결된다.

### 3.3 부수 효과 — bastion 경로 해제

bastion 차단 사유 3종은 **전부 IAM/CLI 특정**이다: ① kubectl 401(EKS aws-auth, MSK 무관) ② Kafka CLI/Java 미설치(TF provider는 Go라 무관) ③ 역할 `kafka:*` 권한 없음(TLS는 IAM 미사용). 따라서 **TLS-only 선택 시 토픽 terraform 경로가 bastion 네트워크 도달만으로 열린다.**

## 4. 주 작업 — MSK terraform 편입

### 4.1 인증 정렬 (코드/문서)

- `infra/aws/dev/msk.tf`: 변경 없음(TLS 유지 확인).
- shared `KAFKA_AUTH_MATRIX.md`: §1 인증표를 TLS-only로 수정, §3 IAM Policy 예시 제거(또는 "A안 백로그"로 강등), §5 적용단계를 토픽 TF 절차로 갱신. (gitops 소관 변경 → shared에 PR/조율.)

### 4.2 토픽 선언화 — `Mongey/kafka` provider (추천 방식)

- **단일 출처**: EVENT_CONTRACT_STANDARD §2 / `create-kafka-topics.sh` `TOPICS` 배열 = 9개:
  1. `platform.auth.user-registered-v1`
  2. `knowledge.note.note-created-v1`
  3. `knowledge.note.note-updated-v1`
  4. `learning.card.review-completed-v1`
  5. `learning.card.review-due-v1`
  6. `engagement.gamification.level-up-v1`
  7. `engagement.gamification.badge-earned-v1`
  8. `platform.notification.notification-send-v1`
  9. `learning.ai.cards-generated-v1` (deprecated/D-001, 토픽만 존속 — 동등 반영)
- **설정**: `kafka_topic` ×9, `partitions=3`, `replication_factor=3`, `config = { "min.insync.replicas" = "2" }` (msk.tf의 `aws_msk_configuration` 기본과 정합).
- **구성 분리**: 토픽 TF는 **별도 디렉터리/state**(예: `infra/aws/dev/kafka-topics/`)로 분리. 이유 = 데이터플레인 provider는 브로커가 살아 있어야 plan/apply 가능 → 인프라 apply(브로커 생성) → 토픽 apply의 **2단계 순서**. 인프라 state 오염 방지.
- **provider 연결**: `bootstrap_servers = [<9094 TLS 엔드포인트>]`, `tls_enabled = true`. private subnet이라 **bastion에서 실행하거나 bastion 경유 터널**로 9094 도달. 브로커 주소는 `terraform output`(인프라)에서 취득.
- **idempotent**: 기존 토픽 존재 시 import 또는 신규 클러스터라 clean apply. 라이브 window가 clean 재기동이므로 신규 생성 경로.

### 4.3 브로커 주소 취약성 (옵션, 코어 아님)

재apply마다 브로커 DNS 변동(`fark5c`→`v2grm6`→`dchj3l` 이력) → 5개 service overlay의 `KAFKA_BROKERS` 하드코딩을 매번 수정해야 함. 개선안: `terraform output` → 단일 ConfigMap 소싱으로 전환. **범위가 커서 이번 window 코어에서 제외**, W5 백로그로 문서화. 이번엔 apply 후 실제 브로커 주소로 overlay 5개 갱신(기존 절차 유지).

## 5. 라이브 기동 window (비용 발생 구간)

- **06-04 apply**: `terraform apply`(인프라 재기동) → `terraform output`로 브로커 주소 확보 → 토픽 TF apply 검증(9개 생성 확인) → service overlay 브로커 주소 갱신 → **image-updater E2E(A5) 라이브 검증**(ECR semver push → write-back → sync) → 증거 캡처.
- **06-05 destroy**: 결과 문서화 후 `terraform destroy`로 과금 차단(W4 패턴 유지).
- **리스크 & 무관성**: 타 서비스 미배포·engagement 스키마 비호환은 **토픽/인프라 검증과 무관**(토픽은 서비스 독립 생성). image-updater E2E는 이미지 푸시→write-back 경로만 확인하면 됨.

## 6. 경량 트랙 (비용 0, 병렬)

| | 작업 | 내용 |
|---|---|---|
| **A** | git 정리 | 로컬 4개 삭제(`chore/local-k8s-cleanup`·`feat/deploy-mirror-standardization`·`feat/gateway-dev-overlay`·`docs/unified-handoff-hub-spoke`) + `main` ff(+7) + `.gitignore`에 `infra/aws/dev/*.log` 추가 |
| **B** | W4 마감 패키지 | 사인오프 2건(권한모델·RTO/RPO) team-lead 전달용 정리 + HISTORY/HANDOFF 확정 |
| **C** | 이월 항목 정정 | 실도메인(W1)·image-updater 잔여를 차단사유 명시로 닫고 "복귀 시 즉시 실행" 상태 유지 |
| **D** | shared 정합 | KAFKA_AUTH_MATRIX TLS-only 전환 반영. 타 owner·라이브 의존 항목은 조율 코멘트만 |
| **E** | W5 스코핑 | 다음 주차 범위 초안 (A안 SASL/IAM·브로커 주소 자동화·실도메인 등 백로그 포함) |

## 7. 순서

- **06-02 (오늘)**: 트랙 A(git 정리) + 본 spec → plan 확정 + 토픽 TF 코드 초안(오프라인 작성, apply는 안 함).
- **06-04**: 기동 window(§5) — 토픽 TF apply 검증 + image-updater E2E + 매트릭스 적용.
- **06-05**: 마감(트랙 B·C·D·E) + `terraform destroy` + HISTORY 갱신.

## 8. 성공 기준

- [ ] `infra/aws/dev/kafka-topics/` TF로 9개 토픽이 라이브 클러스터에 선언·생성됨(수동 스크립트 불필요 입증).
- [ ] `msk.tf` TLS 유지 확인, `KAFKA_AUTH_MATRIX`가 TLS-only로 정렬됨.
- [ ] image-updater E2E(A5) 라이브 1회 검증(증거 캡처) — 클러스터가 떠 있는 김에.
- [ ] 로컬 브랜치 4개 삭제·`main` ff·`*.log` gitignore 완료.
- [ ] W4 사인오프 패키지·HISTORY·shared 정합·W5 스코핑 문서 마감.
- [ ] `terraform destroy`로 과금 차단 복귀.

## 9. 미해결/의존

- team-lead 사인오프 2건은 **사람 의존**(이 작업으로 패키지화까지만, 합의는 외부).
- 토픽 TF provider의 bastion 실행 경로는 라이브 window에서 **첫 실증**(설계상 TLS로 열리나 미검증) → §5에서 확인.
