# 설계: learning-card 기동 안정화(#164) + PR BEHIND 레이스 완화(#165)

> **작성**: 2026-06-10 · **담당**: @VelkaressiaBlutkrone
> **상태**: 브레인스토밍 승인 → 플랜 대기
> **관련**: #164(learning-card Degraded 조사) · #165(semver 전략/BEHIND 레이스) · [[live-window-2026-06-10-accumulated-verify]]

---

## 0. 배경

2026-06-10 라이브 윈도우에서 두 문제가 실증됨:

1. **#164**: learning-card가 dev·staging 공통 CrashLoop. 로그상 DB·Flyway·Hibernate 정상이나 `Startup probe failed: dial tcp :8080: connect: connection refused`(dev ×76, staging ×44). 근본 = **cpu request 100m 스로틀로 JVM 콜드스타트가 startupProbe 예산(150s) 초과**. dev(replica1)는 회복, staging(replica2·`dev-latest`·노드경합)은 지속 실패.
2. **#165 BEHIND 레이스**: shared deploy 파이프라인이 learning-ai/card SHA를 main에 계속 push(매 배포) → ruleset `strict_required_status_checks_policy: true`로 피처 PR이 반복 out-of-date(PR #171이 2회 BEHIND). 머지 직전마다 `git merge origin/main` 강제.

## 1. 범위

### In Scope (오프라인 gitops)
- #164: `apps/learning-card/base/deployment.yaml` 리소스·startupProbe 조정 + staging 이미지 SHA 핀
- #165: `scripts/setup-branch-protection.sh` `strict` 완화 + 재적용 + SHA↔semver 결정 문서(팀 입력물)

### Out of Scope
- staging readiness **401**(`/actuator/health/readiness` 인증요구) — 앱 레포(`synapse-learning-svc`) 시큐리티 → 결정문서/#164 코멘트로 크로스레포 위임
- SHA↔semver 태깅 **구현**(b: deploy-service semver화 = 크로스레포 / c: IU digest = 추후 결정) — 본 스펙은 결정 문서만
- Grafana nip.io 외부 curl — 다음 라이브 윈도우
- 타 4개 Java 앱 리소스 일괄 조정 — 라이브서 probe 실패가 입증된 learning-card만(나머지는 DB 문제로 회복됨)

### 성공 기준
learning-card가 노드 경합 콜드스타트에서도 startupProbe 내 기동(스로틀 완화+예산↑) · staging이 결정적 이미지 사용 · 피처 PR이 main 처닝과 무관하게 머지 가능(strict 완화) · 팀이 태깅 전략을 결정할 문서 확보.

---

## 2. #164 learning-card 기동 안정화

### 2.1 리소스 — `apps/learning-card/base/deployment.yaml`

| 필드 | 현재 | 변경 | 이유 |
|------|------|------|------|
| `requests.cpu` | 100m | **250m** | 라이브 근본: request 100m로 노드 경합 시 ~0.1코어 스로틀 → JVM 콜드스타트가 startupProbe(150s) 초과. 250m로 기동 CPU 확보(limit 500m 유지=버스트 가능) |
| `requests.memory` | 256Mi | **384Mi** | Spring Boot 4 + JPA 힙/메타스페이스 헤드룸 |
| `limits.memory` | 512Mi | **768Mi** | W5 resource-sizing "512Mi tight·OOM 리스크" 반영. 콜드스타트 GC 압박 완화 |
| `startupProbe.failureThreshold` | 30 | **60** | 150s→300s. 경합 콜드스타트 안전망(스로틀 완화 후에도 여유) |

- `requests.cpu`/`limits.cpu`(500m)·liveness/readiness probe 경로·securityContext는 불변.
- base 변경 → dev/staging/prod 전 환경 상속. prod overlay(hpa/pdb)는 requests 기준 스케일이므로 cpu request 250m로 HPA 타깃 동작 정상.

### 2.2 staging 이미지 결정성 — `apps/learning-card/overlays/staging/kustomization.yaml`

