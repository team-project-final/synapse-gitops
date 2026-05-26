# W3 통합 작업 플랜 설계

> **작성일**: 2026-05-26
> **기간**: 2026-05-26 ~ 2026-05-29 (4 영업일, 5/25 부처님오신날 제외)
> **트랙**: gitops
> **담당**: @VelkaressiaBlutkrone
> **관련 문서**: [PRD_W3](../../project-management/prd/PRD_W3.md) | [WORKFLOW_W3](../../project-management/workflow/WORKFLOW_gitops_W3.md) | [TASK](../../project-management/task/TASK_gitops.md) | [HANDOFF_W3](../HANDOFF_W3.md) | [W3 Runbook](../../runbooks/w3-staging-observability-runbook.md)

---

## 1. 목표와 범위

3주차를 **통합 플랜**으로 진행한다. 코어 인프라 작업(PRD W3)을 크리티컬 패스로 보호하면서, W2 이월 항목과 docs-portal 마무리를 위험이 낮은 슬롯에 끼워넣는다.

**범위 (3트랙)**
1. **코어 W3** — Step 7 staging 환경 마무리 + Step 8 Observability 스택 (PRD FR-GO-301~307)
2. **W2 이월** — gitleaks 평문 시크릿 0건 검증, 이미지 자동 sync E2E 1건 확인
3. **docs-portal** — 정리/머지, W3 신규 문서 반영, Pages CI 검증/확장, dashboard에 Grafana 링크 연동

**접근**: 인프라 크리티컬 패스 우선(접근 A). 포털 기능 개선 중 "대시보드 강화"만 observability 산출물에 얹어 처리하고, "검색 고도화"·"핸드오프 허브 통합 뷰"는 P2로 명시 연기한다.

---

## 2. 핵심 결정 사항

| 항목 | 결정 | 근거 |
|---|---|---|
| staging sync 정책 | **자동 sync** | PRD FR-GO-301 원안. 표준 GitOps(staging은 main 미러링, manual gate는 prod=W4). 현재 PR #34의 manual sync를 auto로 전환 |
| 로그 백엔드 (FR-GO-305) | **Loki + Promtail** | 설치 예정인 Grafana와 통합 — 단일 Explore 창에서 메트릭+로그. self-hosted, 비용↓ |
| 알람 채널 (FR-GO-306) | **Slack** | #synapse-gitops 채널 이미 runbook에서 참조. webhook 설정 간단 |
| 포털 기능 우선순위 | 대시보드 강화만 이번 주, 검색/허브통합은 P2 | 4일 통합 범위에서 인프라 P0 보호. 대시보드는 observability에 얹어 처리 |

---

## 3. 4일 타임라인 (크리티컬 패스)

> 전제: 클러스터는 `terraform destroy` 상태 가정 → Day1 오전은 기동부터 시작.

### Day 1 (월 5/26) — 기동 + W2 이월 마감 + staging 분석
- **AM 클러스터 기동**: `w2-session-bootstrap-runbook` 12단계 + `terraform apply`(dev) + SG 수동작업(D-026: EKS cluster SG → RDS/Redis/MSK/OpenSearch SG 인바운드) → `argocd app list` 5/5 Healthy 확인
- **W2 이월 흡수**: gitleaks 스캔(평문 시크릿 0건), 이미지 자동 sync E2E 1건 확인
- **PM**: Step 7-A 사전분석 + 7-B staging overlay 점검 (이미 작성됨 — replicas=2 / 리소스 상향값 / staging ExternalSecret 경로 `synapse/staging/{app}/*` 검증)

### Day 2 (화 5/27) — staging 마무리 (Step 7 완료)
- **7-C**: `argocd/applicationset-staging.yaml` **manual → auto sync 전환**, generator matrix dev+staging
- **staging 전용 도메인 + Ingress + TLS** (`staging-{app}.<domain>`)
- **7-D**: dev→staging 승격 시뮬레이션 1회 (PR merge → staging 자동 반영, 5분 이내 확인)
- **7-E**: 승격 절차 README 작성
- **🎯 검증**: 10개 Application(5앱 × dev+staging) Synced+Healthy, staging 도메인 헬스체크

### Day 3 (수 5/28) — 메트릭 스택 (Step 8 전반)
- **8-A**: 사전분석 (보존기간 등)
- **8-B**: kube-prometheus-stack Helm 설치(Prometheus+Grafana+Alertmanager), Grafana admin → ExternalSecret, 외부노출+TLS
- **8-C**: 5개 앱 ServiceMonitor 정의(`/actuator/prometheus`, learning-ai는 `/metrics`) → Prometheus targets UP 확인
- **🔧 끼워넣기 (포털 정리)**: playwright 콘솔 로그 삭제 확정, `.gitignore`에 `site/scripts/node_modules`·`.summary-cache.json` 추가, `site/README.md` 교체

