# Unified Handoff Hub-Spoke Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a hub-spoke handoff system across synapse-shared (hub), synapse-gitops (spoke), and service repos (no spoke) to eliminate cross-repo state drift and establish a session-close process.

**Architecture:** Hub document (`HANDOFF_HUB.md`) lives in synapse-shared with project-wide dashboard + cross-repo dependency map. Each major repo keeps a spoke document with repo-specific details. A session-close checklist ensures spoke-to-hub sync after every session.

**Tech Stack:** Markdown documents, git

---

## File Map

### synapse-shared repo (`C:\workspace\team-project-final\synapse-shared`)

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `docs/project-management/HANDOFF_HUB.md` | Project-wide status dashboard (hub) |
| Create | `docs/project-management/HANDOFF_SHARED.md` | Shared repo spoke (schemas, Kafka, Docker Compose) |
| Create | `docs/project-management/SESSION_CLOSE_CHECKLIST.md` | 5-step session-close process |
| Modify | `docs/project-management/HANDOFF_2026-05-19.md` | Archive header (read-only marker) |

### synapse-gitops repo (`C:\workspace\team-project-final\synapse-gitops`)

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `docs/superpowers/HANDOFF_W3.md` | Gitops spoke (infra, ArgoCD, costs) |
| Modify | `docs/superpowers/HANDOFF_W2.md` | Archive header (read-only marker) |

---

## Task 1: Create Hub Document (HANDOFF_HUB.md)

**Files:**
- Create: `C:\workspace\team-project-final\synapse-shared\docs\project-management\HANDOFF_HUB.md`

- [ ] **Step 1: Create HANDOFF_HUB.md with W3 initial content**

```markdown
# Synapse 통합 핸드오프 허브

> **최종 갱신**: 2026-05-22 (W2 → W3 전환)
> **현재 주차**: W3
> **갱신자**: @VelkaressiaBlutkrone

---

## 1. 프로젝트 상태 대시보드

### 환경별 서비스 상태

| 서비스 | dev | staging | prod |
|---|---|---|---|
| platform-svc | ✅ Healthy | ⚠️ staging 프로필 미존재 | ⏳ W4 |
| engagement-svc | ✅ Healthy | ✅ Healthy | ⏳ W4 |
| knowledge-svc | ✅ Healthy | ✅ Healthy | ⏳ W4 |
| learning-card | ✅ Healthy | ✅ Healthy | ⏳ W4 |
| learning-ai | ✅ Healthy | ✅ Healthy | ⏳ W4 |

> 상태 enum: ✅ Healthy / ⚠️ Degraded / 🔴 Down / ⏳ Not Started

### 인프라 상태

| 컴포넌트 | 상태 | 비고 |
|---|---|---|
| EKS | ✅ | destroy/apply 반복 (비용 관리), private endpoint |
| RDS PostgreSQL 16 | ✅ | SG 매 apply 후 수동 추가 필요 (D-026) |
| MSK Kafka | ✅ | 토픽 5개 생성 완료, 브로커 주소 PR #42 반영 |
| Redis | ✅ | SG 수동 추가 필요 |
| OpenSearch | ✅ | SG 수동 추가 필요 |
| ArgoCD | ✅ | HA 모드, dev auto-sync + staging manual |

### Kafka / 스키마 상태

| 항목 | 상태 |
|---|---|
| Avro 스키마 8개 | ✅ BACKWARD 호환 |
| MSK 토픽 5개 | ✅ 생성 완료 |
| 서비스 Kafka Producer/Consumer | 🔴 5/5 미착수 |

---

## 2. 교차 의존관계 맵

```
[블로커] platform-svc application-staging.yml 추가
    └─→ staging 5/5 Healthy 달성

[블로커] 5개 서비스 Kafka Producer/Consumer 구현 (서비스 레포)
    └─→ shared E2E 검증 가능
        └─→ staging 프로모션 테스트

[독립] Observability 스택 설치 (gitops)
    └─→ W3 PRD FR-GO-303~307