```yaml
images:
  - name: ghcr.io/team-project-final/synapse-learning-card
    newName: 963773969059.dkr.ecr.ap-northeast-2.amazonaws.com/synapse/learning-card
    newTag: ab67c3c2be0aa64611c6c22e7bf1c9d0d519c116   # was dev-latest (mutable). dev와 동일 SHA로 결정성 확보.
```
- `dev-latest`(mutable, dev와 다른 빌드 가능 — #164 1차 가설 적중) → 명시 SHA 핀.
- staging은 IU 대상 아님(`image-updater.yaml` namePattern=`synapse-*-dev`)이라 핀이 안정적(자동 덮어쓰기 없음).
- 주석으로 "SHA는 #165 전략 결정 후 일괄 재정렬 대상" 명시.

---

## 3. #165 PR BEHIND 레이스 완화

### 3.1 ruleset strict 완화 — `scripts/setup-branch-protection.sh`

```diff
-        "strict_required_status_checks_policy": true
+        "strict_required_status_checks_policy": false
```
- 의미: PR이 main에 뒤처져도(behind) **PR 자체 커밋에서 status check 통과 시 머지 가능**. main 처닝(deploy-bump)과 무관.
- 유지: `required_status_checks`(Validate Kubernetes Manifests 필수)·`pull_request`·`deletion`·`non_fast_forward`는 그대로 → 보호 강도 유지, "최신화 강제"만 해제.
- 적용: `bash scripts/setup-branch-protection.sh`(기존 ruleset id PUT 갱신, 멱등).
- 리스크: 동시 변경 시맨틱 충돌(behind 머지)이 CI에서 안 잡힐 가능성 — 매니페스트 레포라 deploy-bump(오버레이 태그)와 피처 PR(다른 파일) 간 충돌 거의 없음. 수용.

### 3.2 SHA↔semver 결정 문서 — `docs/runbooks/image-tag-strategy-decision.md` (신규)

팀 결정 입력물(구현 아님). 내용:
- **문제**: deploy-service.yml이 dev 오버레이에 SHA write-back(매 배포) ↔ IU `semver` 전략(`Invalid Semantic Version` skip) 충돌 + main 처닝.
- **옵션**:
  - (a) 임시 ECR SHA→1.0.0 재태그 + overlay 정정 — 1회성, 다음 배포에 회귀(무의미).
  - (b) **deploy-service.yml을 semver 태깅으로** — shared 크로스레포, 릴리스시만 bump → 처닝 격감. 팀 조율(#126류).
  - (c) **IU 전략을 `digest`/`newest-build`로** — gitops 측(`image-updater.yaml` 어노테이션 + dev 오버레이 digest). mutable 태그 추적, semver 불필요.
- **권장**: (c) IU digest — gitops 단독 적용 가능(크로스레포 불필요)·SHA write-back과 양립. 단 strict 완화(§3.1)로 BEHIND 레이스는 이미 해소되므로 (c)는 IU 자동업데이트 일관성 목적의 후속.
- **연계**: §2.2 staging SHA 핀 + 6앱 dev 오버레이 태그 정렬은 이 결정 후 일괄.
- staging readiness 401(앱 시큐리티)도 본 문서에 크로스레포 후속으로 기록.

---

## 4. 컴포넌트 경계

| 단위 | 책임 | 변경 |
|------|------|------|
| `learning-card/base/deployment.yaml` | 파드 스펙(리소스·probe) | requests/limits·startupProbe |
| `learning-card/overlays/staging/kustomization.yaml` | staging 환경차 | 이미지 SHA 핀 |
| `setup-branch-protection.sh` | main ruleset 정의 | strict false |
| `image-tag-strategy-decision.md` | 팀 결정 입력물 | 신규 |

각 단위 독립 검증: kustomize build(매니페스트 2), ruleset gh api(strict 값), 문서(존재·옵션 3).

---

## 5. 검증 (오프라인, 클러스터 destroy 상태)

1. `kustomize build apps/learning-card/overlays/dev` · `.../staging` → 렌더 성공, learning-card cpu request 250m·mem 768Mi limit·startupProbe 60·staging 이미지 SHA 확인.
2. `kubeconform -strict -ignore-missing-schemas`(kustomize build 파이프) 통과.
3. `bash -n scripts/setup-branch-protection.sh` + 실제 적용 `bash scripts/setup-branch-protection.sh` → `gh api repos/team-project-final/synapse-gitops/rulesets/16480319 --jq '.rules[] | select(.type=="required_status_checks") | .parameters.strict_required_status_checks_policy'` == `false` 확인.
4. yamllint(`infra/`·`apps/` 변경분).
- **라이브 검증(learning-card 1/1 Running·기동시간)은 다음 윈도우** — #164에 "조치 적용·라이브 재검증 대기" 코멘트.

---

## 6. 작업 순서

1. base deployment 리소스/probe 조정 (kustomize build)
2. staging 이미지 SHA 핀 (kustomize build)
3. setup-branch-protection.sh strict false + 적용 + gh api 확인
4. image-tag-strategy-decision.md 작성
5. #164/#165 이슈 코멘트(조치 적용·잔여) + PR

> §2(코드)·§3.1(ruleset)·§3.2(문서)는 독립 — 원자적 커밋.
