# KICKOFF: synapse-gitops

> **트랙**: gitops
> **담당**: @VelkaressiaBlutkrone
> **GitHub Repository**: [synapse-gitops](https://github.com/team-project-final/synapse-gitops)
> **기간**: 2026-05-12 ~ 2026-06-12 (W1 ~ W5)

---

## 1. 트랙 미션

`synapse-gitops` 레포에서 Synapse 백엔드 5개 앱(platform-svc, engagement-svc, knowledge-svc, learning-card, learning-ai)을 ArgoCD ApplicationSet + Kustomize 기반 GitOps로 dev/staging/prod 3개 환경에 안정적으로 배포한다.

5주차 종료 시점에 다음이 모두 충족되어야 한다:

- 모든 앱이 ArgoCD 자동 sync로 dev/staging/prod에 배포됨
- Secret이 안전하게 관리됨 (평문 노출 0)
- 이미지 태그 변경이 git 푸시 한 번으로 환경에 반영됨
- 롤백 절차가 문서화되고 1회 이상 실제 검증됨
- 운영 Runbook이 존재하여 장애 발생 시 따라할 수 있음

## 2. 주차별 큰 그림

| 주차 | 기간 | 영업일 | 핵심 목표 |
|---|---|---|---|
| W1 | 2026-05-12 ~ 05-16 | 5 | ArgoCD 부트스트랩 + ApplicationSet 골격 + CI 검증 정착 |
| W2 | 2026-05-19 ~ 05-23 | 5 | dev 환경 5개 앱 자동 배포 + Secret 관리 + 이미지 sync |
| W3 | 2026-05-26 ~ 05-29 | 4 (5/25 부처님오신날 제외) | staging 환경 + Observability(Prometheus/Grafana) |
| W4 | 2026-06-01 ~ 06-05 | 4 (6/3 지방선거 제외) | prod 환경 + 승인 게이트 + 롤백/백업 전략 |
| W5 | 2026-06-08 ~ 06-12 | 5 | Runbook + 장애 시나리오 검증 + Cost/안정화 |

## 3. 현재 상태 (W1 기준)

- ✅ `apps/`, `argocd/`, `infra/` 디렉토리 골격 존재
- ✅ `validate-manifests.yml` (kustomize lint + build) CI 동작
- ✅ docker-compose 로컬 개발 환경 (W0 단계)
- ⏳ ArgoCD 실제 설치 — W1 Step 1
- ⏳ ApplicationSet 정의 — W1 Step 2

## 4. 외부 의존성

- **synapse-platform-svc / engagement-svc / knowledge-svc / learning-svc / frontend / shared**: 이미지 빌드 산출물의 태그 규칙(`{branch}-{sha}` 또는 `vX.Y.Z`)이 안정적으로 정해져야 함
- **AWS 인프라**: EKS 클러스터, IAM Role, Route53, ACM 인증서, S3 (Velero 백업용)
- **외부 시크릿 저장소**: AWS Secrets Manager 또는 SOPS + KMS

## 5. 리스크

| 리스크 | 영향 | 완화 |
|---|---|---|
| 5개 앱의 이미지 태깅 규칙이 제각각 | dev 환경 자동 sync 실패 | W2 Step 6에서 통일 규칙 합의 + 문서화 |
| Secret 누출 사고 | 보안 사고 | W2 Step 5에서 External Secrets 도입, git 평문 금지 정책 |
| ArgoCD 자체 장애 | 모든 환경 배포 중단 | W4 Step 9 ArgoCD HA 구성 + Backup |
| prod 잘못 배포로 인한 데이터 사고 | 비즈니스 영향 | W4 Step 9 승인 게이트(Manual Sync), W4 Step 10 롤백 절차 사전 검증 |

## 6. 관련 문서

- [TASK_gitops.md](./task/TASK_gitops.md) — Step 단위 상세 정의
- [SCOPE_gitops.md](./scope/SCOPE_gitops.md) — In/Out of Scope
- [PRD_W1.md ~ W5.md](./prd/) — 주차별 요구사항(FR-GO-*)
- [HISTORY_gitops.md](./history/HISTORY_gitops.md) — 진행 이력
- [synapse-gitops/README.md](../../README.md) — 레포 사용법