[독립] terraform state 정리 — SG/OIDC 코드 반영 (gitops)
```

---

## 3. 스포크 참조

| 레포 | 스포크 문서 | 최종 갱신 | 정합성 |
|---|---|---|---|
| synapse-gitops | `docs/superpowers/HANDOFF_W3.md` | 2026-05-22 | ✅ 동기 |
| synapse-shared | `docs/project-management/HANDOFF_SHARED.md` | 2026-05-22 | ✅ 동기 |

---

## 4. 다음 세션 작업 순서

```
1. [gitops] terraform apply + 세션 기동 (runbook 12단계)
     → docs/runbooks/w2-session-bootstrap-runbook.md
2. [gitops] platform-svc staging 프로필 해결 → staging 5/5
     → 완료 기준: argocd app sync synapse-platform-svc-staging → Healthy
3. [gitops] Observability 스택 설치 (kube-prometheus-stack)
     → 완료 기준: Prometheus + Grafana + Alertmanager Running
4. [gitops] ServiceMonitor 5개 + Grafana 대시보드
     → 완료 기준: Grafana Explore에서 5개 앱 메트릭 조회
5. [shared] 서비스별 Kafka 구현 상태 확인 + E2E 준비
     → 완료 기준: kafka-e2e-test.sh --all PASS
6. [gitops] terraform state 정리 (SG/OIDC 코드 반영)
     → 완료 기준: terraform plan → no unexpected drift
```

---

## 5. 주간 마일스톤 추적

| 주차 | 목표 | 상태 | 실제 완료일 |
|---|---|---|---|
| W1 (5/12-16) | ArgoCD bootstrap + CI | ✅ 완료 | 5/16 |
| W2 (5/19-23) | Dev 5앱 + secrets + image sync | ✅ 완료 | 5/21 (9차 세션) |
| W3 (5/26-29) | Staging + Observability | ⏳ 미시작 | — |
| W4 (6/01-05) | Prod + approval + rollback | ⏳ 계획 | — |
| W5 (6/08-12) | Runbooks + DR + 비용 최적화 | ⏳ 계획 | — |
```

- [ ] **Step 2: Verify line count is under 200**

Run: `wc -l C:/workspace/team-project-final/synapse-shared/docs/project-management/HANDOFF_HUB.md`
Expected: under 200 lines

- [ ] **Step 3: Commit**

```bash
cd C:/workspace/team-project-final/synapse-shared
git add docs/project-management/HANDOFF_HUB.md
git commit -m "docs: create unified handoff hub — W3 transition dashboard"
```

---

## Task 2: Create Shared Spoke (HANDOFF_SHARED.md)

**Files:**
- Create: `C:\workspace\team-project-final\synapse-shared\docs\project-management\HANDOFF_SHARED.md`

- [ ] **Step 1: Create HANDOFF_SHARED.md**

```markdown
# 핸드오프: synapse-shared

> **최종 갱신**: 2026-05-22 (W2 → W3 전환)
> **허브 참조**: → [HANDOFF_HUB.md](./HANDOFF_HUB.md)

---

## 1. Avro 스키마 현황

| 스키마 | 네임스페이스 | 토픽 | 호환성 |
|---|---|---|---|
| CloudEventEnvelope | com.synapse.shared | (래퍼) | ✅ BACKWARD |
| UserRegistered | com.synapse.platform | platform.auth.user-registered-v1 | ✅ BACKWARD |
| NoteCreated | com.synapse.knowledge | knowledge.note.note-created-v1 | ✅ BACKWARD |
| NoteUpdated | com.synapse.knowledge | knowledge.note.note-updated-v1 | ✅ BACKWARD |
| ReviewCompleted | com.synapse.learning | learning.card.review-completed-v1 | ✅ BACKWARD |
| CardsGenerated | com.synapse.learning | learning.ai.cards-generated-v1 | ✅ BACKWARD |
| TenantId | com.synapse.shared | (공통) | ✅ |
| UserId | com.synapse.shared | (공통) | ✅ |

## 2. Kafka 토픽 / MSK 상태

| 토픽 | MSK 생성 | 파티션 | 복제 | 프로듀서 | 컨슈머 |
|---|---|---|---|---|---|
| platform.auth.user-registered-v1 | ✅ | 3 | 2 | platform-svc | engagement, learning-card |
| knowledge.note.note-created-v1 | ✅ | 3 | 2 | knowledge-svc | learning-ai |
| knowledge.note.note-updated-v1 | ✅ | 3 | 2 | knowledge-svc | learning-ai, opensearch |
| learning.card.review-completed-v1 | ✅ | 3 | 2 | learning-card | engagement-svc |
| learning.ai.cards-generated-v1 | ✅ | 3 | 2 | learning-ai | learning-card |

**MSK 브로커**: PR #42 반영 완료 (endpoint 변경 시 gitops ConfigMap 갱신 필요)

## 3. Docker Compose 현황

13개 서비스 로컬 환경: ✅ 전체 Healthy
- DB/Cache: postgres, redis, zookeeper
- Kafka: kafka, schema-registry
- Search: opensearch
- App: platform, engagement, knowledge, learning-card, learning-ai, gateway

## 4. CI/CD 파이프라인 상태

| 워크플로 | 트리거 | 상태 |
|---|---|---|
| ci-java.yml | PR/push → Gradle build + Modulith verify | ✅ PASS |
| schema-check.yml | PR (*.avsc 변경) → 호환성 검증 | ✅ PASS |
| mirror.yml | push → synapse-mirror 동기화 | ✅ PASS |

## 5. 팀원 체크리스트

→ [TEAM_CHECKLIST_W3.md](../guides/TEAM_CHECKLIST_W3.md)

**서비스별 Kafka 구현 상태**:

| 서비스 | 역할 | 구현 상태 |
|---|---|---|
| platform-svc | Producer (UserRegistered) + Consumer (CardsGenerated) | 🔴 미착수 |
| engagement-svc | Consumer (UserRegistered, ReviewCompleted) | 🔴 미착수 |
| knowledge-svc | Producer (NoteCreated, NoteUpdated) | 🔴 미착수 |
| learning-card | Producer (ReviewCompleted) | 🔴 미착수 |
| learning-ai | Producer (CardsGenerated) + Consumer (NoteCreated) | 🔴 미착수 |
```

