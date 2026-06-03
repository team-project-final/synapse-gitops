# Spring graceful shutdown Implementation Plan (B3)

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`).
> **⚠️ svc 레포 게이트:** 본 plan은 svc 앱 레포 5개를 편집/PR한다. [[svc-repo-changes-need-confirmation]] 규칙대로 각 레포 편집·푸시·PR 직전에 사용자 확인 필수.

**Goal:** 5개 Spring Boot 서비스에 앱 레벨 graceful shutdown을 추가해 #98의 무중단 배포를 완성한다.

**Architecture:** 각 svc 레포 `src/main/resources/application.yml`에 `server.shutdown: graceful` + `spring.lifecycle.timeout-per-shutdown-phase` 추가. 코드 변경 없음(설정 2줄+α). svc 레포당 1 PR = 5 PR.

**Tech Stack:** Spring Boot(graceful shutdown 내장), YAML.

**환경:** 형제 레포 루트 `D:/workspace/final-project-syn`(SIB). 대상 레포: synapse-gateway, synapse-platform-svc, synapse-engagement-svc, synapse-knowledge-svc, synapse-learning-svc(learning-card 컴포넌트).

**현황(확인됨):** 5개 모두 `server:`(port)·`spring:` 블록은 있으나 `server.shutdown`·`spring.lifecycle` 없음. 파일 내 블록 순서: gateway/platform = server→spring, engagement/knowledge/learning-card = spring→server.

**타임버짓:** preStop(대부분 5s, gateway 10s) + graceful drain < terminationGracePeriodSeconds(40s).
→ 일반 서비스 `timeout-per-shutdown-phase: 30s`, **gateway는 20s**(preStop 10s 고려).

**머지 순서 무관:** 앱 레벨 설정이라 k8s(#98)·이미지와 독립. 단 효과 검증엔 이미지 재배포 필요.

---

## 공통 편집 패턴

`application.yml`의 기존 `server:` 블록에 `shutdown: graceful` 추가:
```yaml
server:
  port: <기존>
  shutdown: graceful
```
기존 `spring:` 블록(최상위)에 `lifecycle` 추가(들여쓰기 2칸, spring 하위):
```yaml
spring:
  lifecycle:
    timeout-per-shutdown-phase: 30s   # gateway는 20s
  # ...기존 spring 하위 키 유지...
```
(YAML이라 `spring.lifecycle`을 spring 블록 어디에 넣어도 무방. 기존 키 보존.)

---

## Task 1: synapse-gateway (timeout 20s)
**확인 게이트:** 편집 전 사용자 승인.
**Files:** `D:/workspace/final-project-syn/synapse-gateway/src/main/resources/application.yml` (server: 1-2행, spring: 4행~)

- [ ] **Step 1: 브랜치** — `cd D:/workspace/final-project-syn/synapse-gateway && git checkout main && git pull --ff-only && git checkout -b feat/graceful-shutdown`
- [ ] **Step 2: server에 shutdown 추가** — `server:` 블록(port 8080) 아래에 `  shutdown: graceful` 추가.
- [ ] **Step 3: spring에 lifecycle 추가** — `spring:` 블록 바로 아래에:
```yaml
  lifecycle:
    timeout-per-shutdown-phase: 20s
```
(gateway는 preStop 10s라 20s. 기존 spring 하위 키 보존.)
- [ ] **Step 4: 빌드 확인** — `./gradlew build --no-daemon` (또는 PR CI). YAML 유효성 + 컴파일 통과.
- [ ] **Step 5: 커밋/푸시/PR(승인 후)** —
```bash
git add src/main/resources/application.yml
git commit -m "feat: graceful shutdown 활성화 (server.shutdown + lifecycle timeout 20s)"
git push -u origin feat/graceful-shutdown
gh pr create --base main --head feat/graceful-shutdown --title "feat: graceful shutdown 활성화" --body "무중단 배포 완성(B3). server.shutdown: graceful + spring.lifecycle.timeout-per-shutdown-phase 20s(gateway preStop 10s 고려). k8s preStop+grace(#98)와 정합.

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

## Task 2: synapse-platform-svc (timeout 30s)
**확인 게이트:** 편집 전 승인.
**Files:** `D:/workspace/final-project-syn/synapse-platform-svc/src/main/resources/application.yml` (server: 1-2행, spring: 5행~)

