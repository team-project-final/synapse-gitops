# W5 Followups: Doc Sync + Kafka/DB Provisioning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** W5 일정 추적 문서 4종을 현실과 동기화하고, 저우선 후속 3건을 GitHub 이슈로 추적하며, `bring-up.sh`에 Kafka 토픽 9종 + DB 5종 자동 프로비저닝 phase를 추가한다.

**Architecture:** 두 독립 파트. 파트1=문서/이슈(오프라인, 순수 텍스트·gh CLI). 파트2=`bring-up.sh` 클러스터 내 Job 방식 프로비저닝(접근법 A) + 토픽 리스트 단일 출처 파일화(C 하이브리드). 라이브 검증 없음 → `bash -n`/`--dry-run`/`terraform validate`/`kubectl --dry-run=client`로 최대 검증.

**Tech Stack:** Bash(`bring-up.sh`), Terraform(Mongey/kafka + AWS), Kubernetes Job(apache/kafka:3.9.0, postgres:16), GitHub CLI(`gh`), Markdown.

**Spec:** `docs/superpowers/specs/2026-06-10-w5-followups-doc-sync-provisioning-design.md`

**Branch:** `docs/w5-followups-doc-sync-provisioning` (이미 생성됨, 스펙 커밋 완료)

**참고 — 확인된 사실(구현 중 재조회 불필요):**
- 토픽 9종 정본: `infra/aws/dev/kafka-topics/main.tf` `locals.topics` (아래 Task 6에 전문)
- DB 5종: `synapse_platform`, `synapse_engagement`, `synapse_knowledge`, `synapse_learning`, `synapse_ai`
- terraform outputs(`infra/aws/dev/outputs.tf`): `rds_endpoint`(host:port), `rds_staging_endpoint`(host:port), `rds_port`, `msk_bootstrap_brokers_tls`. `rds_username` 출력 **없음 → Task 7에서 추가**.
- dev+staging RDS 동일 master 자격: username 기본 `synapse_admin`, password=`$TF_VAR_rds_password`(env, `phase_terraform` 전제). 기본 db `synapse`(항상 존재).
- RDS `rds.force_ssl=1` → psql `sslmode=require` 필수.
- `bring-up.sh` PHASES 배열(L37): `terraform eks-auth tunnel argocd eso oidc-fix alb-controller kafka-config manifests metrics-server image-updater observability status`. 신설 phase는 `kafka-config`와 `manifests` 사이.
- phase 함수 호출 규약: `"phase_${p//-/_}"` → phase 이름 `kafka-topics` → 함수 `phase_kafka_topics`.

---

## 파트 1 — 일정 문서 동기화 + 이슈

### Task 1: WORKFLOW_gitops_W5.md 동기화

**Files:**
- Modify: `docs/project-management/workflow/WORKFLOW_gitops_W5.md`

- [ ] **Step 1: Step 11 체크박스 + Status 갱신**

`## Step 11` 하위(L9~L39)의 미체크 박스를 실제 완료 상태로 갱신. 다음 항목을 `[ ]`→`[x]`:
- 1.1 사전 분석: 장애 유형 도출 / symptom→cause→action 매핑 / On-call 로테이션 / 에스컬레이션 기준 → `[x]`. PR diff 코멘트 후보 비교 + 도입 2건도 `[x]`(W1 이월·기구현, validate-manifests.yml diff-comment).
- 1.2 Runbook 작성: 5개 문서(`incidents/` 5종) + 각 문서 6섹션 → `[x]`
- 1.3 시뮬레이션: Pod kill / OOM / sync 실패 3종 → `[x]`(윈도우2 incident-sim). `team-lead가 Runbook만 보고 1회 처리` 줄은 `[x]`로 하고 끝에 ` <!-- 2026-06-09 #155 operator 드릴로 충족 -->` 주석.
- 1.4 On-call: 연락처+채널 / 알람 전달 경로 / 야간주말 정책 / README 링크 → `[x]`

`**Step 11 Status**` 줄을 다음으로 교체:
```
**Step 11 Status**: [x] Done (런북 5종 + 윈도우2 라이브 시뮬 3종·알람 검증 + #155 operator 드릴로 따라하기 충족 — 2026-06-09)
```

- [ ] **Step 2: Step 12 체크박스 + Status 갱신**

`## Step 12` 하위(L43~L70):
- 1.1 사전 분석: Cost Explorer 태그 정책 / 비용 분포 / P95 측정 / 미사용 리소스 식별 → 미완(라이브 메트릭 필요)은 `[ ]` 유지. resource-sizing 정적 리뷰분만 반영 불가하면 그대로.
- 1.2 리소스 적정화: resources 조정 `[ ]` 유지(P95 튜닝 윈도우 위임). HPA 정의 → `[x]`(윈도우2 검증). PDB/미사용 정리 `[ ]` 유지.
- 1.3 안정화: W1~W4 잔여 P1 점검+처리 → `[x]`(OPEN 0건). 헬스체크 → `[x]`(dev16/staging20 ALL PASSED). CI/CD 시간 → `[x]`. 알람 false-positive → `[ ]` 유지. kustomize 캐싱 → `[x]`(kubeconform+pip 캐싱 대체).
- 1.4 핸드오프: 최종 검토 → `[x]`. 트랜지션 미팅 / HISTORY 회고 / team-lead 사인오프 → `[ ]` 유지(team-lead 비동기).