- [ ] **Step 2: Commit**

```bash
cd C:/workspace/team-project-final/synapse-shared
git add docs/project-management/HANDOFF_SHARED.md
git commit -m "docs: create shared spoke handoff — schemas, Kafka, Docker Compose status"
```

---

## Task 3: Create Session Close Checklist

**Files:**
- Create: `C:\workspace\team-project-final\synapse-shared\docs\project-management\SESSION_CLOSE_CHECKLIST.md`

- [ ] **Step 1: Create SESSION_CLOSE_CHECKLIST.md**

```markdown
# 세션 종료 체크리스트

> 매 세션 종료 시 이 체크리스트를 따라 허브-스포크 정합성을 유지합니다.

---

## Step 1: 스포크 갱신

작업한 레포의 핸드오프 문서에 세션 결과를 기록합니다.

| 레포 | 스포크 문서 |
|---|---|
| synapse-gitops | `docs/superpowers/HANDOFF_W3.md` |
| synapse-shared | `docs/project-management/HANDOFF_SHARED.md` |

기록 항목:
- [ ] 완료 사항 (작업 | 산출물 테이블)
- [ ] 발견 사항 (D-0XX, 해당 시)
- [ ] PR 현황 (해당 시)

---

## Step 2: 허브 동기화

`docs/project-management/HANDOFF_HUB.md`를 갱신합니다.

- [ ] 헤더의 "최종 갱신" 날짜 + 세션 번호 + 갱신자 업데이트
- [ ] 대시보드 테이블 상태값 갱신 (서비스/인프라/Kafka)
- [ ] 교차 의존관계 맵 변경 반영 (블로커 해소, 새 블로커 추가)
- [ ] 스포크 참조 테이블의 "최종 갱신" 날짜 업데이트
- [ ] 다음 세션 작업 순서 갱신 (완료 항목 제거, 새 항목 추가)

---

## Step 3: 정합성 점검 (30초)

3개 질문에 답합니다. 모두 ✅이면 통과.

- [ ] 허브 서비스 상태가 실제(ArgoCD/kubectl)와 같은가?
- [ ] 허브의 "스포크 최종 갱신일"이 오늘 날짜인가? (작업한 레포에 한해)
- [ ] 허브의 "다음 세션 작업"에 오늘 완료한 항목이 남아있지 않은가?

하나라도 ❌이면 해당 항목 수정 후 재커밋.

---

## Step 4: 커밋 + 푸시

- [ ] 스포크: 해당 레포에 커밋 + 푸시
- [ ] 허브: synapse-shared에 커밋 + 푸시

커밋 메시지 형식:
```
docs: session N handoff — [한줄 요약]
```

---

## Step 5: 비용 정리

- [ ] 인프라 사용 시: `cd infra/aws/dev && terraform destroy -auto-approve`
- [ ] S3 state bucket + DynamoDB lock table은 유지 (destroy 대상 아님)

---

## 세션 유형별 범위

| 세션 유형 | 스포크 갱신 | 허브 갱신 | 정합성 점검 |
|---|---|---|---|
| gitops만 작업 | gitops만 | 대시보드 + 다음 작업 | 서비스 상태만 |
| shared만 작업 | shared만 | 스키마/토픽 + 다음 작업 | 의존관계만 |
| 교차 작업 (양쪽) | 양쪽 모두 | 전체 | 전체 |
| 서비스 레포만 | 없음 | 대시보드 서비스 상태만 | 서비스 상태만 |
```