- [ ] **Step 1: 브랜치** — `cd .../synapse-platform-svc && git checkout main && git pull --ff-only && git checkout -b feat/graceful-shutdown`
- [ ] **Step 2:** `server:`(port 8081)에 `  shutdown: graceful` 추가.
- [ ] **Step 3:** `spring:` 아래에:
```yaml
  lifecycle:
    timeout-per-shutdown-phase: 30s
```
- [ ] **Step 4: 빌드** — `./gradlew build --no-daemon`.
- [ ] **Step 5: 커밋/푸시/PR(승인 후)** — 커밋 메시지 `feat: graceful shutdown 활성화 (server.shutdown + lifecycle timeout 30s)`, PR 본문 동일 취지.

## Task 3: synapse-engagement-svc (timeout 30s)
**확인 게이트:** 편집 전 승인.
**Files:** `D:/workspace/final-project-syn/synapse-engagement-svc/src/main/resources/application.yml` (spring: 1행~, server: 32-33행)

- [ ] **Step 1:** 브랜치 `feat/graceful-shutdown`. (engagement 레포는 merge commit 금지 — PR 머지 시 squash/rebase.)
- [ ] **Step 2:** `server:`(port 8083)에 `  shutdown: graceful` 추가.
- [ ] **Step 3:** `spring:`(1행) 아래에 `  lifecycle:\n    timeout-per-shutdown-phase: 30s` 추가(기존 spring 하위 flyway/kafka 등 보존).
- [ ] **Step 4: 빌드** — `./gradlew build --no-daemon`.
- [ ] **Step 5: 커밋/푸시/PR(승인 후)** — 메시지 동일 취지(30s).

## Task 4: synapse-knowledge-svc (timeout 30s)
**확인 게이트:** 편집 전 승인.
**Files:** `D:/workspace/final-project-syn/synapse-knowledge-svc/src/main/resources/application.yml` (spring: 1행~, server: 34-35행)

- [ ] **Step 1:** 브랜치 `feat/graceful-shutdown`.
- [ ] **Step 2:** `server:`(port 8082)에 `  shutdown: graceful`.
- [ ] **Step 3:** `spring:` 아래 `lifecycle.timeout-per-shutdown-phase: 30s`.
- [ ] **Step 4: 빌드** — `./gradlew build --no-daemon`.
- [ ] **Step 5: 커밋/푸시/PR(승인 후)** — 30s.

## Task 5: synapse-learning-svc / learning-card (timeout 30s)
**확인 게이트:** 편집 전 승인. (learning-svc 레포엔 learning-ai CLAUDE.md 규칙이 있으나 learning-card 컴포넌트에는 별도 규칙 없음 — 일반 절차.)
**Files:** `D:/workspace/final-project-syn/synapse-learning-svc/learning-card/src/main/resources/application.yml` (spring: 1행~, server: 35-36행)

- [ ] **Step 1:** 브랜치 `feat/graceful-shutdown-learning-card`(레포에 learning-ai 등 공존 가능 → 명확한 브랜치명).
- [ ] **Step 2:** `server:`(port 8084)에 `  shutdown: graceful`.
- [ ] **Step 3:** `spring:` 아래 `lifecycle.timeout-per-shutdown-phase: 30s`.
- [ ] **Step 4: 빌드** — learning-card 빌드(`./gradlew :learning-card:build` 또는 해당 디렉토리 빌드 방식 확인).
- [ ] **Step 5: 커밋/푸시/PR(승인 후)** — `learning-card/src/main/resources/application.yml`만 add. 30s.

---

## Task 6: (선택) minikube 무중단 검증
**확인 게이트:** 이미지 재빌드/재배포는 로컬 — svc 레포 푸시와 무관하나 5개 이미지 재빌드 필요.

- [ ] 5개 svc 이미지 재빌드 → `minikube image load`(동일 :local 태그면 [[minikube-image-load-stale]] 절차: scale0→rm→load→scaleup) → 재배포.
- [ ] 부하 중 롤링 재시작/파드 삭제 시 200 유지(#98의 무중단 테스트 절차 재사용).
- [ ] 미수행 시: 효과 검증은 EKS(태스크 A)로 이연.

---

## Self-Review
- 대상 5개 Spring 전부 Task 1-5 매핑 ✓. learning-ai 제외(Python, 비대상) 명시 ✓.
- 각 Task에 svc 레포 확인 게이트 명시 ✓([[svc-repo-changes-need-confirmation]]).
- gateway timeout 20s(preStop 10s), 나머지 30s — 타임버짓 정합 ✓.
- 파일별 현재 행 위치(server/spring 순서) 반영 ✓. 기존 키 보존 지시 ✓.
- 플레이스홀더 없음(편집 내용 구체 YAML 제공).
