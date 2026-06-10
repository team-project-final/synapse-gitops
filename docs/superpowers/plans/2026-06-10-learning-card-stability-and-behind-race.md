# learning-card 안정화(#164) + PR BEHIND 레이스 완화(#165) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** learning-card 콜드스타트 안정화(cpu/mem request↑·startupProbe 예산↑·staging 이미지 SHA 핀) + main-protection ruleset의 strict 완화로 PR BEHIND 레이스 제거 + SHA↔semver 태깅 결정 문서 작성.

**Architecture:** 순수 gitops/문서 변경. #164=`apps/learning-card` 매니페스트(base+staging overlay). #165=`scripts/setup-branch-protection.sh` ruleset 재적용(gh api) + 결정 문서. 클러스터 destroy 상태 → 검증은 `kubectl kustomize`(오프라인 렌더) + `gh api`(ruleset) + yamllint. 라이브 기동 재검증은 다음 윈도우.

**Tech Stack:** Kustomize(kubectl 내장), GitHub Rulesets API(gh CLI), Markdown.

**Spec:** `docs/superpowers/specs/2026-06-10-learning-card-stability-and-behind-race-design.md`
**Branch:** `feat/learning-card-stability-behind-race` (스펙 커밋됨)

**확인된 사실(재조회 불필요):**
- ruleset 이름 `main-protection`(현재 id 17307721이나 스크립트·검증 모두 **name으로 조회**).
- staging 핀 대상 SHA = `ab67c3c2be0aa64611c6c22e7bf1c9d0d519c116`(라이브서 ECR pull 성공 입증된 실존 태그).
- 검증 도구: `kubectl kustomize <dir>`(클러스터 불필요), `kubeconform` 로컬 미설치→CI(validate-manifests) 위임, `yamllint -c .yamllint`.
- base deployment 현재값: requests cpu 100m/mem 256Mi, limits cpu 500m/mem 512Mi, startupProbe periodSeconds 5/failureThreshold 30.

---

### Task 1: learning-card base 리소스 + startupProbe

**Files:**
- Modify: `apps/learning-card/base/deployment.yaml`

- [ ] **Step 1: startupProbe failureThreshold 30→60**

기존:
```yaml
          startupProbe:
            tcpSocket:
              port: 8080
            periodSeconds: 5
            failureThreshold: 30   # 최대 ~150s 기동 허용(JVM 콜드스타트). 성공 후 liveness 활성
```
교체:
```yaml
          startupProbe:
            tcpSocket:
              port: 8080
            periodSeconds: 5
            failureThreshold: 60   # 최대 ~300s 기동 허용(#164: 노드 경합 콜드스타트). 성공 후 liveness 활성
```

- [ ] **Step 2: resources requests/limits 상향**

기존:
```yaml
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 512Mi
```
교체:
```yaml
          resources:
            requests:
              cpu: 250m      # #164: req 100m 스로틀로 콜드스타트가 startupProbe 초과 → 250m로 기동 CPU 확보
              memory: 384Mi
            limits:
              cpu: 500m
              memory: 768Mi  # W5 resource-sizing "512Mi tight·OOM 리스크" 반영(Spring Boot 4 + JPA)
```

- [ ] **Step 3: dev 오버레이 렌더 검증**

Run: `kubectl kustomize apps/learning-card/overlays/dev | grep -A8 "resources:" | head -12`
Expected: `cpu: 250m`, `memory: 384Mi`(requests), `memory: 768Mi`(limits) 출력.

Run: `kubectl kustomize apps/learning-card/overlays/dev | grep "failureThreshold: 60"`
Expected: 1건 매치.

- [ ] **Step 4: staging/prod 오버레이 렌더 무오류 확인**

Run: `kubectl kustomize apps/learning-card/overlays/staging >/dev/null && kubectl kustomize apps/learning-card/overlays/prod >/dev/null && echo "render OK"`
Expected: `render OK` (base 변경이 전 환경 정상 상속, prod hpa/pdb 충돌 없음).

- [ ] **Step 5: Commit**

```bash
git add apps/learning-card/base/deployment.yaml
git commit -m "fix(learning-card): #164 콜드스타트 안정화 — cpu req 250m·mem 384/768Mi·startupProbe 300s"
```

---

### Task 2: staging 이미지 SHA 핀

**Files:**
- Modify: `apps/learning-card/overlays/staging/kustomization.yaml`

- [ ] **Step 1: newTag dev-latest → SHA**