`**Step 12 Status**` 줄을 교체:
```
**Step 12 Status**: [ ] Not Started / [x] In Progress / [ ] Done (HPA·P1 0건·CI캐싱·핸드오프검토 완료. 비용 가시성·P95 튜닝·team-lead 사인오프 잔여 — 2026-06-10)
```

- [ ] **Step 3: 검증 (미체크 잔여 의도 확인)**

Run: `grep -n "\[ \]" docs/project-management/workflow/WORKFLOW_gitops_W5.md`
Expected: 잔여 미체크는 모두 라이브 메트릭/team-lead 비동기 항목만 (비용 가시성, P95 리소스 조정, PDB, 미사용 정리, 알람 false-positive, 트랜지션 미팅, HISTORY 회고, 사인오프). 그 외 0건.

- [ ] **Step 4: Commit**

```bash
git add docs/project-management/workflow/WORKFLOW_gitops_W5.md
git commit -m "docs(pm): WORKFLOW_W5 Step11 Done·Step12 In Progress 현행화"
```

---

### Task 2: TASK_gitops.md 동기화 + 후속 추적 섹션

**Files:**
- Modify: `docs/project-management/task/TASK_gitops.md`

- [ ] **Step 1: Step 11 Status → Done**

`### Step 11` 의 `**Status**` 줄(L258)을 교체:
```
**Status**: [ ] Not Started / [ ] In Progress / [x] Done (런북 5종 + 윈도우2 라이브 시뮬 3종·알람 검증. team-lead 따라하기는 #155 operator 드릴로 충족 — 2026-06-09)
```
그리고 L251 `- [ ] team-lead가 Runbook 따라하기 1회 검증` 을 `- [x]`로 바꾸고 줄 끝에 ` (#155 operator 라이브 드릴로 충족, 2026-06-09)` 추가.

- [ ] **Step 2: Step 12 Status 현행화**

`### Step 12` 의 `**Status**` 줄(L279)을 교체:
```
**Status**: [ ] Not Started / [x] In Progress / [ ] Done (HPA 검증·P0/P1 0건·리소스 정적리뷰·CI캐싱·핸드오프검토 완료. AWS 비용 가시성·P95 기반 조정·team-lead 사인오프 잔여)
```
L271 `- [ ] HPA 동작 검증` → `- [x] HPA 동작 검증 (5개 앱 중 트래픽 변동 큰 2개)` 끝에 ` — 2026-06-08 윈도우2: engagement HPA min3→max6 스케일아웃/인 관찰` 추가.

- [ ] **Step 3: 후속 추적 섹션 추가**

파일 맨 끝(L280 이후)에 추가:
```markdown

---

## W5 마감 후 저우선 후속 (2026-06-10 이관)

> W5 잔여 백로그는 2026-06-09 라이브로 전부 완주(OPEN 이슈 0건, #144 포함 close). 아래 3건은 핸드오프 [`HANDOFF_2026-06-09-followups.md`](../../superpowers/HANDOFF_2026-06-09-followups.md)에서 이관, GitHub 이슈로 추적.

| 후속 | 이슈 | 우선순위 | 상태 |
|------|------|----------|------|
| A. learning-card-staging Degraded 근본원인 조사 | #<A> | 낮음 | OPEN (라이브 윈도우 필요) |
| B. learning-ai·card semver 재핀 — SHA vs semver 전략 결정 | #<B> | 낮음 | OPEN (팀 결정 필요) |
| C. bring-up Kafka 토픽 9종 + DB 5종 자동 프로비저닝 | #<C> | 낮음~중 | 코드 완료, 라이브 검증 대기 |

- A/B는 라이브 EKS 윈도우(과금) 필요 → 다음 윈도우.
- C는 2026-06-10 오프라인 구현(`docs/superpowers/plans/2026-06-10-w5-followups-doc-sync-provisioning.md`). 라이브 토픽/DB 생성 검증만 다음 윈도우.
```
(`#<A>`/`#<B>`/`#<C>`는 Task 5에서 실제 이슈 번호로 치환.)

- [ ] **Step 4: Commit**

```bash
git add docs/project-management/task/TASK_gitops.md
git commit -m "docs(pm): TASK Step11 Done·Step12 현행화 + 후속 A/B/C 추적 섹션"
```

---

