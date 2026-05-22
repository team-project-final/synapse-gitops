# W3 핸드오프: synapse-gitops

> **최종 갱신**: 2026-05-22 (W2 → W3 전환)
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
| — | (W3 시작 전, 추가 발견 없음) | — |

---

## 5. 비용 관리

- 시간당 ~$0.41 (EKS + RDS + MSK + Redis + OpenSearch)
- 작업 완료 후: `cd infra/aws/dev && terraform destroy -auto-approve`
- 유지 대상: S3 state bucket (`synapse-terraform-state`) + DynamoDB lock table