기존:
```yaml
images:
  - name: ghcr.io/team-project-final/synapse-learning-card
    newName: 963773969059.dkr.ecr.ap-northeast-2.amazonaws.com/synapse/learning-card
    newTag: dev-latest
```
교체:
```yaml
images:
  - name: ghcr.io/team-project-final/synapse-learning-card
    newName: 963773969059.dkr.ecr.ap-northeast-2.amazonaws.com/synapse/learning-card
    # #164: mutable dev-latest(dev와 다른 빌드 가능=조사 1차 가설) → 결정적 SHA 핀.
    # staging은 IU 대상 아님(image-updater namePattern=synapse-*-dev). SHA 일괄 재정렬은 #165 전략 결정 후.
    newTag: ab67c3c2be0aa64611c6c22e7bf1c9d0d519c116
```

- [ ] **Step 2: 렌더 검증**

Run: `kubectl kustomize apps/learning-card/overlays/staging | grep "image:" | grep learning-card`
Expected: `image: 963773969059.dkr.ecr.ap-northeast-2.amazonaws.com/synapse/learning-card:ab67c3c2be0aa64611c6c22e7bf1c9d0d519c116`

- [ ] **Step 3: Commit**

```bash
git add apps/learning-card/overlays/staging/kustomization.yaml
git commit -m "fix(learning-card): #164 staging 이미지 dev-latest→SHA 핀(결정성)"
```

---

### Task 3: ruleset strict 완화 (#165 BEHIND 레이스)

**Files:**
- Modify: `scripts/setup-branch-protection.sh`

- [ ] **Step 1: strict 정책 false로**

기존:
```bash
        "strict_required_status_checks_policy": true
```
교체:
```bash
        "strict_required_status_checks_policy": false
```

- [ ] **Step 2: 문법 확인**

Run: `bash -n scripts/setup-branch-protection.sh && echo "syntax OK"`
Expected: `syntax OK`

- [ ] **Step 3: ruleset 재적용(GitHub)**

Run: `bash scripts/setup-branch-protection.sh`
Expected: `Ruleset 갱신 완료 (id=...)` 출력(기존 ruleset PUT 갱신).

- [ ] **Step 4: strict=false 적용 확인**

Run:
```bash
gh api repos/team-project-final/synapse-gitops/rulesets --jq '.[] | select(.name=="main-protection") | .id' \
  | xargs -I{} gh api repos/team-project-final/synapse-gitops/rulesets/{} \
  --jq '.rules[] | select(.type=="required_status_checks") | .parameters.strict_required_status_checks_policy'
```
Expected: `false`

- [ ] **Step 5: Commit**

```bash
git add scripts/setup-branch-protection.sh
git commit -m "fix(ci): #165 ruleset strict 완화 — main 처닝 BEHIND 레이스 제거(PR 자체 CI만 요구)"
```

---

### Task 4: SHA↔semver 태깅 결정 문서

**Files:**
- Create: `docs/runbooks/image-tag-strategy-decision.md`

- [ ] **Step 1: 결정 문서 작성**

`docs/runbooks/image-tag-strategy-decision.md`:
```markdown
# 이미지 태그 전략 결정 (SHA ↔ semver) — 팀 입력물

> 작성: 2026-06-10 · 상태: **팀 결정 대기** · 관련: #165 · #157 · #126

## 문제
shared `deploy-service.yml`이 dev 오버레이에 **SHA를 write-back**(매 배포) → 두 부작용:
1. ArgoCD Image Updater `semver` 전략이 SHA를 `Invalid Semantic Version`으로 **skip**(learning-ai/card 자동업데이트 안 됨).
2. main이 매 배포마다 churn → 피처 PR이 ruleset strict로 반복 **BEHIND**(2026-06-10 PR #171 2회). → **strict 완화(#165)로 즉시 해소함**. 본 문서는 태깅 일관성(IU 자동업데이트)용 후속 결정.

## 옵션
| 옵션 | 내용 | 범위 | 트레이드오프 |
|------|------|------|-------------|
| (a) 임시 재태그 | ECR SHA→1.0.0 재태그 + overlay 정정 | gitops 1회 | 다음 배포에 회귀 → 무의미 |
| (b) deploy-service semver화 | shared 파이프라인이 릴리스시 semver 태깅 | **크로스레포**(shared, 팀) | 근본·처닝 격감, 단 조율 필요(#126류) |
| (c) IU digest 전환 | image-updater 전략 `digest`/`newest-build` + dev 오버레이 digest | **gitops 단독** | mutable 태그 추적, semver 불필요. SHA write-back과 양립 |

## 권장
**(c) IU digest** — gitops 단독 적용 가능(크로스레포 불필요), SHA write-back과 충돌 없음. BEHIND 레이스는 strict 완화로 이미 해소됐으므로 (c)는 IU 자동업데이트 일관성 목적의 선택적 후속.

## 연계 후속
- learning-card staging + 6앱 dev 오버레이 태그 일괄 재정렬은 본 결정 후.
- **staging readiness 401**(`/actuator/health/readiness` 인증 요구) = 앱 레포 시큐리티 → **synapse-learning-svc#74로 상세 핸드오프 이슈 생성 완료**(gitops에서 직접 처리 안 함).
```

