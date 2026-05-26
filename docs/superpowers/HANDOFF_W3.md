# W3 핸드오프: synapse-gitops

> **최종 갱신**: 2026-05-26 (W3 1일차 — observability 라이브 검증)
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

### W3 1일차 (2026-05-26) — observability 라이브 검증

> 산출물 분리 PR: **#47** (`feat/w3-staging-observability`). staging/관측 매니페스트 + 포털 마감 + CI.

- ✅ **리포 작업 전부 완료**: staging auto-sync 전환, 공유 Ingress, 승격 절차 문서, 관측 매니페스트 9종, gitleaks 0건, 포털 정리/CI(build_docs.mjs+sibling 체크아웃)/대시보드 링크
- ✅ **observability 스택 실 EKS 검증** (SSM 터널 경유): Prometheus/Grafana/Alertmanager/Loki/Promtail 모두 Running, ServiceMonitor ×2 + PrometheusRule 3개 + 대시보드 적재, Watchdog 알람 파이프라인 firing
- ⚠️ **클러스터는 destroy 후 bare 상태** — 이번 apply는 인프라만 생성(ArgoCD helm_release는 프라이빗 엔드포인트로 실패). staging 5/5·메트릭 실수집은 W1/W2 재구축 필요
- 🐛 Loki 매니페스트 버그 2건 수정(schemaConfig, deploymentMode=SingleBinary) → PR #47

### W3 추가 (2026-05-26) — bring-up 자동화 + A2 실 EKS 1사이클

> PR **#50** (`scripts/bring-up.sh` 멱등 자동화, merged) + **#52** (A2 하드닝 6건, open).

- ✅ **bring-up.sh 11/11 phase E2E 통과**: terraform(48리소스, EBS CSI addon) → eks-auth → SG(D-026 자동) → SSM 터널 → argocd → ESO → oidc-fix(trust 자동갱신) → manifests → observability → status
- ✅ **W3 잔여 3항목 검증**: staging **4/5 Healthy**(platform-svc Degraded=cross-repo) · 메트릭 타깃 대부분 UP · Alertmanager→**slack receiver 라우팅**(실 webhook)
- 🐛 A2 발견 6건 수정(PR #52): tfvars fail-fast, eks-auth 폴링, 터널 readiness(/readyz→get nodes), ExternalSecret v1, argocd --force-conflicts, --verify curl pod
- 🔧 운영 전제 문서화: **ESO IAM 정책에 `synapse/monitoring/*` 필요**(수동 갱신함, terraform화 백로그) · **observability엔 노드 ≥4**(2노드 max-pods 초과)
- 잔여(차기): platform-svc staging 프로필(app 레포), staging Ingress 도메인/ACM TLS, ESO 정책 terraform화

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
| D-032 | EKS API 엔드포인트 프라이빗 전용(public=false) | 로컬 terraform의 helm_release.argocd 실패. kubectl/helm은 bastion SSM 포트포워딩 터널 경유 필요 (`bastion-ssm-access.md`) |
| D-033 | destroy 후 재apply한 bare 클러스터에 EBS CSI 드라이버/기본 SC 부재 (gp2는 in-tree provisioner, 1.30에서 미작동) | 동적 PVC 불가 → Loki persistence 블록. 재구축 시 aws-ebs-csi-driver 애드온 + IRSA 필요 |
| D-034 | grafana/loki 차트는 `schemaConfig` 필수 + `deploymentMode: SingleBinary` 미설정 시 loki-0 미생성 | loki-values.yaml 수정 (PR #47) |
| D-035 | ApplicationSet staging을 manual → auto sync로 전환 (PRD FR-GO-301 정합) | PR #47 |

---

## 5. 비용 관리

- 시간당 ~$0.41 (EKS + RDS + MSK + Redis + OpenSearch)
- 작업 완료 후: `cd infra/aws/dev && terraform destroy -auto-approve`
- 유지 대상: S3 state bucket (`synapse-terraform-state`) + DynamoDB lock table
