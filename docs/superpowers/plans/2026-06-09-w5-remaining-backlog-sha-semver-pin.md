# W5 잔여 백로그 정리 + dev overlay SHA→semver 핀 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 잔여 5건을 추적 가능한 정본(HANDOFF_W5 표 + GH 이슈 3)으로 정리하고, 외부 블로커 없는 항목5(dev overlay 6앱 SHA/dev-latest→semver `1.0.0` 핀)를 실행한다.

**Architecture:** 두 개의 PR(피처브랜치→PR→main, ArgoCD `targetRevision: main`)과 3개의 GH 이슈로 구성. PR1=overlay 핀(코드), PR2=추적 문서(HANDOFF/TASK). 이슈를 먼저 만들어 번호를 PR/문서가 참조한다. overlay 핀은 비용0(클러스터 destroy 상태) — 런타임 반영은 다음 라이브 윈도우 ECR 재태그 후.

**Tech Stack:** kustomize 오버레이(`images[].newTag`), argocd-image-updater(`semver` 전략), yamllint(`.yamllint`), GitHub CLI(`gh`), GitHub Actions `validate`(kustomize 5.4.3 + kubeconform 0.6.7 + yamllint).

**검증 환경 주의:** 로컬엔 `kustomize`/`kubeconform`/`yamllint` 미설치, `python`/`pip`/`gh` 존재. 로컬 게이트 = `python -m yamllint`(주석 구문/들여쓰기 리스크 커버). `kustomize build`/`kubeconform`은 순수 태그 스칼라 변경이라 깨질 수 없으며 **PR의 CI `validate` 잡이 권위 검증**이다.

---

## File Structure