- [ ] **Step 2: 검증**

Run: `test -f docs/runbooks/image-tag-strategy-decision.md && grep -c "^| (" docs/runbooks/image-tag-strategy-decision.md`
Expected: 파일 존재 + 옵션 행 3건(`3`).

- [ ] **Step 3: Commit**

```bash
git add docs/runbooks/image-tag-strategy-decision.md
git commit -m "docs(#165): SHA↔semver 태깅 전략 결정 문서(옵션 a/b/c + 권장 c)"
```

---

### Task 5: yamllint 검증 + 이슈 코멘트 + PR

**Files:** 없음(검증·게시·PR)

- [ ] **Step 1: yamllint 통과 확인**

Run: `yamllint -c .yamllint apps/learning-card/ 2>&1 | grep -i error; echo "exit=$?"`
Expected: error 라인 없음(line-length warning은 무방). yamllint 미설치 시 `kubectl kustomize apps/learning-card/overlays/dev >/dev/null && echo render-ok`로 대체.

- [ ] **Step 2: #164 조치 코멘트**

```bash
gh issue comment 164 --body "$(cat <<'EOF'
## 조치 적용 (gitops, 2026-06-10)
- base 리소스: cpu request 100m→250m(스로틀 완화), mem 256→384Mi/limit 512→768Mi.
- startupProbe failureThreshold 30→60(150s→300s).
- staging 이미지 dev-latest→SHA 핀(ab67c3c2).
잔여: staging readiness 401 → 앱 레포 핸드오프 **synapse-learning-svc#74**(상세 이슈) · 라이브 기동 재검증(다음 윈도우). spec/plan: docs/superpowers/{specs,plans}/2026-06-10-learning-card-stability-and-behind-race*.
EOF
)"
```

- [ ] **Step 3: #165 조치 코멘트**

```bash
gh issue comment 165 --body "$(cat <<'EOF'
## BEHIND 레이스 완화 (2026-06-10)
ruleset main-protection `strict_required_status_checks_policy` true→false 적용 — main 처닝(deploy-bump)과 무관하게 PR 자체 CI 통과 시 머지 가능(2026-06-10 PR #171 2회 BEHIND 실증 해소).
SHA↔semver 태깅 결정은 별도 문서 `docs/runbooks/image-tag-strategy-decision.md`(옵션 a/b/c + 권장 c=IU digest). 팀 결정 대기.
EOF
)"
```

- [ ] **Step 4: push + PR**

```bash
git push -u origin feat/learning-card-stability-behind-race
gh pr create --base main --title "fix: learning-card 안정화(#164) + PR BEHIND 레이스 완화(#165)" --body "$(cat <<'EOF'
## 요약
2026-06-10 라이브 윈도우 발견 후속(spec/plan 2026-06-10-learning-card-stability-and-behind-race).

### #164 learning-card 콜드스타트 안정화
- base: cpu req 100m→250m, mem 256→384Mi/limit 512→768Mi, startupProbe 30→60(300s).
- staging 이미지 dev-latest→SHA 핀(결정성).

### #165 PR BEHIND 레이스 완화
- ruleset strict true→false(재적용 완료). SHA↔semver 결정 문서(옵션 a/b/c, 권장 c).

## 검증(오프라인)
- [x] kubectl kustomize dev/staging/prod 렌더 + 값 확인
- [x] ruleset strict=false (gh api)
- [ ] learning-card 라이브 기동 재검증 = 다음 윈도우(#164)

범위 밖: staging readiness 401(앱 크로스레포)·태깅 구현·Grafana curl.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```
Expected: PR URL. `validate` CI 통과.

- [ ] **Step 5: CI 확인**

Run: `gh pr checks --watch --interval 15`
Expected: validate/diff-comment/parse 통과.

---

## Self-Review 결과

- **Spec coverage**: §2.1 리소스/probe→Task1 · §2.2 staging 핀→Task2 · §3.1 strict→Task3 · §3.2 결정문서→Task4 · §5 검증/코멘트→Task5. 전부 매핑.
- **Placeholder scan**: SHA·strict 값·ruleset name 조회 모두 구체. TBD/TODO 없음. 라이브 재검증 미체크는 의도(다음 윈도우, 명시).
- **이름/값 일관성**: cpu 250m·mem 384/768Mi·startupProbe 60·SHA ab67c3c2·strict false — Task·spec·코멘트·PR 본문 전부 일치. ruleset은 name(`main-protection`)으로 조회(id 하드코딩 회피).
- **검증 도구**: kubeconform 로컬 부재→`kubectl kustomize` 렌더 + CI 위임으로 대체(Task1/2/5에 반영).
