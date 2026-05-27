# W3 정리·마감(Consolidation) 작업 플랜 설계

> **작성일**: 2026-05-27 (W3 Day 2 — 화)
> **기간**: 2026-05-27 ~ 2026-05-29 (남은 3 영업일)
> **트랙**: gitops
> **담당**: @VelkaressiaBlutkrone
> **관련 문서**: [PRD_W3](../../project-management/prd/PRD_W3.md) | [WORKFLOW_W3](../../project-management/workflow/WORKFLOW_gitops_W3.md) | [TASK](../../project-management/task/TASK_gitops.md) | [HANDOFF_W3](../HANDOFF_W3.md) | [W3 통합 플랜(Day1)](./2026-05-26-w3-integrated-plan-design.md)

---

## 1. 배경

W3 핵심 플랜(Step 7 staging + Step 8 Observability, PRD FR-GO-301~307)이 **Day 1(5/26)에 사실상 완료**되었다. bring-up 자동화(PR #50/#52) + A2 실 EKS 1사이클로 staging 4/5 Healthy, observability 스택 전체(Prometheus/Grafana/Loki/Alertmanager) 검증, Slack 알람 라우팅까지 마쳤고, WORKFLOW·TASK 모두 Step 7/8 Done 체크되었다. W1/W2 carry-over(W1 S3 diff 코멘트, W2 S4 트래픽, S6 image-updater)도 PR #54/#55로 흡수되었다.

즉 원래 4일치 W3 계획이 1일차에 압축 완료된 상태다. 남은 3일은 **새 기능 확장이 아니라 "정리·마감(consolidation)"** 으로 운영한다.

---

## 2. 목표와 범위

**목표:** 잔여·이월 항목을 비용 0으로 준비해 두고, 라이브 검증이 필요한 것만 주 마지막 단일 EKS 사이클에 묶어 마감한다. W4 prod/rollback 확장은 **하지 않는다**(사용자 결정).

**범위 (3트랙)**
1. **A. 잔여·이월 마감** — cross-repo platform-svc staging 프로필, staging Ingress ACM/TLS, ESO `synapse/monitoring/*` 정책 terraform화, image-updater 라이브 write-back E2E, engagement-svc 노드 ≥4 capacity
2. **B. 문서·포털 P2 마감** — docs-portal WIP 분리/머지, 포털 검색 고도화, 핸드오프 허브 통합 뷰, Grafana 링크 연동
3. **C. 로컬/레포/PM 정리** — local MSA HTML 가이드 확정 + 미추적 아티팩트 처리, local-k8s/minikube 정합화, 브랜치 프루닝 + docs-portal-v2 21커밋 분리, PM 문서 정합

**접근:** 비용 게이트 배칭(접근 1). 비용 0 작업을 Day2~Day4 오전까지 전부 끝내고, 라이브 EKS 검증 항목 전부를 Day4 오후 단일 사이클로 묶는다. 단 가장 긴 의존인 cross-repo work order만 Day2 아침으로 당겨 발행한다.

---

## 3. 핵심 결정 사항

| 항목 | 결정 | 근거 |
|---|---|---|
| 주간 성격 | 확장 아님, **정리·마감** | W3 핵심 Day1 완료. W4 당김 제외(사용자 선택) |
| 비용 모델 | **조건부 단일 EKS 사이클** (Day4 오후, 여유 시) | 비용 0 준비 우선, 라이브 검증 일괄. 미실행 시 "코드 완료, 라이브 W4" 이월 |
| cross-repo work order | **Day2 아침 즉시 발행** | 앱 레포 의존 = 가장 긴 폴, 리드타임 확보 |
| 포털 P2(검색/허브뷰) | 여유분 — 압박 시 **W4 이월** | 인프라/정리 P0 보호, 기존 P2 분류 유지 |
| 미추적 `synapse-local-setup.html` | 번들러 아티팩트 → **삭제 또는 gitignore** | 손으로 쓰는 `local-msa-setup.html`이 정본 |

---

## 4. 3일 배칭 타임라인

> 전제: 비용 0 작업을 Day2~Day4 오전까지 전부 끝내고, 라이브 EKS 검증은 Day4 오후 단일 사이클로 묶음.

### Day 2 (화 5/27) — 의존성 발행 + 잔여 코드/terraform 준비 *(비용 0)*
- **🚀 최우선(AM)**: cross-repo **platform-svc staging 프로필 work order 발행** (`cross-repo-work-order` 패턴, 앱 레포로). 가장 긴 폴 → 즉시 발행해 리드타임 확보
- **ESO 정책 terraform화**: 수동 추가했던 `synapse/monitoring/*` 권한을 `synapse-dev-eso-secrets-read` terraform 리소스로 코드화 (apply는 Day4 사이클에)
- **engagement-svc capacity**: node group `desired/min` ≥4로 terraform 수정 (W2 S4 Pending 해소용, apply는 Day4)
- **staging Ingress ACM/TLS**: ACM 인증서 terraform + `staging-{app}.<도메인>` Ingress annotations 정비 (도메인 패턴은 이미 결정됨)
- **image-updater 라이브 write-back**: dev/staging=A안(전용 봇 bypass) 설정 매니페스트/스크립트 정비 (절차 `image-updater-ecr-setup.md`)

### Day 3 (수 5/28) — 브랜치 위생 + 문서·포털 *(비용 0)*
- **브랜치/레포 위생**: 머지 완료 원격 브랜치(~24개) 프루닝, 로컬 `feat/docs-portal-v2` **21커밋 WIP 인프라 분리** — 독립 변경은 새 브랜치로 (메모리 노트 정합)
- **docs-portal 머지**: 분리된 독립 변경 머지, W3 신규 문서 반영(`build_docs.mjs`), dashboard에 **Grafana 링크 연동**
- **포털 P2 (여유분)**: 검색 고도화 + 핸드오프 허브 통합 뷰 — 시간 남을 때만, 압박 시 W4

### Day 4 (목 5/29) — 로컬 정리 + PM 정합 + (오후) 조건부 EKS
- **AM 로컬 트랙**: `local-msa-setup.html` 본문 확정(계획 9태스크) + 미추적 `synapse-local-setup.html` 처리 / local-k8s 매니페스트 + `minikube-up.sh` 검증·문서화
- **PM 정합**: HANDOFF_W3 / TASK / WORKFLOW 상태 갱신, D-0XX 마감, **잔여→W4 이월 명시**
- **🔧 PM 오후 — 조건부 EKS 1사이클** (시간/예산 남으면): `bring-up.sh` → ESO monitoring 정책 apply → engagement-svc 5/5 → staging TLS → image-updater write-back E2E 라이브 검증 → cross-repo 프로필 도착 시 platform-svc staging 5/5 확인 → **`terraform destroy`**

---

## 5. 완료 정의 (Exit 기준)

| # | 항목 | Done 검증 | 비용 |
|---|---|---|---|
| A1 | cross-repo work order 발행 | 앱 레포에 이슈/PR 등록 + git log | 0 |
| A2 | ESO `synapse/monitoring/*` terraform화 | terraform 코드에 정책 리소스, plan 클린 | 0 |
| A3 | engagement-svc capacity | node group ≥4 terraform | 0 (라이브=조건부) |
| A4 | staging Ingress ACM/TLS | ACM terraform + Ingress 매니페스트 | 0 (라이브=조건부) |
| A5 | image-updater A안 bypass | 봇 설정 매니페스트/스크립트 + 절차 문서 | 0 (E2E=조건부) |
| B1 | docs-portal 머지 | 독립 변경 분리 머지, W3 문서 반영, Grafana 링크 | 0 |
| B2 | 포털 P2 (검색/허브뷰) | **여유분** — 미달 시 W4 이월(감점 아님) | 0 |
| C1 | local MSA HTML 가이드 | 본문 완성 + 링크 + 아티팩트 처리 | 0 |
| C2 | local-k8s/minikube 정합 | 매니페스트 검증 + `minikube-up.sh` 문서 | 0 |
| C3 | 브랜치/레포 위생 | 머지 브랜치 프루닝, docs-portal-v2 21커밋 분리 | 0 |
| C4 | PM 문서 정합 | HANDOFF/TASK/WORKFLOW 갱신, D-0XX, W4 이월 명시 | 0 |
| ★ | 조건부 EKS 1사이클 | A3/A4/A5(+platform 5/5) 라이브 검증 후 destroy | ~$0.41/hr |

**주 종료 Exit 기준:** 비용 0 항목(A1·A2·A3·A4·A5 코드, B1, C1~C4) 전부 완료 + PM 문서 갱신. 조건부 EKS 사이클은 실행 시 A3/A4/A5 라이브 검증까지, 미실행 시 "코드 완료, 라이브 W4 이월"로 명시 기록.

---

## 6. 리스크 · 의존성 · 완화

| 리스크 | 영향 | 완화 |
|---|---|---|
| 🔴 cross-repo 프로필 지연 | platform-svc staging 5/5 불가 | Day2 즉시 발행, 미도착 시 "조건부 done" 기록(기존 방침 유지) |
| 🟡 docs-portal-v2 21커밋 분리 난이도 | 인프라/포털 변경 뒤엉킴 | 파일 경로 기준 cherry-pick, 인프라는 이미 main에 있는지 대조 후 폐기 |
| 🟡 조건부 EKS 사이클 미실행 | A3/A4/A5 라이브 미검증 | 코드/매니페스트는 완비 → "코드 완료, 라이브 W4" 명시 이월 (감점 아님) |
| 🟢 포털 P2 시간 부족 | 검색/허브뷰 미완 | 여유분 분류 — W4 이월 |

**전제/준비물**
- bring-up 자동화(`scripts/bring-up.sh`) = W3 Day1 검증됨 (조건부 사이클 시 재사용)
- staging 도메인 패턴 `staging-{app}.<도메인>` 결정됨 — ACM 인증서만 확보하면 적용
- Slack webhook = W3 Day1 라우팅 검증됨

---

## 7. W4 명시 이월 백로그

- Step 9 prod overlay + 승인 게이트
- Step 10 롤백 / 백업 전략
- (조건부 사이클 미실행 시) A3/A4/A5 라이브 검증
- 포털 P2 미완분 (검색 고도화 / 핸드오프 허브 통합 뷰)