- [ ] **Step 2: Commit**

```bash
cd C:/workspace/team-project-final/synapse-shared
git add docs/project-management/SESSION_CLOSE_CHECKLIST.md
git commit -m "docs: add session close checklist — 5-step hub-spoke sync process"
```

---

## Task 4: Create Gitops Spoke (HANDOFF_W3.md)

**Files:**
- Create: `C:\workspace\team-project-final\synapse-gitops\docs\superpowers\HANDOFF_W3.md`

- [ ] **Step 1: Create HANDOFF_W3.md**

```markdown
# W3 핸드오프: synapse-gitops

> **최종 갱신**: 2026-05-22 (W2 → W3 전환)
> **허브 참조**: [synapse-shared/docs/project-management/HANDOFF_HUB.md](https://github.com/team-project-final/synapse-shared/blob/main/docs/project-management/HANDOFF_HUB.md)
> **담당**: @VelkaressiaBlutkrone

---

## 1. 세션별 완료 사항

W2 이전 (1~9차 세션): → [HANDOFF_W2.md](./HANDOFF_W2.md) 참조

### W2 최종 상태 요약

- ✅ 5/5 서비스 Healthy (dev)
- ✅ staging overlay 5개 + ApplicationSet (manual sync)
- ✅ staging 4/5 Healthy (platform-svc staging 프로필 미존재)
- ✅ MSK 토픽 5개 생성, KAFKA_BROKERS 갱신 (PR #42)
- ✅ ExternalSecret 11개 SecretSynced
- ✅ 세션 기동 runbook + 트러블슈팅 가이드 22항목

---

## 2. 인프라 상세 상태

### ArgoCD Application 상태

| 앱 | dev | staging |
|---|---|---|
| platform-svc | Synced / Healthy | Synced / ⚠️ staging 프로필 없음 |
| engagement-svc | Synced / Healthy | Synced / Healthy |
| knowledge-svc | Synced / Healthy | Synced / Healthy |
| learning-card | Synced / Healthy | Synced / Healthy |
| learning-ai | Synced / Healthy | Synced / Healthy |

### ExternalSecret 동기화

| 시크릿 | 상태 |
|---|---|
| dev 환경 11개 | ✅ SecretSynced |
| staging 환경 | ⏳ staging sync 후 확인 |

### terraform 리소스 (46개)

EKS, RDS, MSK, Redis, OpenSearch, Bastion, VPC, OIDC, IAM roles.
매 apply 후 수동 작업: EKS cluster SG → RDS/Redis/MSK/OpenSearch SG 인바운드 추가 (D-026).

---

## 3. 세션 기동 절차

→ [docs/runbooks/w2-session-bootstrap-runbook.md](../runbooks/w2-session-bootstrap-runbook.md) (12단계)
→ [docs/runbooks/troubleshooting-infra.md](../runbooks/troubleshooting-infra.md) (22항목)

---

## 4. 발견 사항 (D-0XX)

기존 D-016 ~ D-031: → [HANDOFF_W2.md 섹션 6](./HANDOFF_W2.md#6-발견-사항-기록)

W3에서 추가된 발견 사항은 아래에 기록:

| ID | 내용 | 영향 |
|---|---|---|
| — | (W3 시작 전, 추가 발견 없음) | — |

---

## 5. 비용 관리

- 시간당 ~$0.41 (EKS + RDS + MSK + Redis + OpenSearch)
- 작업 완료 후: `cd infra/aws/dev && terraform destroy -auto-approve`
- 유지 대상: S3 state bucket (`synapse-terraform-state`) + DynamoDB lock table
```

