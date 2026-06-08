# W5 Step 11 장애 Runbook + 검증 윈도우 2 — 설계

- 작성일: 2026-06-08
- 대상 리포: `synapse-gitops`
- 관련 이슈: #91, #92, #121, #122 (+ Step 11 = TASK_gitops W5)
- 선행 문서: `docs/runbooks/step11-operational-runbook.md`(작성 가이드) · `2026-06-05-w5-진입차단-클리어-design.md`(윈도우 1)
- 통보 허브: `synapse-shared#20`

## 1. 목표와 범위

**한 줄 목표:** Step 11 장애 Runbook 산출물(비용 0)을 지금 작성·머지하고, 잔존 차단 4건(#91/#92/#121/#122)과 Step 11 라이브 항목(시뮬레이션·team-lead 검증·알람 테스트)을 **단일 검증 윈도우(윈도우 2) 1회**로 클리어할 계획을 확정한다.

### 범위

| 구분 | 작업 | 시점 |
|------|------|------|
| 단계 A (비용 0) | incidents 런북 5개 + `on-call.md` + PR diff 요약 Action | 지금 작성·머지 |
| 단계 B (비용 0) | `docs/runbooks/W5_WINDOW_2.md` 윈도우 실행 런북 | 지금 작성·머지 |
| 단계 C (과금) | 윈도우 2 실행 — #91/#92/#121/#122 클리어 + Step 11 라이브 항목 | 차기 세션 (on-demand) |

> 윈도우 내부의 Phase 0~6(§4)과 구분하기 위해 작업 단계는 A/B/C로 표기한다.

### 비범위 (명시 제외)

- **#126** (main ruleset Maintain bypass / shared `deploy-service.yml` 처리) — 팀 결정 대기, 윈도우 범위 아님.
- **Step 12** (Cost 최적화 + 안정화) — 별도 사이클.
- 실 도메인 / 공인 ACM — 윈도우 1 결정대로 nip.io + self-signed ACM 유지.
- 서비스 코드 변경 — gateway/platform-svc는 선결 조건 확인만(아래 §5).

### 성공 기준

- 단계 A+B: incidents 5개·on-call·W5_WINDOW_2 런북 main 머지, CI(yamllint/validate) 통과, PR diff Action 동작 1회 확인.
- 단계 C(윈도우): #91/#92/#121/#122 전부 close + Step 11 Done When 라이브 3항목 완료 + destroy.

## 2. 결정 사항 (브레인스토밍 합의)

| 결정 | 선택 | 근거 |
|------|------|------|
| Step 11 라이브 항목 처리 | **윈도우 2에 통합** | 시뮬레이션·team-lead 검증·알람 테스트는 staging 필요. 윈도우 비용 1회로 차단 클리어와 일괄 수행 |
| 인증서 만료 런북 스택 | **실제 스택 기준** (self-signed ACM import + ArgoCD NLB) | cert-manager 미도입 결정(윈도우 1, D-047 경로)과 정합. 실행 불가능한 문서 배제 |
| On-call 체계 | **실제 팀 기준 2레벨 간소화** | 트랙 1인 + team-lead 구조. 채널 = Slack(W3 검증된 Alertmanager 경로) + GitHub(synapse-shared 허브). PagerDuty 제외 |
| PR diff 요약 Action (W1 이월, 선택) | **단계 A에 포함** | 비용 0·소규모. Step 11 Done When 선택 항목 해소 |
| 스펙 구조 | 단일 스펙·플랜 (접근 A) | 시뮬레이션이 윈도우에 통합되어 두 작업이 결합됨. 윈도우 1과 동일 패턴 |
| #91 성공 기준 재정의 | dev **7/7** · staging **7/7** | 현 ApplicationSet 기준 — dev = 5svc+gateway+frontend, staging = 5svc+frontend+schema-registry(gateway는 dev 전용). 원문 "5/5"는 frontend·schema-registry 이전 기준 |

## 3. 단계 A 산출물 — Step 11 문서 (비용 0)

### 디렉토리 구조

```
docs/runbooks/
├── incidents/
│   ├── pod-crashloop.md
│   ├── oom-killed.md
│   ├── argocd-sync-failed.md
│   ├── cert-expired.md
│   └── db-connection-failed.md
└── on-call.md
```

### 공통 골격 (incidents 5개)

각 문서: `## 증상` → `## 진단`(단계별 명령) → `## 조치` → `## 에스컬레이션 기준` → `## 회피 방법` → `## 사후 점검`.

일반론이 아닌 **이 프로젝트 실사례(`troubleshooting-infra.md` T-XXX)를 1차 진단 경로로 인용**한다. 모든 kubectl 명령에 `--context`/네임스페이스 명시.

| 런북 | 실사례 소스 | 핵심 설계 |
|------|------------|----------|
| pod-crashloop.md | T-050(D-024 mfa 테이블)·T-051(포트 불일치)·T-052(D-028 probe)·T-054/055(AES 키)·T-057/072(구 이미지) | `logs --previous` → 프로젝트 빈발 원인 체크리스트 순회(시크릿/스키마/포트/probe/이미지) |
| oom-killed.md | W4 리소스 한도 학습 | `kubectl top`+Grafana P95 → limit 상향은 **git overlay 패치 경유**(kubectl patch 금지 — GitOps 원칙 명시, 시뮬레이션 한정 예외) |
| argocd-sync-failed.md | T-020/021/022(CRD·server-side)·T-070(ns 부재) | `kustomize build` 로컬 재현 → AppProject 제약 → image-updater PR write-back 실패 케이스(#126 맥락) 포함 |
| cert-expired.md | 윈도우 1 self-signed 경로 | ① ArgoCD NLB self-signed 재발급 ② nip.io ALB: `scripts/gen-nipio-selfsigned.sh` 재실행 → ACM re-import → ingress cert ARN 갱신. **ACM import 인증서는 자동갱신 없음** → 만료 전 알람을 회피 방법에 명시 |
| db-connection-failed.md | T-040(D-026 SG)·T-030/031(ESO)·W4 db.t3.small 연결 한도 | 진단 트리: SG → RDS 엔드포인트 → 시크릿(ESO) → max_connections 순 |

### on-call.md

- **2레벨 에스컬레이션**: L1 트랙 담당(@VelkaressiaBlutkrone, 응답 5분/시도 30분) → L2 team-lead(응답 10분/해결 2시간). 서비스 전체 영향 시 L2 즉시.
- **채널**: Slack(Alertmanager 실 webhook — W3 Step 8 검증 경로) + GitHub 이슈(`synapse-shared` 통보 허브).
- **야간/주말**: critical만 즉시, warning은 다음 영업일.
- **알람 경로 테스트 절차**(amtool) 수록 — "윈도우 실행 항목" 표시.

### PR diff 요약 Action

- `.github/workflows/pr-diff-summary.yml`: PR 시 변경된 overlay 대상 `kustomize build` diff를 PR 코멘트로 게시.
- base/head 각각 빌드 → diff → 코멘트(갱신형, 중복 코멘트 방지). 변경 없는 앱은 생략.
- 기존 `validate-manifests.yml`과 분리(검증 vs 가시성).

## 4. 단계 B 산출물 — 윈도우 2 런북

`docs/runbooks/W5_WINDOW_2.md` (윈도우 1 `W5_CLEARANCE_WINDOW.md` 패턴 계승).

### 윈도우 페이즈 구성

```
Phase 0 — 선결 조건 확인 (비용 0, 윈도우 진입 전)
  ├─ gateway#4 잔여: ECR synapse/gateway 이미지 + SM synapse/dev/gateway/redis-password 시드
  ├─ platform-svc dev-latest 재빌드가 application-staging.yml(main 머지본) 포함하는지
  ├─ frontend ECR 이미지 존재 (06-07 bump 3건으로 사실상 확인)
  └─ PR #124(ALB 컨트롤러+IU ECR)·#127(PR write-back) main 반영 — ✅ 완료

Phase 1 — bring-up (과금 ON)
  └─ terraform apply → bring-up.sh
     (ArgoCD HA + ESO + ApplicationSet + alb-controller helm phase + IU ECR auth ext-script
      — PR #124 신규 경로 첫 라이브 검증)

Phase 2 — #91/#92 fleet 검증
  ├─ dev 7/7 Healthy (5svc + gateway + frontend) — verify-argocd-deploy.sh
  ├─ staging sync → 7/7 (5svc + frontend + schema-registry,
  │   platform-svc-staging 기동 = #92 해소 확인)
  └─ 롤백 1회 <3분 → #91/#92 close

Phase 3 — #121 외부 노출 완주 (ALB 의존)
  └─ ingress apply → ALB 프로비저닝 → gen-nipio-selfsigned.sh → ACM import
     → cert ARN 치환 재apply → curl --cacert 체인 유효 → ArgoCD webhook 외부 도달
     → #121 close

Phase 4 — #122 Image Updater write-back E2E (Phase 3과 상호 독립, 병행 가능)
  └─ ECR 재태그 푸시 → IU 감지 → image-updater-* 브랜치 → PR 자동 생성(#127 경로)
     → 머지 → 반영시간 측정(≤5분) → argocd rollback 1회 → #122 close

Phase 5 — Step 11 라이브 항목 (Phase 2 완료 후 가능)
  ├─ 시뮬레이션 3건 (staging): crashloop / oom / sync 실패 — incidents 런북 따라 복구
  ├─ team-lead 따라하기 1회 (런북만 보고 독립 복구)
  └─ 알람 경로 테스트 (amtool → Slack 수신)

Phase 6 — 마감
  └─ 이슈 코멘트/close + TASK/HISTORY 갱신 + synapse-shared#20 통보 + terraform destroy
```

### 설계 포인트

- **Phase 3·4 병행**: ALB 프로비저닝 대기(~3분) 동안 Phase 4 진행 → 윈도우 시간 압축.
- **#122 검증 경로 변경**: 윈도우 1 당시 direct push(bypass) 전제였으나 PR #127로 **PR write-back**으로 전환됨 — E2E 판정에 `image-updater-pr.yml`의 PR 자동 생성·머지 단계 포함.
- **team-lead 폴백**: 윈도우 당일 team-lead 불가 시 "시뮬레이션·알람만 완료, 따라하기는 비동기 후속"으로 분리 — Step 11 Done은 따라하기 완료 시점.
- **시뮬레이션 원복 보증**: 시뮬레이션 전 staging 스냅샷 → 종료 후 ArgoCD 강제 sync + diff 비교(가이드 11-C).

## 5. 선결 조건 현황 (2026-06-08 확인)

| 조건 | 상태 | 근거 |
|------|------|------|
| platform-svc `application-staging.yml` main 머지 | ✅ | gh API로 main 존재 확인 |
| platform-svc dev-latest 재빌드 | ✅(추정) | 06-05 bump 2건(bc54401·d11f743) — 윈도우 Phase 0에서 이미지 push 시각 > 머지 시각 재확인 |
| gateway ECR 이미지 | ✅(추정) | 06-05/06-07 `deploy: bump gateway` 2건 = CI 빌드·푸시 발생 |
| gateway SM redis-password 시드 | ⚠️ 미확인 | gateway#4 OPEN — 윈도우 Phase 0 체크 항목 |
| frontend ECR 이미지 | ✅(추정) | 06-07 bump 3건 |
| PR #124 / #127 main 반영 | ✅ | 머지 확인 |

## 6. 리스크와 대응

| 리스크 | 영향 | 대응 |
|--------|------|------|
| gateway SM 시크릿 미시드 | dev 7/7 미달 | Phase 0에서 확인, 미시드 시 gateway팀에 사전 요청(윈도우 전) 또는 gateway 제외 6/7로 부분 판정 + gateway#4 유지 |
| ALB 컨트롤러 첫 라이브 실패 (PR #124 미검증 경로) | #121 차단 | bring-up 로그로 IRSA/helm 단계 분리 진단 — 실패 시 윈도우 1 방식(수동 helm) 폴백, 결과를 PR로 반영 |
| IU PR write-back 미동작 (#127 미검증 경로) | #122 차단 | image-updater 로그 → 브랜치 push 여부 → workflow 트리거 여부 단계 분리. GITOPS_TOKEN 권한 사전 점검(Phase 0) |
| team-lead 윈도우 당일 불가 | Step 11 따라하기 미완 | 폴백: 비동기 후속으로 분리(§4) |
| 시뮬레이션 잔여물 (staging 오염) | 이후 검증 왜곡 | 스냅샷 + 강제 sync 원복 + diff 검증을 런북 필수 단계로 |
| 윈도우 시간 초과 | 과금 | Phase 3·4 병행, Phase 5는 staging 검증 직후 즉시 착수, 종료 시 즉시 destroy |

## 7. 산출물 요약

- **문서(단계 A):** `docs/runbooks/incidents/{pod-crashloop,oom-killed,argocd-sync-failed,cert-expired,db-connection-failed}.md`, `docs/runbooks/on-call.md`
- **코드(단계 A):** `.github/workflows/pr-diff-summary.yml`
- **문서(단계 B):** `docs/runbooks/W5_WINDOW_2.md`
- **갱신:** `TASK_gitops.md` Step 11 진행 반영, `step11-operational-runbook.md`에 결정 변경(인증서 스택·on-call 간소화) 주석
- **윈도우 실행(단계 C):** 차기 세션 — 본 스펙 범위는 계획·런북 머지까지