### Task 3: HANDOFF_W5.md #144 CLOSED 정합

**Files:**
- Modify: `docs/superpowers/HANDOFF_W5.md`

- [ ] **Step 1: 헤더 + §1 표 갱신**

L1 제목 옆/L3 갱신일을 `2026-06-10`로, 그리고 §1 표(L19)의 #144 행을 교체:
```
| 4 | learning-ai dev 복구 | #144 | ✅ **CLOSED** | learning-svc PR #67 재수정(`9140e597`) — learning-ai 1/1 Running·RESTARTS 0·ssl_context 0건 (2026-06-09 2차 라이브) |
```

- [ ] **Step 2: §2 갱신 (OPEN → 해결 경위)**

`## 2. ⚠️ #144 (유일 OPEN)` 섹션(L22~L32)을 다음으로 교체:
```markdown
## 2. ✅ #144 (CLOSED) — 2차 라이브에서 재수정 검증

1차 라이브에서 `learning-ai:1.0.0`(=`3774e2e6`)이 동일 ssl_context CrashLoop → **앱팀 PR #63 fix 무효** 입증. 원인: `3774e2e6`은 `fix(avro) #64` 빌드라 ssl_context 수정 미포함(**코드 머지 ≠ 빌드 반영**).

**실수정**: `synapse-learning-svc` PR #67 — `app/kafka/ssl_support.py`(`kafka_ssl_context()`=SSL시 `create_ssl_context()`) + producer/consumer `ssl_context=` 전달 + TLS 단위테스트(앱팀이 빠뜨린 검증). CI green → admin 머지 → ECR `learning-ai:9140e597` 푸시 + gitops bump.