| 파일 | 책임 | 작업 |
|------|------|------|
| `apps/knowledge-svc/overlays/dev/kustomization.yaml` | dev knowledge 오버레이 | Modify L67-69 |
| `apps/platform-svc/overlays/dev/kustomization.yaml` | dev platform 오버레이 | Modify L79-81 |
| `apps/gateway/overlays/dev/kustomization.yaml` | dev gateway 오버레이 | Modify L41-43 |
| `apps/frontend/overlays/dev/kustomization.yaml` | dev frontend 오버레이 | Modify L15-17 |
| `apps/learning-card/overlays/dev/kustomization.yaml` | dev learning-card 오버레이 | Modify L59-61 |
| `apps/learning-ai/overlays/dev/kustomization.yaml` | dev learning-ai 오버레이(#144 결합) | Modify L53-55 |
| `docs/superpowers/HANDOFF_W5.md` | 잔여 5건 정본 핸드오프 | Rewrite |
| `docs/project-management/task/TASK_gitops.md` | gitops 태스크 정본 | Modify(머리말/꼬리 한 줄) |

GH 이슈 3개(파일 아님): `gh issue create` × 3.

브랜치: PR1=`fix/sha-semver-pin-dev-overlays`(off main), PR2=`docs/w5-remaining-backlog`(이미 존재, spec 커밋 `dccc327` 보유).

---

## Phase B 먼저: GH 이슈 3개 생성

> 이슈 번호를 PR1/문서가 참조하므로 가장 먼저 만든다. 브랜치 무관(`gh issue create`는 현재 브랜치와 독립).

### Task B1: Step11 team-lead 따라하기 이슈

- [ ] **Step 1: 이슈 생성**

Run:
```bash
gh issue create \
  --title "[ops] Step11 Done 조건: team-lead 런북 따라하기 1회 (async)" \
  --body "## 목적
Step11 운영 런북(incident 복구)을 **team-lead가 런북만 보고 1택 독립 복구 1회** 수행 → Step11 Done 확정.

## 배경
W5 윈도우2(2026-06-08)에서 incident-sim(ns synapse-sim)으로 crashloop/oom/sync 3종 재현·복구 + 알람 경로 검증 완료. 남은 Done 조건은 team-lead 따라하기뿐(비동기).

## next-action
team-lead 가용 시 \`docs/runbooks/incidents/\` + \`docs/runbooks/on-call.md\` 따라 1택 독립 복구.

## blocker
team-lead 가용시간.

## 참조
- \`docs/runbooks/W5_WINDOW_2.md\` Phase 5
- \`docs/superpowers/HANDOFF_W5.md\` 잔여 #1"
```
Expected: 이슈 URL 출력. 출력된 번호를 기록(이하 `<ISSUE_TEAMLEAD>`).

- [ ] **Step 2: 번호 확인**

Run: `gh issue list --search "team-lead 런북 따라하기" --state open`
Expected: 방금 만든 이슈 1건 표시.

### Task B2: staging DB 분리(항목8) 이슈

- [ ] **Step 1: 이슈 생성**

Run:
```bash
gh issue create \
  --title "[infra] staging 환경 DB 분리 (항목8) — team-lead 비용 결정 선행" \
  --body "## 목적
staging이 dev RDS·DB(\`synapse_platform\`)를 공유하는 환경 격리 갭 해소 — staging 전용 DB/인스턴스 분리.

## blocker
**team-lead 비용 결정** (전용 인스턴스/DB 추가는 사이징·시간당 과금 영향). 미결정 시 보류.

## next-action
비용 승인 시 \`infra/aws/\`(또는 staging 모듈)에 전용 DB/인스턴스 terraform + staging overlay DATABASE_* 전환.

## 완료조건
staging이 dev RDS와 분리된 전용 DB 사용(환경 격리).

## 참조
- \`docs/superpowers/specs/2026-06-08-w3-w4-incomplete-audit-design.md\` §4
- \`docs/superpowers/HANDOFF_W5.md\` 잔여 #2 / 항목8"
```
Expected: 이슈 URL 출력. 번호 기록(`<ISSUE_STAGINGDB>`).

- [ ] **Step 2: 번호 확인**

Run: `gh issue list --search "staging 환경 DB 분리" --state open`
Expected: 1건 표시.

### Task B3: SHA→semver 핀 + ECR 재태그 이슈

- [ ] **Step 1: 이슈 생성**

Run:
```bash
gh issue create \
  --title "[ops] dev overlay SHA/dev-latest → semver 핀 + ECR 재태그 (6앱)" \
  --body "## 목적
dev overlay 6앱(knowledge·platform·gateway·frontend·learning-card·learning-ai)의 \`newTag\`가 SHA/dev-latest라 argocd-image-updater \`semver\` 전략에서 \`Invalid Semantic Version\`으로 skip됨. semver 베이스라인 \`1.0.0\`으로 핀해 IU 정상화.

## 작업 분할
- [x] **overlay 핀**(이 이슈 PR: \`fix/sha-semver-pin-dev-overlays\`) — 6앱 newTag→1.0.0 + 주석. 비용0.
- [ ] **ECR 재태그**(다음 라이브 윈도우) — 각 앱 ECR에서 현재 SHA→1.0.0 재태그(\`aws ecr batch-get-image\` | \`put-image\`, 동일 digest). 미선결 시 sync 후 ImagePullBackOff.
- [ ] **learning-ai 예외** — 1.0.0은 #144 수정 이미지(앱팀 PR #63)에 재태그(현 acafc06b digest=CrashLoop이므로 금지).

## 완료조건
6앱 ECR에 1.0.0 존재 + 다음 윈도우 sync에서 IU semver 비교 정상(skip 해소).

## 참조
- \`argocd/applicationset.yaml\`(IU semver 전략)
- \`docs/runbooks/image-updater-ecr-setup.md\`
- #144(learning-ai 예외) / \`docs/superpowers/HANDOFF_W5.md\` 잔여 #5"
```
Expected: 이슈 URL 출력. 번호 기록(`<ISSUE_PIN>`).

- [ ] **Step 2: 번호 확인**

Run: `gh issue list --search "dev overlay SHA" --state open`
Expected: 1건 표시.

---

## Phase A: PR1 — dev overlay SHA→semver 핀

### Task A1: PR1 브랜치 생성 (main 기준)

**Files:** 없음(브랜치 작업)

- [ ] **Step 1: main 최신화 후 브랜치 생성**

Run:
```bash
git checkout main
git pull --ff-only origin main
git checkout -b fix/sha-semver-pin-dev-overlays
```
Expected: `Switched to a new branch 'fix/sha-semver-pin-dev-overlays'`.

### Task A2: 공용 5앱 newTag 핀 (knowledge·platform·gateway·frontend·learning-card)

**Files:**
- Modify: `apps/knowledge-svc/overlays/dev/kustomization.yaml:67-69`
- Modify: `apps/platform-svc/overlays/dev/kustomization.yaml:79-81`
- Modify: `apps/gateway/overlays/dev/kustomization.yaml:41-43`
- Modify: `apps/frontend/overlays/dev/kustomization.yaml:15-17`
- Modify: `apps/learning-card/overlays/dev/kustomization.yaml:59-61`

> 각 파일에서 `newTag: <OLD>` 줄만 교체한다. 주석은 4-space 들여쓰기(기존 engagement-svc 주석과 동일 위치 — yamllint `comments-indentation: disable`이라 안전). `was <OLD>`에 기존 값을 정확히 적어 추적성 유지.

- [ ] **Step 1: knowledge-svc** — `apps/knowledge-svc/overlays/dev/kustomization.yaml`

Edit old_string:
```yaml
    newTag: dev-latest
```
Edit new_string:
```yaml
    # image-updater A안: semver update-strategy 호환 위해 semver 베이스라인으로 핀 (was dev-latest).
    # ECR에 1.0.0 태그 존재 필요 — 다음 라이브 윈도우에서 기존 태그→1.0.0 재태그
    # (aws ecr batch-get-image | put-image, 동일 digest) 선결. 미선결 시 sync 후 ImagePullBackOff.
    newTag: 1.0.0
```

- [ ] **Step 2: platform-svc** — `apps/platform-svc/overlays/dev/kustomization.yaml`

Edit old_string:
```yaml
    newTag: bc5440144780fbaaa53a74e2e6d8baef0b8beafd
```
Edit new_string:
```yaml
    # image-updater A안: semver update-strategy 호환 위해 semver 베이스라인으로 핀 (was bc544014…SHA).
    # ECR에 1.0.0 태그 존재 필요 — 다음 라이브 윈도우에서 SHA→1.0.0 재태그
    # (aws ecr batch-get-image | put-image, 동일 digest) 선결. 미선결 시 sync 후 ImagePullBackOff.
    newTag: 1.0.0
```

- [ ] **Step 3: gateway** — `apps/gateway/overlays/dev/kustomization.yaml`

Edit old_string:
```yaml
    newTag: 9e4f190a37efd52abe24c72fb659d98c350f8988
```
Edit new_string:
```yaml
    # image-updater A안: semver update-strategy 호환 위해 semver 베이스라인으로 핀 (was 9e4f190a…SHA).
    # ECR에 1.0.0 태그 존재 필요 — 다음 라이브 윈도우에서 SHA→1.0.0 재태그
    # (aws ecr batch-get-image | put-image, 동일 digest) 선결. 미선결 시 sync 후 ImagePullBackOff.
    newTag: 1.0.0
```

- [ ] **Step 4: frontend** — `apps/frontend/overlays/dev/kustomization.yaml`

Edit old_string:
```yaml
    newTag: e4532fee21683cf88b21937f9b8977d7f9037ad3
```
Edit new_string:
```yaml
    # image-updater A안: semver update-strategy 호환 위해 semver 베이스라인으로 핀 (was e4532fee…SHA).
    # ECR에 1.0.0 태그 존재 필요 — 다음 라이브 윈도우에서 SHA→1.0.0 재태그
    # (aws ecr batch-get-image | put-image, 동일 digest) 선결. 미선결 시 sync 후 ImagePullBackOff.
    newTag: 1.0.0
```

- [ ] **Step 5: learning-card** — `apps/learning-card/overlays/dev/kustomization.yaml`

Edit old_string:
```yaml
    newTag: acafc06b6fc6ec1bcb076f0ccb4487ad29da9274
```
Edit new_string:
```yaml
    # image-updater A안: semver update-strategy 호환 위해 semver 베이스라인으로 핀 (was acafc06b…SHA).
    # ECR에 1.0.0 태그 존재 필요 — 다음 라이브 윈도우에서 SHA→1.0.0 재태그
    # (aws ecr batch-get-image | put-image, 동일 digest) 선결. 미선결 시 sync 후 ImagePullBackOff.
    newTag: 1.0.0
```

### Task A3: learning-ai newTag 핀 (#144 결합 주석)

**Files:**
- Modify: `apps/learning-ai/overlays/dev/kustomization.yaml:53-55`

> learning-ai는 동일 SHA(`acafc06b…`)지만 #144(aiokafka ssl_context CrashLoop) 때문에 재태그 대상 digest가 다르다. 전용 주석으로 "현 digest 재태그 금지"를 명시.

- [ ] **Step 1: learning-ai 편집** — `apps/learning-ai/overlays/dev/kustomization.yaml`

Edit old_string:
```yaml
    newTag: acafc06b6fc6ec1bcb076f0ccb4487ad29da9274
```
Edit new_string:
```yaml
    # image-updater A안: semver 베이스라인 핀 (was acafc06b…SHA).
    # 단, ECR 1.0.0은 #144(aiokafka ssl_context CrashLoop) 수정 이미지(앱팀 PR #63)에 재태그할 것.
    # 현재 acafc06b digest는 CrashLoop이므로 그 digest로 재태그 금지(다음 윈도우 선결).
    newTag: 1.0.0
```

### Task A4: 검증 (yamllint 로컬 + 변경 확인)

**Files:** 없음

- [ ] **Step 1: yamllint 설치(없으면)**

Run: `python -m pip install --quiet --user yamllint`
Expected: 성공(이미 설치면 즉시 반환).

- [ ] **Step 2: yamllint 실행 — 변경 파일 대상**

Run: `python -m yamllint -c .yamllint apps/knowledge-svc apps/platform-svc apps/gateway apps/frontend apps/learning-card apps/learning-ai`
Expected: 출력 없음(exit 0). 경고(line-length 등)는 `level: warning`이라 비차단이나, error는 0이어야 함.

- [ ] **Step 3: 변경 결과 확인 — 6개 모두 1.0.0인지**

Run: `git -c core.pager=cat diff --stat && grep -rn "newTag:" apps/*/overlays/dev/kustomization.yaml`
Expected: 6개 dev overlay가 `newTag: 1.0.0`(+engagement 기존 1.0.0). SHA/`dev-latest` 잔존 0건.

> kustomize build / kubeconform은 로컬 미설치 → PR의 CI `validate` 잡이 권위 검증(Task A6 이후 자동 실행). 태그 스칼라 변경이라 렌더 실패 불가.

### Task A5: 커밋

**Files:** 6개 dev overlay

- [ ] **Step 1: 커밋**

Run:
```bash
git add apps/knowledge-svc/overlays/dev/kustomization.yaml \
        apps/platform-svc/overlays/dev/kustomization.yaml \
        apps/gateway/overlays/dev/kustomization.yaml \
        apps/frontend/overlays/dev/kustomization.yaml \
        apps/learning-card/overlays/dev/kustomization.yaml \
        apps/learning-ai/overlays/dev/kustomization.yaml
git commit -m "$(cat <<'EOF'
fix(image-updater): dev overlay 6앱 SHA/dev-latest → semver 1.0.0 핀

argocd-image-updater semver 전략이 비-semver newTag를 Invalid Semantic
Version으로 skip → knowledge·platform·gateway·frontend·learning-card·
learning-ai 베이스라인 1.0.0 핀(engagement 패턴). ECR 1.0.0 재태그는
다음 라이브 윈도우 선결(주석 명시). learning-ai는 #144 수정 이미지에
재태그(현 acafc06b digest=CrashLoop 금지).

Refs #<ISSUE_PIN>, #144

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```
Expected: `6 files changed`. (`<ISSUE_PIN>`은 Task B3 번호로 치환.)

### Task A6: 푸시 + PR 생성

**Files:** 없음

- [ ] **Step 1: 푸시**

Run: `git push -u origin fix/sha-semver-pin-dev-overlays`
Expected: 원격 브랜치 생성.

- [ ] **Step 2: PR 생성**

Run:
```bash
gh pr create --base main --head fix/sha-semver-pin-dev-overlays \
  --title "fix(image-updater): dev overlay 6앱 SHA/dev-latest → semver 1.0.0 핀" \
  --body "## 무엇
dev overlay 6앱(knowledge·platform·gateway·frontend·learning-card·learning-ai)의 \`newTag\`를 SHA/dev-latest → semver 베이스라인 \`1.0.0\`으로 핀.

## 왜
argocd-image-updater \`semver\` 전략이 비-semver 태그를 \`Invalid Semantic Version\`으로 skip(engagement만 1.0.0 정상). 베이스라인 핀으로 IU 정상화.

## 런타임 주의 (비차단, 다음 윈도우 선결)
ECR엔 현재 SHA 태그만 존재 → sync 전 **ECR SHA→1.0.0 재태그**(\`aws ecr batch-get-image\` | \`put-image\`, 동일 digest) 선결. 미선결 시 ImagePullBackOff. 클러스터 현재 destroy(과금0)라 머지 자체는 무해. learning-ai는 #144 수정 이미지에 재태그(현 digest=CrashLoop 금지).

## 범위
dev overlay만(IU 대상). prod/staging·ECR 재태그·앱코드는 범위 밖.

## 검증
- 로컬 yamllint(.yamllint) 통과
- CI \`validate\`(kustomize build + kubeconform) 통과 기대

Refs #<ISSUE_PIN>, #144"
```
Expected: PR URL 출력.

- [ ] **Step 3: CI validate 결과 확인**

Run: `gh pr checks --watch`
Expected: `validate` 잡 success(diff-comment/parse 포함). 실패 시 로그 확인 후 수정.

---

## Phase C: PR2 — 추적 문서 (HANDOFF_W5 + TASK_gitops)

> 브랜치 `docs/w5-remaining-backlog`는 이미 존재하며 spec 커밋(`dccc327`)을 보유. 여기에 문서 변경을 추가.

### Task C1: 브랜치 전환 + HANDOFF_W5 재작성

**Files:**
- Rewrite: `docs/superpowers/HANDOFF_W5.md`

- [ ] **Step 1: 브랜치 전환 + main 변경 반영(선택)**

Run:
```bash
git checkout docs/w5-remaining-backlog
git merge --no-edit main
```
Expected: spec 커밋 위에 main 최신 반영(충돌 없음 기대).

- [ ] **Step 2: HANDOFF_W5.md 전체 재작성**

`docs/superpowers/HANDOFF_W5.md`를 아래 내용으로 **전체 교체**(Write):
```markdown
# W5 핸드오프: synapse-gitops — 잔여 5건 (윈도우2 완료 후)

> **갱신**: 2026-06-09 · **이전**: 2026-06-08(윈도우2 이관, 현재 stale 해소) · **발표**: 2026-06-15
> **정본 허브**: synapse-shared `HANDOFF_HUB.md`(team-lead 유지)

## 0. 윈도우2 완료 (2026-06-08, PR #145~#152, destroy로 과금0)

#121(prod 외부노출)·#122(IU write-back E2E) **close**. Step11 시뮬 3종+알람 경로·HPA 검증. #126 옵션3(GitHub App 토큰) 라이브. #144(learning-ai aiokafka ssl_context) 신규 발견. 상세: 메모리 `w5-window2-live-complete` / `HISTORY_gitops.md`.

## 1. 잔여 5건 (정본 표)

| # | 항목 | owner | blocker | next-action | 완료조건 | 추적 |
|---|------|-------|---------|-------------|---------|------|
| 1 | Step11 team-lead 따라하기 | team-lead | 가용시간 | 런북만 보고 1택 독립 복구 1회 | Step11 Done | #<ISSUE_TEAMLEAD> |
| 2 | staging 환경 DB 분리(항목8) | velka | **team-lead 비용 결정** | 전용 DB/인스턴스 terraform | staging≠dev RDS(환경 격리) | #<ISSUE_STAGINGDB> |
| 3 | #126 ruleset 축소 | velka | shared `deploy-service.yml` App 전환 동기화 | deploy-service GitHub App 토큰화 후 bypass 축소 | Maintain bypass 제거/축소 | #126 |
| 4 | learning-ai dev 복구 | 앱팀→velka | **앱팀 PR #63 수정 이미지** | 수정 이미지 ECR push→overlay bump | #144 close(dev Healthy) | #144 |
| 5 | dev overlay SHA→semver 핀 | velka | overlay분 없음 / ECR 재태그는 윈도우 | overlay 핀(PR `fix/sha-semver-pin-dev-overlays`)→ECR 재태그(윈도우) | 6앱 IU semver 정상(skip 해소) | #<ISSUE_PIN> |

**블로커 분류**: 1·2·4는 외부(team-lead·앱팀) 블록 → 이슈/대기 트래킹. 3은 cross-repo(shared)+org admin. 5는 overlay분 단독 완결(런타임만 윈도우 의존).

## 2. 다음 라이브 윈도우 선결 절차 (항목5 ECR 재태그)

overlay는 `1.0.0`으로 핀됨(PR 머지 시). bring-up/sync 전 ECR에 1.0.0 태그가 없으면 ImagePullBackOff → **6앱 각각 재태그**:
```bash
# 동일 digest 유지(현재 SHA가 가리키는 매니페스트를 1.0.0으로도 태깅)
REGION=ap-northeast-2; REPO_BASE=963773969059.dkr.ecr.$REGION.amazonaws.com/synapse
for app in knowledge-svc platform-svc gateway frontend learning-card; do
  SHA=$(현재 dev에 박혀있던 SHA)   # 핀 PR 직전 git log 또는 ECR describe-images로 확인
  MANIFEST=$(aws ecr batch-get-image --repository-name synapse/$app --image-ids imageTag=$SHA \
    --region $REGION --query 'images[0].imageManifest' --output text)
  aws ecr put-image --repository-name synapse/$app --image-tag 1.0.0 \
    --image-manifest "$MANIFEST" --region $REGION
done
```
**learning-ai 예외**: #144 수정 이미지(앱팀 PR #63 빌드)를 1.0.0으로 태깅. 현 `acafc06b` digest=CrashLoop이므로 절대 재태그 금지.

## 3. 레포 상태

- **OPEN 이슈**: #126·#144 · #<ISSUE_TEAMLEAD>·#<ISSUE_STAGINGDB>·#<ISSUE_PIN>. #91·#92·#120·#121·#122 close.
- **CI**: main 보호(PR + `validate`/diff-comment/parse).
- **설계**: `docs/superpowers/specs/2026-06-09-w5-remaining-backlog-sha-semver-pin-design.md`, `docs/superpowers/plans/2026-06-09-w5-remaining-backlog-sha-semver-pin.md`.
```
(`#<ISSUE_*>`는 Phase B 번호로 치환.)

### Task C2: TASK_gitops.md 머리말 동기화

**Files:**
- Modify: `docs/project-management/task/TASK_gitops.md`

- [ ] **Step 1: 잔여 포인터 한 줄 추가**

`docs/project-management/task/TASK_gitops.md`에서 Step 11 상태 블록(`**Status**: ... In Progress ...` Step11 항목, 약 L258) 바로 아래 HTML 주석 줄 다음에 한 줄 추가(Edit):

Edit old_string:
```
<!-- 2026-06-08 윈도우2: incident-sim(ns synapse-sim) 시뮬 3종·알람 라이브 검증. 발견: set env override는 sync 미원복(3-way merge), OOM은 requests≤limit 제약. team-lead 따라하기만 잔여. -->
```
Edit new_string:
```
<!-- 2026-06-08 윈도우2: incident-sim(ns synapse-sim) 시뮬 3종·알람 라이브 검증. 발견: set env override는 sync 미원복(3-way merge), OOM은 requests≤limit 제약. team-lead 따라하기만 잔여. -->
<!-- 2026-06-09: 잔여 5건 정본 = docs/superpowers/HANDOFF_W5.md 표(#1 team-lead 따라하기·#2 staging DB·#3 #126 ruleset·#4 #144 learning-ai·#5 SHA→semver 핀). -->
```

> 위 old_string이 정확히 일치하지 않으면, `grep -n "team-lead 따라하기만 잔여" docs/project-management/task/TASK_gitops.md`로 현재 줄을 찾아 그 직후에 동일한 신규 주석 한 줄을 삽입한다.

### Task C3: 검증 + 커밋 + 푸시 + PR

**Files:** `docs/superpowers/HANDOFF_W5.md`, `docs/project-management/task/TASK_gitops.md`

- [ ] **Step 1: 잔여 플레이스홀더 스캔**

Run: `grep -rn "<ISSUE_" docs/superpowers/HANDOFF_W5.md`
Expected: **출력 0건**(모든 `<ISSUE_*>`가 실제 번호로 치환됨). 남아있으면 치환.

- [ ] **Step 2: 커밋**

Run:
```bash
git add docs/superpowers/HANDOFF_W5.md docs/project-management/task/TASK_gitops.md
git commit -m "$(cat <<'EOF'
docs(handoff): HANDOFF_W5 잔여 5건 정본화 + TASK 동기화

윈도우2 완료(#121/#122 close) 반영해 stale 해소, 잔여 5건을
owner/blocker/next-action/완료조건/추적 표로 재작성. ECR 재태그
선결 절차 추가. TASK_gitops 머리말에 정본 포인터 한 줄.

Refs #<ISSUE_TEAMLEAD>, #<ISSUE_STAGINGDB>, #<ISSUE_PIN>, #126, #144

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```
Expected: `2 files changed`(+spec은 이미 커밋됨).

- [ ] **Step 3: 푸시 + PR 생성**

Run: `git push -u origin docs/w5-remaining-backlog`

```bash
gh pr create --base main --head docs/w5-remaining-backlog \
  --title "docs(handoff): W5 잔여 5건 정본화 + SHA→semver 핀 설계/플랜" \
  --body "## 무엇
- HANDOFF_W5 재작성 — 윈도우2 완료 반영 + 잔여 5건 정본 표(owner/blocker/next-action/완료조건/추적) + ECR 재태그 선결 절차.
- TASK_gitops 머리말 동기화(정본 포인터).
- 설계 spec + 구현 플랜 문서 포함.

## 추적
잔여 5건 → #<ISSUE_TEAMLEAD>·#<ISSUE_STAGINGDB>·#<ISSUE_PIN>·#126·#144.

## 관련 PR
overlay 핀 실행분: \`fix/sha-semver-pin-dev-overlays\`(#<ISSUE_PIN>)."
```
Expected: PR URL 출력.

- [ ] **Step 4: CI 확인**

Run: `gh pr checks --watch`
Expected: `validate` 등 success(문서 변경이라 렌더 무영향).

---

## 완료 정의 (Done)

- [ ] GH 이슈 3개 생성(team-lead 따라하기·staging DB·SHA→semver 핀).
- [ ] PR1(`fix/sha-semver-pin-dev-overlays`) — 6 overlay `newTag: 1.0.0` + 주석, CI `validate` green, 머지.
- [ ] PR2(`docs/w5-remaining-backlog`) — HANDOFF_W5 정본 표 + TASK 동기화 + spec/plan, CI green, 머지.
- [ ] 잔여 5건이 전부 이슈/문서로 추적 가시화(`<ISSUE_*>` 플레이스홀더 0건).

## 범위 밖 (YAGNI)

- ECR 재태그 실제 실행(라이브 윈도우·과금) — 절차만 HANDOFF에 기록.
- prod/staging overlay 핀 — IU 대상 아님.
- 항목 1·2·3·4 실행 — 외부 블로커, 트래킹만.
- IU update-strategy 변경 — 팀 전략(semver) 유지.