- [ ] **Step 2: Commit**

```bash
cd C:/workspace/team-project-final/synapse-gitops
git add docs/superpowers/HANDOFF_W3.md
git commit -m "docs: create W3 gitops spoke handoff — infra status and session bootstrap"
```

---

## Task 5: Archive Existing Documents

**Files:**
- Modify: `C:\workspace\team-project-final\synapse-shared\docs\project-management\HANDOFF_2026-05-19.md:1-6`
- Modify: `C:\workspace\team-project-final\synapse-gitops\docs\superpowers\HANDOFF_W2.md:1-8`

- [ ] **Step 1: Add archive header to shared HANDOFF_2026-05-19.md**

Insert at line 1 (before existing content):

```markdown
> **⚠️ 아카이브**: 이 문서는 W2 기간(2026-05-19 ~ 05-22) 핸드오프 기록입니다.
> 현재 핸드오프는 [HANDOFF_HUB.md](./HANDOFF_HUB.md) + [HANDOFF_SHARED.md](./HANDOFF_SHARED.md)를 참조하세요.

---

```

Existing content remains unchanged below the archive header.

- [ ] **Step 2: Add archive header to gitops HANDOFF_W2.md**

Insert at line 1 (before existing content):

```markdown
> **⚠️ 아카이브**: 이 문서는 W2 기간(1~9차 세션) 핸드오프 기록입니다.
> 현재 핸드오프는 [HANDOFF_HUB.md](https://github.com/team-project-final/synapse-shared/blob/main/docs/project-management/HANDOFF_HUB.md) + [HANDOFF_W3.md](./HANDOFF_W3.md)를 참조하세요.

---

```

Existing content remains unchanged below the archive header.

- [ ] **Step 3: Commit shared archive**

```bash
cd C:/workspace/team-project-final/synapse-shared
git add docs/project-management/HANDOFF_2026-05-19.md
git commit -m "docs: archive W2 shared handoff — replaced by hub-spoke system"
```

- [ ] **Step 4: Commit gitops archive**

```bash
cd C:/workspace/team-project-final/synapse-gitops
git add docs/superpowers/HANDOFF_W2.md
git commit -m "docs: archive W2 gitops handoff — replaced by hub-spoke system"
```

---

## Task 6: Verify Hub-Spoke Consistency

- [ ] **Step 1: Cross-check hub dashboard against spokes**

Verify each hub section matches its spoke source:

```
□ Hub 서비스 상태 (5행) ↔ gitops spoke 섹션 2 ArgoCD 테이블
□ Hub 인프라 상태 (6행) ↔ gitops spoke 섹션 2 terraform 리소스
□ Hub Kafka/스키마 (3행) ↔ shared spoke 섹션 1 + 2
□ Hub 스포크 참조 갱신일 ↔ 각 스포크 헤더 날짜
□ Hub 다음 작업 순서 ↔ 양쪽 스포크에 해당 컨텍스트 존재
```

Expected: 5/5 ✅

- [ ] **Step 2: Verify hub is under 200 lines**

Run: `wc -l C:/workspace/team-project-final/synapse-shared/docs/project-management/HANDOFF_HUB.md`
Expected: under 200

- [ ] **Step 3: Verify all 4 new files exist**

```bash
ls C:/workspace/team-project-final/synapse-shared/docs/project-management/HANDOFF_HUB.md
ls C:/workspace/team-project-final/synapse-shared/docs/project-management/HANDOFF_SHARED.md
ls C:/workspace/team-project-final/synapse-shared/docs/project-management/SESSION_CLOSE_CHECKLIST.md
ls C:/workspace/team-project-final/synapse-gitops/docs/superpowers/HANDOFF_W3.md
```

Expected: all 4 exist

- [ ] **Step 4: Verify archive headers exist**

```bash
head -3 C:/workspace/team-project-final/synapse-shared/docs/project-management/HANDOFF_2026-05-19.md
head -3 C:/workspace/team-project-final/synapse-gitops/docs/superpowers/HANDOFF_W2.md
```

Expected: both show "⚠️ 아카이브" header