### Day 4 (목 5/29) — 로그+대시보드+알람 (Step 8 완료) + 포털 마감
- **8-D**: Loki+Promtail DaemonSet 설치 → 5앱 로그 Grafana Explore 조회
- **8-E**: Grafana "Synapse 개요" 대시보드(5앱 상태/트래픽/5xx) + platform-svc 상세 1개
- **8-F**: PrometheusRule 3개(Pod 다운 5분 / 메모리 90% 10분 / 5xx 비율 5% 5분) + Alertmanager → Slack 라우팅 + 알람 1건 의도 발생 → Slack 도달 확인
- **🔧 끼워넣기 (포털 마감)**: W3 신규 문서 반영 빌드(`build_docs.mjs`), Pages CI 검증/확장, dashboard에 Grafana 링크 연동
- **📋 마감**: HANDOFF_W3 완료 항목 갱신 + D-0XX 추가, TASK_gitops Step 7/8 Done 체크, `terraform destroy`

---

## 4. 리스크 · 의존성 · 완화

| 리스크 | 영향 | 완화 |
|---|---|---|
| 🔴 platform-svc staging 프로필 부재 | staging 5/5 불가 (4/5에서 막힘) — 앱 레포 의존 | Day1에 앱 트랙으로 staging Spring profile 요청 cross-repo work-order 발행. 미해결 시 platform-svc staging은 **"조건부 done"**으로 기록 |
| 🟡 클러스터 기동 시간 / SG 수동작업(D-026) | apply ~수십분, SG 누락 시 앱 DB/Kafka 연결 실패 | 기동 런북 12단계 준수, SG 인바운드 추가를 체크리스트 필수 항목화 |
| 🟡 4일 통합 범위 압박 | 포털 기능이 첫 컷 대상 | 포털 기능 개선(검색/허브)을 P2로 사전 분리, 인프라 P0 보호 |
| 🟢 Loki 노드 용량 | Promtail/Loki Pending | resource request 보수적 설정, 필요 시 노드그룹 scaling |
| 🟢 비용 ~$0.41/hr | 누적 비용 | 작업 종료 시 `terraform destroy`, S3 state·DynamoDB lock만 유지 |

**전제/준비물**
- ArgoCD / ESO / Image Updater = W2에서 동작 확인됨 (기동 후 재검증)
- Slack webhook URL 확보 (Alertmanager 라우팅용) — Day4 전 준비

---

## 5. 이번 주 P2 명시 연기 (W4 백로그)

- 포털 **검색 고도화** (전문검색 / 태그 필터 / AI 요약 품질 개선)
- 포털 **핸드오프 허브 통합 뷰** (handoff_hub / handoff_shared / W3 렌더링, 세션 기동 흐름 가시화)
- → 인프라 P0 완료 후 여유 시 당김. 압박 시 W4로 이월.
- *포털 "대시보드 강화"는 Day4 observability에 얹어 처리하므로 연기 대상 아님 (Grafana 링크 연동 수준).*

---

## 6. 완료 정의 (PRD W3 매핑)

| 요구사항 | 우선순위 | Done 검증 | 단계 |
|---|---|---|---|
| FR-GO-301 staging auto sync | P0 | staging 5개 Application Synced+Healthy (auto) | Day2 |
| FR-GO-302 승격 절차 문서+1회 실행 | P0 | README 절차 + git log 실행 이력 | Day2 |
| FR-GO-303 kube-prometheus-stack | P0 | Prometheus+Grafana+Alertmanager Running | Day3 |
| FR-GO-304 5앱 ServiceMonitor | P0 | Grafana Explore에서 5앱 메트릭 조회 | Day3 |
| FR-GO-305 로그 스택(Loki) | P1 | 5앱 로그 Grafana Explore 조회 | Day4 |
| FR-GO-306 알람 3개+채널 도달 | P0 | Pod다운/메모리/5xx 알람 Slack 도달 | Day4 |
| FR-GO-307 Synapse 개요 대시보드 | P1 | 5앱 상태+트래픽+에러율 한 화면 | Day4 |

**통합 범위 추가 산출물 (PRD 외)**
- W2 이월: gitleaks 평문 0건, 이미지 자동 sync E2E (Day1)
- docs-portal: 정리+머지, W3 문서 반영, Pages CI 검증/확장, dashboard Grafana 링크 (Day3-4)

**주 종료 Exit 기준**: P0 7건 중 staging(조건부 platform-svc 제외)·observability·알람 모두 통과 + 핸드오프 문서 갱신 + `terraform destroy` 실행.