**2차 라이브**: `9140e597` 배포 → learning-ai 1/1 Running·RESTARTS 0·Healthy, ssl_context 에러 0건 → **#144 close**.
```

- [ ] **Step 3: §4/§5 정합**

L44 `learning-card-staging` 줄은 후속 A로 이관됨을 명시: 끝에 ` (후속 A, 이슈 #<A>)` 추가.
L48 `**OPEN 이슈**: #144만.` → `**OPEN 이슈**: 0건(#144 포함 W5 잔여 전부 close). 저우선 후속 A/B/C는 별도 이슈 추적(HANDOFF_2026-06-09-followups §2).`
(`#<A>`는 Task 5 후 치환.)

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/HANDOFF_W5.md
git commit -m "docs(handoff): HANDOFF_W5 #144 OPEN→CLOSED 정합(9140e597 재수정)"
```

---

### Task 4: HISTORY_gitops.md 엔트리 추가

**Files:**
- Modify: `docs/project-management/history/HISTORY_gitops.md`

- [ ] **Step 1: 2026-06-09 엔트리 삽입**

`## 다음 항목 템플릿`(L491) 바로 앞에 삽입:
```markdown
## 2026-06-09 (W5) — 잔여 5건 라이브 완주 + #144 close

1회 on-demand EKS 라이브(과금, 63 destroyed·과금0 종료). 브레인스토밍→spec→plan→subagent. spec/plan `2026-06-09-w5-remaining-backlog-sha-semver-pin*`, 핸드오프 `HANDOFF_2026-06-09-followups.md`.

### 결과 (OPEN 이슈 0건 달성)
- **#157 SHA→semver 핀 close** — dev overlay 6앱 1.0.0 핀(PR #158) + ECR 6앱 1.0.0 재태그 + 라이브 배포 검증.
- **#156 staging DB 분리 close** — 전용 RDS `synapse-staging-postgres`(PR #160) 인스턴스 격리.
- **#155 Step11 드릴 close** — operator 라이브 드릴(CrashLoop·OOM 재현·복구), team-lead 따라하기 충족.
- **#126 ruleset close** — image-updater GitHub App 전환(옵션3), Maintain bypass 수용(팀 결정).
- **#144 learning-ai close** — 2차 라이브에서 재수정 검증(아래).
- **engagement-svc-dev** — phantom `1.0.1`(IU 데모 잔재) ImagePull → `1.0.0` 정정(PR #161).

### 의사결정
- **#144 근본원인 = 코드 머지 ≠ 빌드 반영**: 핀된 `3774e2e6`은 `fix(avro) #64` 빌드라 앱팀 PR #63(ssl_context)이 미포함. 어느 커밋이 이미지가 됐는지 SHA 대조 필수.
  - **실수정**: learning-svc PR #67 — `ssl_support.py`로 producer/consumer에 `ssl_context` 실제 전달 + TLS 단위테스트. ECR `learning-ai:9140e597` → 2차 라이브 1/1 Running·ssl_context 0건.
  - **대안 검토**: 앱팀 재수정 대기(다음 윈도우 지연) vs gitops가 직접 수정(채택, 크로스레포 admin 머지로 즉시 해소).

### 이벤트 (라이브 운영 메모 — 재발 방지)
- bring-up 미자동화: 서비스 DB 5종(psql CREATE DATABASE)·MSK 토픽 9종(kafka SSL) 수동 → 미생성 시 Spring/aiokafka 크래시. **→ 후속 C로 자동화 착수(2026-06-10)**.
- selfHeal: resource 패치 즉시 자동원복. `set env` override는 3-way merge로 미원복.
- ECR 재태그: batch-get→put-image는 manifest digest만 변경, config·layer 동일.

### 산출물
- PR #158~#163 머지. learning-ai/card `9140e597` bump. 핸드오프 `HANDOFF_2026-06-09-followups.md`.

---

## 2026-06-10 (W5 마감) — 일정 문서 동기화 + 후속 3건 이슈화 + 후속 C 구현

### 무엇을 했는지
- 일정 추적 문서 4종(WORKFLOW_W5·TASK·HANDOFF_W5·HISTORY) 현실 동기화 — W5 사실상 완주·OPEN 0건 반영.
- 저우선 후속 3건 GitHub 이슈화: A(learning-card-staging 조사 #<A>)·B(semver 재핀 전략 #<B>)·C(bring-up 토픽/DB 자동화 #<C>).
- **후속 C 구현**: `bring-up.sh` `phase_kafka_topics`(MSK 토픽 9종, 클러스터 내 apache/kafka Job·SSL)·`phase_db_init`(DB 5종, postgres Job·dev+staging RDS) + 토픽 리스트 단일 출처 `infra/kafka/topics.txt`.

### 의사결정
- **후속 C 접근법 A(클러스터 내 Job) + C(토픽 단일파일)**: bring-up은 SSM 터널 kubectl 모델 → MSK/RDS private subnet 도달은 클러스터 내부 Job만 가능(bastion terraform 경로는 bring-up 호스트에서 부적합). 토픽명 drift는 `topics.txt`를 terraform+Job 공유로 해소.
  - **대안 검토**: B(bastion SSM terraform) — SSM 오케스트레이션 bash 취약 → 기각.
- **라이브 검증 보류**: 클러스터 destroy 상태(과금0) → 오프라인 검증(`bash -n`·`--dry-run`·`terraform validate`)만, 실생성은 다음 윈도우(#<C>에서 close).

### 산출물
- 브랜치 `docs/w5-followups-doc-sync-provisioning`, PR #<PR>. spec/plan `2026-06-10-w5-followups-doc-sync-provisioning*`. `infra/kafka/topics.txt`, `bring-up.sh` phase 2종, `outputs.tf` rds_username.
```
(`#<A>`/`#<B>`/`#<C>`/`#<PR>`는 Task 5 / PR 생성 후 치환.)

- [ ] **Step 2: 검증**

Run: `grep -n "2026-06-09\|2026-06-10" docs/project-management/history/HISTORY_gitops.md`
Expected: 두 엔트리 제목이 `## 다음 항목 템플릿` 앞에 위치.

- [ ] **Step 3: Commit**

```bash
git add docs/project-management/history/HISTORY_gitops.md
git commit -m "docs(history): 2026-06-09 잔여완주·#144 close + 2026-06-10 문서동기화·후속C 엔트리"
```

---

### Task 5: GitHub 이슈 3건 생성 + 번호 역링크

**Files:**
- (gh CLI 사용, 이후 Task 2/3/4 산출물에 번호 치환)

- [ ] **Step 1: 이슈 A 생성**

```bash
gh issue create --title "[ops] learning-card-staging Degraded 근본원인 조사 (라이브)" --body "$(cat <<'EOF'
## 증상
라이브 윈도우(2026-06-09)에서 `synapse-learning-card-staging` = Degraded. dev는 Healthy. staging RDS 연결 정상(JDBC `synapse_learning` 확인 → DB 무관).

## 정적 분석 (완료)
staging overlay는 dev 대비: replica 2 · profile `staging` · `newTag: dev-latest`(dev=9140e597).

## 다음 액션 (라이브 윈도우 필요)
- `kubectl -n synapse-staging logs deploy/learning-card --previous --tail=50`로 크래시 근본원인 확인.
- 가설: ① `dev-latest`가 가리키는 이미지 ② staging 프로파일 설정 ③ replica 2 리소스.
- 선행: DB 5종·Kafka 토픽 선생성(후속 C) 후 관찰.

## 우선순위
낮음 (staging 한정, dev 정상).

출처: HANDOFF_2026-06-09-followups.md §2 후속 A.
EOF
)"
```

- [ ] **Step 2: 이슈 B 생성**

```bash
gh issue create --title "[ops] learning-ai·card semver 재핀 — SHA vs semver 태깅 전략 결정" --body "$(cat <<'EOF'
## 현재
deploy-service.yml write-back으로 learning-ai/card dev overlay = SHA `9140e597`(#157 semver 1.0.0 핀에서 회귀). engagement·knowledge·platform·gateway·frontend는 1.0.0 유지.

## 영향
IU `semver` 전략에서 이 2앱 `Invalid Semantic Version` skip(자동 업데이트 안 됨). 런타임 영향 없음.

## 근본 긴장
shared `deploy-service.yml`이 SHA 태깅 ↔ IU `semver` 전략 충돌. 매 배포마다 SHA 회귀 → semver 핀은 일시적.

## 옵션
- (a) 임시: ECR `9140e597`→`1.0.0` 재태그 + overlay 정정(1회, 다음 배포에 또 회귀 → 무의미).
- (b) 근본: `deploy-service.yml`을 semver 태깅 전환(shared, 크로스레포 — 팀 조율).
- (c) 근본: IU 전략을 `digest`/`newest-build` 전환(전 앱, mutable 태그 추적).

## 다음 액션
팀과 SHA vs semver 전략 정리(b/c) → 결정 후 일괄 적용.

## 우선순위
낮음 (런타임 영향 없음, IU 자동업데이트만).

출처: HANDOFF_2026-06-09-followups.md §2 후속 B.
EOF
)"
```

- [ ] **Step 3: 이슈 C 생성**

```bash
gh issue create --title "[infra] bring-up Kafka 토픽 9종 + DB 5종 자동 프로비저닝" --body "$(cat <<'EOF'
## 현재
bring-up이 MSK 토픽 9종·서비스 DB 5종을 자동생성 안 함 → 매 윈도우 수동. 미생성 시 learning-ai(aiokafka) `UnknownTopicOrPartitionError`·Spring `database does not exist` 크래시.

## 구현 (2026-06-10, 오프라인)
- `infra/kafka/topics.txt` 토픽 단일 출처화(terraform + Job 공유, drift 제거).
- `bring-up.sh` `phase_kafka_topics`(클러스터 내 apache/kafka:3.9.0 Job, SSL, `--if-not-exists`).
- `bring-up.sh` `phase_db_init`(클러스터 내 postgres:16 Job, dev+staging RDS, psql `\gexec` 멱등).
- 접근법 A(클러스터 내 Job) + C(토픽 단일파일). spec/plan: `docs/superpowers/{specs,plans}/2026-06-10-w5-followups-doc-sync-provisioning*`.

## 라이브 검증 대기 (다음 윈도우, 이 이슈 close 조건)
- `--from kafka-topics --to db-init` 실행 → 토픽 9종·DB 5종 실생성 확인.
- learning-ai 1/1 Running(토픽 존재)·Spring DB 연결 확인.

## 우선순위
낮음~중 (매 윈도우 반복 수작업 제거).

출처: HANDOFF_2026-06-09-followups.md §2 후속 C.
EOF
)"
```

- [ ] **Step 4: 이슈 번호 역링크 치환**

세 이슈의 출력 번호를 확인:
```bash
gh issue list --state open --limit 5
```
Task 2 Step 3, Task 3 Step 3, Task 4 Step 1의 `#<A>`/`#<B>`/`#<C>` placeholder를 실제 번호로 치환(Edit). 그 후:
```bash
git add docs/project-management/task/TASK_gitops.md docs/superpowers/HANDOFF_W5.md docs/project-management/history/HISTORY_gitops.md
git commit -m "docs: 후속 A/B/C 이슈 번호 역링크"
```

---

## 파트 2 — 후속 C 구현

### Task 6: 토픽 리스트 단일 출처화 (topics.txt + terraform)

**Files:**
- Create: `infra/kafka/topics.txt`
- Modify: `infra/aws/dev/kafka-topics/main.tf:5-17`

- [ ] **Step 1: topics.txt 생성**

```
# infra/kafka/topics.txt
# MSK/EKS 토픽 정본(단일 출처). terraform(kafka-topics/main.tf)과 bring-up.sh phase_kafka_topics가 공유.
# 기준: shared EVENT_CONTRACT_STANDARD §2. 로컬 docker-compose(create-topics.sh, PLAINTEXT)는 별도 트랙.
# 1줄당 토픽 1개. '#' 주석/빈줄 무시.
platform.auth.user-registered-v1
knowledge.note.note-created-v1
knowledge.note.note-updated-v1
learning.card.review-completed-v1
learning.card.review-due-v1
engagement.gamification.level-up-v1
engagement.gamification.badge-earned-v1
platform.notification.notification-send-v1
learning.ai.cards-generated-v1
```

- [ ] **Step 2: terraform locals를 파일 참조로 전환**

`infra/aws/dev/kafka-topics/main.tf` 의 `locals { topics = [...] }` 블록(L5~L17)을 교체:
```hcl
# 토픽 단일 출처: infra/kafka/topics.txt (terraform + bring-up.sh 공유).
# 기존 인라인 배열 → 파일에서 로드(빈줄·'#' 주석 제거).
locals {
  topics = [
    for line in split("\n", file("${path.module}/../../../kafka/topics.txt")) :
    trimspace(line)
    if trimspace(line) != "" && !startswith(trimspace(line), "#")
  ]
}
```
주의: 경로는 `kafka-topics/`에서 `infra/kafka/topics.txt`까지 = `../../../kafka/topics.txt` (`kafka-topics`→`dev`→`aws`→`infra`, 그 아래 `kafka/`). 

- [ ] **Step 3: terraform 파싱 검증**

Run: `terraform -chdir=infra/aws/dev/kafka-topics validate`
Expected: `Success! The configuration is valid.` (provider init 필요 시 `terraform -chdir=infra/aws/dev/kafka-topics init -backend=false` 선행)

토픽 9개 파싱 확인:
```bash
terraform -chdir=infra/aws/dev/kafka-topics console <<<'length(local.topics)'
```
Expected: `9` (console이 provider 자격 요구로 실패하면 skip — validate 통과로 충분)

- [ ] **Step 4: 라인 수 교차 검증**

Run: `grep -vc '^\s*#\|^\s*$' infra/kafka/topics.txt`
Expected: `9`

- [ ] **Step 5: Commit**

```bash
git add infra/kafka/topics.txt infra/aws/dev/kafka-topics/main.tf
git commit -m "refactor(kafka): 토픽 리스트 단일 출처 topics.txt로 추출 (terraform 공유)"
```

---

### Task 7: rds_username output + phase_db_init

**Files:**
- Modify: `infra/aws/dev/outputs.tf` (rds 섹션, L46 이후)
- Modify: `scripts/bring-up.sh`

- [ ] **Step 1: rds_username output 추가**

`infra/aws/dev/outputs.tf` 의 `output "rds_port"` 블록(L43~L46) 다음에 추가:
```hcl
output "rds_username" {
  description = "RDS master username (dev+staging 공통). phase_db_init psql 접속용."
  value       = var.rds_username
}
```

- [ ] **Step 2: phase_db_init 함수 추가**

`scripts/bring-up.sh` 의 `phase_kafka_config()` 함수 끝(L157, 닫는 `}`) 다음에 삽입:
```bash
phase_db_init() {
  # 후속 C: 서비스 DB 5종을 dev + staging RDS에 멱등 생성(psql \gexec).
  # RDS는 private subnet → 클러스터 내 postgres Job으로 실행(bring-up 호스트 직접 도달 불가).
  # 자격: dev+staging 공통 master(username=output, password=TF_VAR_rds_password). 기본 db 'synapse' 접속.
  if $DRY_RUN; then echo "+ db-init: dev+staging RDS에 synapse_{platform,engagement,knowledge,learning,ai} 5종(postgres Job, \\gexec 멱등)"; return; fi
  local user pass dev_ep stg_ep
  user=$(terraform -chdir=$TFDIR output -raw rds_username)
  pass="${TF_VAR_rds_password:?phase_db_init: TF_VAR_rds_password 필요(RDS master)}"
  dev_ep=$(terraform -chdir=$TFDIR output -raw rds_endpoint)        # host:port
  stg_ep=$(terraform -chdir=$TFDIR output -raw rds_staging_endpoint)
  local dbs="synapse_platform synapse_engagement synapse_knowledge synapse_learning synapse_ai"
  # \gexec 멱등 SQL 생성
  local sql=""
  for db in $dbs; do
    sql+="SELECT 'CREATE DATABASE ${db}' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname='${db}')\\gexec"$'\n'
  done
  for ep in "$dev_ep" "$stg_ep"; do
    local host="${ep%%:*}" port="${ep##*:}"
    [ "$host" = "$port" ] && port=5432
    log "db-init → $host"
    kubectl -n synapse-dev run "db-init-${host%%.*}" --rm -i --restart=Never \
      --image=postgres:16 --timeout=180s \
      --env="PGPASSWORD=$pass" --command -- \
      psql "host=$host port=$port user=$user dbname=synapse sslmode=require" -v ON_ERROR_STOP=1 -c "$sql" \
      || warn "db-init $host 실패(RDS 미기동/자격 가능) — 재시도: --from db-init"
  done
  ok "DB 5종 적용(dev+staging)"
}
```

- [ ] **Step 3: 문법 검증**

Run: `bash -n scripts/bring-up.sh`
Expected: 출력 없음(exit 0)

- [ ] **Step 4: outputs.tf validate**

Run: `terraform -chdir=infra/aws/dev validate` (필요 시 `init -backend=false` 선행)
Expected: `Success! The configuration is valid.`

- [ ] **Step 5: Commit**

```bash
git add infra/aws/dev/outputs.tf scripts/bring-up.sh
git commit -m "feat(bring-up): phase_db_init — dev+staging RDS DB 5종 멱등 생성(postgres Job)"
```

---

### Task 8: phase_kafka_topics

**Files:**
- Modify: `scripts/bring-up.sh`

- [ ] **Step 1: phase_kafka_topics 함수 추가**

`scripts/bring-up.sh` 의 (Task 7에서 추가한) `phase_db_init()` 함수 끝 `}` 다음에 삽입:
```bash
phase_kafka_topics() {
  # 후속 C: MSK 토픽 9종을 클러스터 내 apache/kafka Job(SSL)으로 멱등 생성(--if-not-exists).
  # MSK private subnet → 클러스터 내부 실행만 도달. 토픽 정본 = infra/kafka/topics.txt(ConfigMap 적재).
  # 무인증 TLS-only(MSK SSL 서버인증) → client.properties=security.protocol=SSL.
  if $DRY_RUN; then echo "+ kafka-topics: infra/kafka/topics.txt 9종(apache/kafka:3.9.0 Job, SSL, --if-not-exists, RF=2)"; return; fi
  local brokers
  brokers=$(terraform -chdir=$TFDIR output -raw msk_bootstrap_brokers_tls)
  # 토픽 리스트를 ConfigMap으로 적재(파일 단일 출처)
  kubectl create configmap kafka-topics-list -n synapse-dev \
    --from-file=topics.txt=infra/kafka/topics.txt --dry-run=client -o yaml | kubectl apply -f -
  # Job: client.properties + 각 토픽 --if-not-exists 생성
  kubectl -n synapse-dev delete job kafka-topics-init --ignore-not-found
  kubectl apply -f - <<YAML
apiVersion: batch/v1
kind: Job
metadata:
  name: kafka-topics-init
  namespace: synapse-dev
spec:
  backoffLimit: 2
  ttlSecondsAfterFinished: 300
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: kafka-topics
          image: apache/kafka:3.9.0
          env:
            - name: BROKERS
              value: "$brokers"
          command: ["/bin/sh", "-c"]
          args:
            - |
              set -eu
              echo "security.protocol=SSL" > /tmp/client.properties
              BIN=/opt/kafka/bin/kafka-topics.sh
              while IFS= read -r t; do
                case "\$t" in ''|\#*) continue;; esac
                echo "Creating \$t"
                "\$BIN" --bootstrap-server "\$BROKERS" --command-config /tmp/client.properties \
                  --create --if-not-exists --topic "\$t" \
                  --partitions 3 --replication-factor 2 \
                  --config min.insync.replicas=2 --config retention.ms=604800000
              done < /etc/kafka-topics/topics.txt
              echo "--- topics ---"
              "\$BIN" --bootstrap-server "\$BROKERS" --command-config /tmp/client.properties --list
          volumeMounts:
            - name: topics
              mountPath: /etc/kafka-topics
      volumes:
        - name: topics
          configMap:
            name: kafka-topics-list
YAML
  kubectl -n synapse-dev wait --for=condition=complete job/kafka-topics-init --timeout=180s \
    || warn "kafka-topics-init 미완료(MSK 미기동/SG 가능) — 로그: kubectl -n synapse-dev logs job/kafka-topics-init; 재시도: --from kafka-topics"
  ok "MSK 토픽 9종 적용(멱등)"
}
```

- [ ] **Step 2: 문법 검증**

Run: `bash -n scripts/bring-up.sh`
Expected: 출력 없음(exit 0)

- [ ] **Step 3: Job YAML heredoc 스키마 검증**

heredoc 변수 전개를 확인하기 위해 더미 값으로 렌더 후 client-side validate:
```bash
brokers="b-1.example:9094,b-2.example:9094"
sed -n '/kubectl apply -f - <<YAML/,/^YAML/p' scripts/bring-up.sh \
  | sed '1d;$d' | sed "s/\$brokers/$brokers/g" \
  | kubectl apply --dry-run=client -f - 2>&1 | head -5
```
Expected: `job.batch/kafka-topics-init created (dry run)` 또는 동등(스키마 valid). 실패 시 YAML 들여쓰기/전개 수정.

- [ ] **Step 4: Commit**

```bash
git add scripts/bring-up.sh
git commit -m "feat(bring-up): phase_kafka_topics — MSK 토픽 9종 멱등 생성(apache/kafka Job SSL)"
```

---

### Task 9: phase 등록(PHASES + usage) + 통합 오프라인 검증

**Files:**
- Modify: `scripts/bring-up.sh:37` (PHASES 배열)
- Modify: `scripts/bring-up.sh:28-29` (usage 도움말)

- [ ] **Step 1: PHASES 배열에 신설 phase 삽입**

`scripts/bring-up.sh` L37 의 PHASES 배열에서 `kafka-config manifests` 사이에 `kafka-topics db-init` 삽입:
```bash
PHASES=(terraform eks-auth tunnel argocd eso oidc-fix alb-controller kafka-config kafka-topics db-init manifests metrics-server image-updater observability status)
```

- [ ] **Step 2: usage 도움말 phase 목록 갱신**

L28~L29 `--from`/`--to` 설명의 phase 나열에 `kafka-topics|db-init`를 `kafka-config` 다음에 추가:
```
  --from <phase>   해당 phase부터 재개 (terraform|eks-auth|tunnel|argocd|eso|oidc-fix|alb-controller|kafka-config|kafka-topics|db-init|manifests|metrics-server|image-updater|observability|status)
```

- [ ] **Step 3: 문법 + phase 인식 검증**

```bash
bash -n scripts/bring-up.sh
```
Expected: exit 0.

```bash
bash scripts/bring-up.sh --dry-run --from kafka-config --to manifests
```
Expected: phase 순서 출력에 `=== phase: kafka-config ===` → `=== phase: kafka-topics ===` → `=== phase: db-init ===` → `=== phase: manifests ===` 포함, 각 `+ ...` dry-run 라인 출력. (terraform output 호출은 dry-run 분기로 우회되어 클러스터/자격 불필요.)

- [ ] **Step 4: shellcheck (가용 시)**

Run: `shellcheck scripts/bring-up.sh || echo "shellcheck 미설치 — skip"`
Expected: 신설 코드 관련 error 0건(기존 경고는 무관). SC2086 등 의도된 분할은 무시.

- [ ] **Step 5: Commit**

```bash
git add scripts/bring-up.sh
git commit -m "feat(bring-up): kafka-topics·db-init phase 등록(PHASES+usage) + dry-run 검증"
```

---

### Task 10: PR 생성

- [ ] **Step 1: push + PR**

```bash
git push -u origin docs/w5-followups-doc-sync-provisioning
gh pr create --title "W5 마감: 일정 문서 동기화 + 후속 A/B/C 이슈 + bring-up 토픽/DB 자동 프로비저닝" --body "$(cat <<'EOF'
## 요약
W5 잔여 백로그 라이브 완주(2026-06-09, OPEN 0건) 후속.

### 파트 1 — 문서/추적
- 일정 문서 4종 동기화(WORKFLOW_W5·TASK·HANDOFF_W5·HISTORY) — W5 완주·#144 close·OPEN 0건 반영.
- 후속 3건 GitHub 이슈화(A: learning-card-staging / B: semver 전략 / C: 토픽·DB 자동화).

### 파트 2 — 후속 C 구현 (#<C>)
- `infra/kafka/topics.txt` 토픽 단일 출처화(terraform 공유, drift 제거).
- `bring-up.sh` `phase_kafka_topics`(MSK 토픽 9종, apache/kafka Job SSL)·`phase_db_init`(DB 5종, postgres Job, dev+staging RDS). 멱등·dry-run/from/to 준수.
- `outputs.tf` rds_username 추가.

## 검증 (오프라인)
- `bash -n scripts/bring-up.sh` ✅
- `bash scripts/bring-up.sh --dry-run --from kafka-config --to manifests` — 신설 phase 인식 ✅
- `terraform -chdir=infra/aws/dev/kafka-topics validate` / `infra/aws/dev validate` ✅
- Job YAML `kubectl --dry-run=client` ✅
- **라이브 토픽/DB 실생성 검증은 다음 윈도우**(#<C> close 조건).

spec/plan: `docs/superpowers/{specs,plans}/2026-06-10-w5-followups-doc-sync-provisioning*`.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```
(`#<C>`는 실제 이슈 번호로 치환.)

Expected: PR URL 출력. `validate-manifests` CI 통과 확인.

---

## Self-Review 결과

- **Spec coverage**: 파트1 문서4종(Task1~4)·이슈3건(Task5) ✅. 파트2 topics.txt+terraform(Task6)·phase_db_init(Task7)·phase_kafka_topics(Task8)·등록+검증(Task9)·PR(Task10) ✅. 스펙 §3.5 오프라인 검증 5종 → Task6 Step3-4, Task7 Step3-4, Task8 Step2-3, Task9 Step3-4 매핑 ✅.
- **Placeholder scan**: `#<A>/<B>/<C>/<PR>`는 의도된 치환 토큰(Task5/PR에서 실제 번호로 교체 명시) — 실행 가능 지시 동반. 그 외 TBD/TODO 없음.
- **Type/이름 일관성**: phase 이름 `kafka-topics`/`db-init` → 함수 `phase_kafka_topics`/`phase_db_init`(`${p//-/_}` 규약 일치) ✅. terraform output 이름(`rds_endpoint`/`rds_staging_endpoint`/`rds_username`/`msk_bootstrap_brokers_tls`) 실재 확인 ✅. DB 5종·토픽 9종 정본 일치 ✅. ConfigMap `kafka-topics-list` / Job `kafka-topics-init` 일관 ✅.
