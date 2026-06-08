# W3/W4 미완료 항목 감사 정합 — 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 감사 스펙(§6 정합 액션)을 실행 — `TASK_gitops.md` 상태 2곳을 현재 코드 상태(PR #136 포함)와 일치시키고, #92 이슈에 이중원인 정합 코멘트를 게시(OPEN 유지).

**Architecture:** 문서·이슈 정합만(비용 0, 코드 변경 없음). 감사 스펙 `docs/superpowers/specs/2026-06-08-w3-w4-incomplete-audit-design.md`의 §6. 브랜치 `docs/w3-w4-incomplete-audit`(스펙 커밋 위에 계속). 감사 문서 자체는 이미 머지 대상 — 본 계획은 TASK 편집 + 이슈 코멘트 + PR.

**Tech Stack:** Markdown 편집(Edit 툴), `gh issue comment`(GitHub CLI), 검증은 grep + 게시 전 본문 확인.

**전제 사실 (감사 §3/§4에서 검증됨, 그대로 사용):**
- platform-svc `main:application-staging.yml`이 `datasource.url: ${DB_URL}` 제공 — 확인됨
- gitops `apps/platform-svc/overlays/staging/kustomization.yaml`이 `DB_URL=.../synapse_platform`·`DATABASE_NAME=synapse_platform` 주입 — 확인됨(PR #136)
- staging 오버레이 `DB_URL` 호스트 = `synapse-dev-postgres`(dev와 동일 인스턴스·동일 DB) — 신규 발견
- #92 OPEN 유지(라이브 재검증 = 윈도우 2 소관)

---

### Task 1: TASK_gitops.md — W3 Step 7 Status 정합

**Files:**
- Modify: `docs/project-management/task/TASK_gitops.md` (Status 라인 ~152)

- [ ] **Step 1: Status 라인 교체**

기존(라인 152):
```markdown
**Status**: [ ] Not Started / [ ] In Progress / [x] Done (auto-sync·승격문서·Ingress매니페스트 완료(PR #47), A2 라이브 4/5 검증. platform-svc 5/5만 app 레포 조건부)
```

교체:
```markdown
**Status**: [ ] Not Started / [ ] In Progress / [x] Done (auto-sync·승격문서·Ingress매니페스트 완료(PR #47), A2 라이브 4/5 검증. platform-svc-staging 5/5는 #92 — gitops 층은 PR #136(서비스별 DB 분리)으로 해소, 잔여=재빌드·라이브 재검증(윈도우 2). 상세: docs/superpowers/specs/2026-06-08-w3-w4-incomplete-audit-design.md §3)
```

- [ ] **Step 2: 변경 확인**

Run: `bash -c 'grep -n "PR #136(서비스별 DB 분리)으로 해소" docs/project-management/task/TASK_gitops.md'`
Expected: 라인 152 1건 매치

- [ ] **Step 3: 커밋**

```bash
git add docs/project-management/task/TASK_gitops.md
git commit -m "docs(task): W3 Step 7 Status 정합 — #92 gitops 층 PR #136 해소·잔여 윈도우2"
```

---

### Task 2: TASK_gitops.md — W4→W5 윈도우 #92 항목 정합

**Files:**
- Modify: `docs/project-management/task/TASK_gitops.md` (#92 항목 라인 ~234)

- [ ] **Step 1: #92 항목 라인 교체**

기존(라인 234):
```markdown
- [ ] **#92 platform-svc-staging** — `application-staging.yml`이 main 미머지(dev 브랜치) 규명 → platform-svc main 머지 + `dev-latest` 재빌드 후 재검증.
```

교체:
```markdown
- [ ] **#92 platform-svc-staging** — ① datasource 부재: `application-staging.yml` **main 머지 확인**(`datasource.url: ${DB_URL}`) + gitops staging 오버레이 `DB_URL` 주입 확인(PR #136). ② flyway 충돌(W5 Day1): 서비스별 DB 분리(PR #136)로 해소. 잔여 = 머지 이후 시점 **재빌드** + 라이브 재검증(윈도우 2). 발견: staging가 dev RDS·DB 공유(§4 감사).
```

- [ ] **Step 2: 변경 확인**

Run: `bash -c 'grep -n "main 머지 확인" docs/project-management/task/TASK_gitops.md'`
Expected: 라인 234 1건 매치

- [ ] **Step 3: 커밋**

```bash
git add docs/project-management/task/TASK_gitops.md
git commit -m "docs(task): W4 윈도우 #92 항목 정합 — 이중원인(datasource/flyway)·PR #136 해소·staging DB공유 발견"
```

---

### Task 3: #92 GitHub 이슈 정합 코멘트

**Files:**
- 없음 (GitHub 이슈 코멘트만)

- [ ] **Step 1: 코멘트 본문 파일 작성**

`/tmp/issue92-comment.md`에 아래 내용 작성:

```markdown
## 정합 업데이트 (2026-06-08, W5 Day1)

W3/W4 미완료 항목 감사 중 #92를 현재 코드 상태로 재대조했습니다. platform-svc-staging은 **두 층의 독립 원인**이 얽혀 있었고, 트래커는 ①만 반영 중이었습니다.

### ① datasource 부재 (이 이슈 원래 증상)
- 증상: `Failed to configure a DataSource: 'url' attribute is not specified` (staging 프로파일)
- 규명: 윈도우 1(06-05) 당시 배포 이미지 `dev-latest`가 `application-staging.yml`이 **main 머지 전** 빌드본 → 컨테이너 내 staging datasource 설정 부재
- 현재 해소: platform-svc `main:application-staging.yml`이 `datasource.url: ${DB_URL}` 제공(확인) + gitops staging 오버레이가 `DB_URL=.../synapse_platform` 주입(확인, PR #136)

### ② flyway_schema_history 충돌 (W5 Day1 별개 발견)
- 증상: 5서비스가 단일 `synapse` DB 공유 → 타 서비스 이력 검증으로 checksum mismatch
- 해소: **PR #136** 서비스별 DB 분리(`synapse_platform` 등)

### 잔여 (윈도우 2)
- `application-staging.yml` 머지 이후 시점으로 **platform-svc 재빌드**(이미지 `imagePushedAt` > 머지 시각) + staging sync 라이브 재검증. ①·② 모두 충족 시 close.

### 신규 발견 — 환경 격리 갭
- gitops staging 오버레이 `DB_URL` 호스트 = `synapse-dev-postgres`, DB = `synapse_platform` → **dev·staging이 동일 인스턴스·동일 DB 공유**. 동일 서비스라 flyway 충돌은 없으나 환경 격리 부재·동시배포 마이그레이션 경합 리스크. 인프라 분리는 비용 결정 → 윈도우 2 / team-lead 위임.

상세: `docs/superpowers/specs/2026-06-08-w3-w4-incomplete-audit-design.md`. **OPEN 유지**(라이브 재검증은 윈도우 2 소관).
```

- [ ] **Step 2: 본문 검토 (게시 전)**

Run: `cat /tmp/issue92-comment.md`
Expected: 위 내용 그대로, 4개 소제목(①/②/잔여/신규 발견) 존재. 게시 전 사실 정합 최종 확인.

- [ ] **Step 3: 코멘트 게시**

```bash
gh issue comment 92 --body-file /tmp/issue92-comment.md
```
Expected: 코멘트 URL 출력. (이슈는 OPEN 유지 — close 명령 실행 안 함)

- [ ] **Step 4: 게시 확인**

Run: `gh issue view 92 --json state,comments --jq '{state, lastComment: .comments[-1].body[0:60]}'`
Expected: `state: OPEN`, lastComment가 "## 정합 업데이트 (2026-06-08..." 로 시작

---

### Task 4: PR 생성 + CI 확인

**Files:** 없음 (push·PR만)

- [ ] **Step 1: 산출물 일괄 확인**

```bash
grep -c "PR #136(서비스별 DB 분리)으로 해소" docs/project-management/task/TASK_gitops.md   # 1
grep -c "main 머지 확인" docs/project-management/task/TASK_gitops.md                      # 1 이상
test -f docs/superpowers/specs/2026-06-08-w3-w4-incomplete-audit-design.md && echo "spec OK"
git log --oneline main..docs/w3-w4-incomplete-audit   # 스펙 1 + TASK 편집 2 커밋
```

- [ ] **Step 2: push + PR 생성**

```bash
git push -u origin docs/w3-w4-incomplete-audit
gh pr create --base main --head docs/w3-w4-incomplete-audit \
  --title "docs(audit): W3/W4 미완료 항목 감사 + 정합 (#92 이중원인·TASK 상태)" \
  --body "..."
```

PR 본문 포함: 감사 스펙 링크, 처분 표 요약(12항목), #92 이중원인 정합, staging DB공유 신규 발견, D-043 사인오프 체크리스트 제공, 라이브 항목은 윈도우 2 위임 명시, #92 이슈는 정합 코멘트만(OPEN 유지).

- [ ] **Step 3: CI 통과 확인 후 머지**

Run: `gh pr checks --watch`
Expected: validate/parse 통과 (문서·PM만 변경)

---

## 자기 검토 메모

- 스펙 §6 정합 액션 3건 → Task 1(TASK Step 7)·Task 2(TASK #92 항목)·Task 3(#92 코멘트) 매핑 완료. §5 사인오프 체크리스트·§2 처분표·§4 신규발견은 이미 머지된 스펙 문서에 존재(추가 코드 불필요).
- #92 OPEN 유지 — Task 3에서 close 명령 없음(스펙 비범위 준수).
- 인프라 변경 없음 — staging DB 공유는 기록만(스펙 §4 처분 일치).
