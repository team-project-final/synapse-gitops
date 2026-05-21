# W2 핸드오프: 다음 세션 이어받기 (v7)

> **최종 갱신**: 2026-05-21 (8차 세션 — 인프라 재기동 + staging overlay + 브랜치 정리)
> **현재 상태**: staging overlay 생성 완료. terraform re-apply 진행 중. 서비스 안정화 대기.
> **남은 작업**: 서비스 CrashLoop 해결 (terraform 완료 후), staging ArgoCD sync, W3 E2E 검증
> **브랜치**: main
> **담당**: @VelkaressiaBlutkrone

---

## 1. 세션별 완료 사항

### 1~5차 세션 (설계 + kind + shared 통합 + AWS 인프라)

이전 세션 내용은 v4 핸드오프 참조. 핵심: kind 검증 → Docker Compose → Avro 스키마 → terraform apply → ConfigMap endpoint.

### 6차 세션 (SSM Bastion 구성)

| 작업 | 산출물 |
|---|---|
| SSM Bastion 설계 + 구현 | `infra/aws/dev/bastion.tf`, PR #24 + #25 |
| EKS public endpoint 비활성화 | private only, bastion 경유 접근 |
| aws-auth ConfigMap 등록 | bastion role → `system:masters` |
| SSM 접속 검증 | kubectl get nodes ✅ |

### 7차 세션 (ECR push + ArgoCD 전체 배포 + 인프라 디버깅)

| 작업 | 산출물 |
|---|---|
| Developer Guide 작성 (808줄) | `docs/synapse-developer-guide.md` (PR #28) |
| Pages 사이트에 가이드 추가 | `scripts/parse-runbooks.dart` 수정 (PR #29) |
| 3개 서비스 Dockerfile 추가 | engagement/knowledge/learning-card (dev 브랜치 PR) |
| 6개 서비스 ECR push | platform/gateway/engagement/knowledge/learning-card/learning-ai (1.0.0 + dev-latest) |
| ECR 리포지토리 5개 생성 | `synapse/platform-svc`, `engagement-svc`, `knowledge-svc`, `learning-card`, `learning-ai` |
| AppProject + ApplicationSet 적용 | bastion 경유 kubectl apply |
| ESO 설치 + IRSA + ClusterSecretStore | Helm install + IRSA annotation + CSS apply |
| OIDC Provider 불일치 수정 | IAM OIDC provider 재생성 + ESO role trust policy 업데이트 |
| AWS Secrets Manager 시크릿 값 업데이트 | 8개 시크릿에 실제 RDS 비밀번호 반영 |
| ConfigMap 환경변수 매핑 수정 | DB_URL/SPRING_DATASOURCE_URL 등 앱 기대값 매핑 (PR #30) |
| RDS/Redis/MSK/OpenSearch SG 수정 | 현재 EKS 노드 SG를 각 서비스 SG ingress에 추가 |
| ArgoCD --insecure 플래그 추가 | HTTP 접근 가능 (ArgoCD UI 확인 완료) |
| ArgoCD UI 스크린샷 | `argocd-ui-applications.png` |
| Developer Guide 작성 (808줄) | `docs/synapse-developer-guide.md` (PR #28) |
| Pages 사이트에 가이드 추가 | `scripts/parse-runbooks.dart` 수정 (PR #29) |
| **Flow Simulator 새 레포** | `synapse-flow-simulator` — 18개 시나리오 인터랙티브 시뮬레이터 |
| **Flow Simulator GitHub Pages 배포** | https://team-project-final.github.io/synapse-flow-simulator/ |
| Flow Simulator 설계 스펙 | `docs/superpowers/specs/2026-05-20-flow-simulator-design.md` |
| Flow Simulator 구현 플랜 | `docs/superpowers/plans/2026-05-20-flow-simulator.md` |

### 8차 세션 (인프라 재기동 + staging overlay + 정리)

| 작업 | 산출물 |
|---|---|
| 브랜치 정리 (gitops 16개 + shared 2개) | 로컬/리모트 삭제 |
| 임시 파일 정리 | `.playwright-mcp/*.log` 8개 삭제 |
| staging overlay 생성 (5개 서비스) | `apps/*/overlays/staging/kustomization.yaml` |
| staging ApplicationSet 추가 | `argocd/applicationset-staging.yaml` (manual sync) |
| Cross-repo 작업 설계 + 플랜 | `docs/superpowers/specs/2026-05-21-cross-repo-work-order-design.md` |
| terraform re-apply | 인프라 재기동 (진행중) |
| synapse-shared 문서 현행화 | HANDOFF, ARGOCD guide, TEAM_CHECKLIST 업데이트 |

---

## 2. 현재 서비스 상태

| 서비스 | ArgoCD | Pod | 비고 |
|---|---|---|---|
| **knowledge-svc** | Synced / **Healthy** | Running / Ready | 완전 정상 |
| engagement-svc | Synced / Progressing | Running / CrashLoop | DB 연결 성공, Flyway 완료 후 크래시 — 앱 설정 확인 필요 |
| learning-card | Synced / Progressing | Running / CrashLoop | DB 연결 성공, Tomcat 기동 후 크래시 — 앱 설정 확인 필요 |
| learning-ai | Synced / Progressing | Running / CrashLoop | Uvicorn 시작됨, health check 또는 DB 문제 |
| platform-svc | Synced / Progressing | Running / CrashLoop | **DB 테이블 `mfa_credentials` 미존재** — Flyway migration 필요 |

### platform-svc 수정 방법

`application-dev.yml`의 JPA 설정에서 `ddl-auto: validate` → `update`로 변경하거나, Flyway migration 파일 추가:

```yaml
spring:
  jpa:
    hibernate:
      ddl-auto: update  # 또는 create (최초만)
```

---

## 3. 다음 세션 작업 순서

```
1. 서비스 안정화 (terraform apply 완료 후)
   ├── kubectl logs로 4개 서비스 크래시 원인 확인
   ├── platform-svc: Flyway migration 또는 ddl-auto 변경
   ├── engagement-svc/learning-card/learning-ai: 크래시 원인별 수정
   └── ECR re-push → ArgoCD Sync → 5/5 Healthy
        ↓
2. terraform state 검증
   ├── fresh apply이므로 state drift 없어야 함
   └── terraform plan → no changes 확인
        ↓
3. staging ArgoCD sync 검증
   ├── applicationset-staging.yaml apply
   ├── 수동 Sync → synapse-staging namespace 생성
   └── 5개 서비스 staging Healthy 확인
        ↓
4. W3 E2E 검증 (팀원 Kafka 구현 완료 후)
   ├── synapse-shared kafka-e2e-test.sh 실행
   ├── dev → staging 프로모션 테스트
   ├── Rollback 시나리오 테스트
   └── 비용 관리: 작업 완료 후 terraform destroy 필수
```

---

## 4. 사전 조건 체크리스트

```
[x] AWS 결제수단 verification 완료
[x] aws configure 완료
[x] terraform apply 완료
[x] SSM Session Manager Plugin 설치
[x] aws-auth ConfigMap에 bastion role 등록
[x] ArgoCD sync 후 Pod 환경변수 반영 확인
[x] ECR 이미지 push (6개 서비스 완료)
[x] OIDC Provider 수정
[x] ClusterSecretStore 정상 (store validated)
[x] ExternalSecret 동기화 (5/5 SecretSynced)
[x] SG 수정 (RDS/Redis/MSK/OpenSearch)
[x] staging overlay 생성 (5개 서비스)
[x] staging ApplicationSet 추가 (manual sync)
[ ] 서비스 안정화 (5개 중 1개 Healthy → 목표: 5/5)
[ ] terraform state 검증 (fresh apply 후 plan clean)
[ ] staging ArgoCD sync 검증
```

---

## 5. 핵심 파일 위치

### 가이드 문서

| 순서 | 문서 | 용도 |
|---|---|---|
| 0 | `docs/synapse-developer-guide.md` | **올인원 개발자 가이드 (808줄)** |
| 1 | `docs/runbooks/w2-terraform-apply-quickstart.md` | terraform apply 전체 절차 |
| 2 | `docs/runbooks/w2-eks-transition.md` | EKS provider swap 절차 |
| 3 | `docs/runbooks/argocd-ui-access.md` | ArgoCD UI 접속 |
| 4 | `docs/runbooks/bastion-ssm-access.md` | Bastion SSM 접근 절차 |

### 설계/계획 문서

| 문서 | 내용 |
|---|---|
| `docs/superpowers/specs/2026-05-20-ssm-bastion-design.md` | SSM Bastion 설계 |
| `docs/superpowers/specs/2026-05-20-developer-guide-design.md` | Developer Guide 설계 |
| `docs/superpowers/plans/2026-05-20-ssm-bastion.md` | SSM Bastion 구현 플랜 |
| `docs/superpowers/plans/2026-05-20-developer-guide.md` | Developer Guide 구현 플랜 |

---

## 6. 발견 사항 기록

| ID | 내용 | 영향 |
|---|---|---|
| D-016 | terraform state drift | OIDC, SG 수동 수정됨 → terraform import 필요 |
| D-017 | EKS private endpoint | ✅ SSM Bastion 구성 완료 |
| D-021 | OIDC Provider ID 불일치 | ✅ IAM OIDC 재생성 + ESO trust policy 업데이트로 해결 |
| D-022 | RDS/Redis/MSK/OpenSearch SG에 현재 EKS 노드 SG 미등록 | ✅ 수동으로 SG ingress 추가 |
| D-023 | ConfigMap 환경변수와 앱 기대 변수명 불일치 | ✅ DB_URL, SPRING_DATASOURCE_URL 등 추가 (PR #30) |
| D-024 | platform-svc: `mfa_credentials` 테이블 미존재 | Flyway migration 또는 ddl-auto 변경 필요 (서비스팀) |
| D-025 | AWS SM 시크릿에 placeholder 값 → 실제 RDS PW로 교체 필요 | ✅ 8개 시크릿 값 업데이트 완료 |
| D-026 | EKS managed node group은 terraform `eks_nodes` SG가 아닌 자체 `eks-cluster-sg-*` 사용 | 매 terraform apply 후 RDS/Redis/MSK/OpenSearch SG에 EKS cluster SG 수동 추가 필요. terraform 코드에 `aws_eks_cluster.main.vpc_config[0].cluster_security_group_id` 참조 추가 권장 |
| D-027 | EKS 인증 모드 CONFIG_MAP → API_AND_CONFIG_MAP 변경 | access entry로 bastion role 등록. terraform eks.tf에 `access_config` 블록 추가 권장 |
| D-028 | liveness probe initialDelaySeconds 30s 부족 | Spring Boot 4.0 + DB migration 기동 ~40-60초. PR #35에서 90s로 수정 |

---

## 7. PR 현황

### synapse-gitops

| PR | 브랜치 | 내용 | 상태 |
|---|---|---|---|
| [#24](https://github.com/team-project-final/synapse-gitops/pull/24) | `feat/w2-ssm-bastion` | SSM Bastion 구성 | Merged |
| [#25](https://github.com/team-project-final/synapse-gitops/pull/25) | `fix/bastion-ssm-agent` | SSM Agent fix | Merged |
| [#27](https://github.com/team-project-final/synapse-gitops/pull/27) | `docs/w2-ssm-bastion-complete` | 핸드오프 v4 + 설계문서 | Merged |
| [#28](https://github.com/team-project-final/synapse-gitops/pull/28) | `docs/developer-guide` | Developer Guide (808줄) | Merged |
| [#29](https://github.com/team-project-final/synapse-gitops/pull/29) | `feat/pages-developer-guide` | Pages 사이트에 가이드 추가 | Merged |
| [#30](https://github.com/team-project-final/synapse-gitops/pull/30) | `fix/configmap-db-env` | ConfigMap DB 환경변수 매핑 수정 | Merged |
| [#34](https://github.com/team-project-final/synapse-gitops/pull/34) | `feat/w2-staging-overlay` | staging overlay + ApplicationSet + KAFKA_BROKERS 갱신 | Merged |
| [#35](https://github.com/team-project-final/synapse-gitops/pull/35) | `fix/liveness-probe-delay` | liveness probe initialDelaySeconds 90s | Merged |

### 서비스 레포 (Dockerfile 추가 → dev 브랜치)

| 레포 | PR | 상태 |
|---|---|---|
| synapse-engagement-svc | [#7](https://github.com/team-project-final/synapse-engagement-svc/pull/7) | Merged → dev |
| synapse-knowledge-svc | [#16](https://github.com/team-project-final/synapse-knowledge-svc/pull/16) | Merged → dev |
| synapse-learning-svc | [#17](https://github.com/team-project-final/synapse-learning-svc/pull/17) | Merged → dev (learning-card Dockerfile) |
| synapse-learning-svc | [#18](https://github.com/team-project-final/synapse-learning-svc/pull/18) | Merged → dev (learning-ai Dockerfile fix) |

---

## 8. ECR 이미지 현황

| 서비스 | ECR 리포지토리 | 태그 |
|---|---|---|
| platform-svc | `synapse/platform-svc` | 1.0.0, dev-latest |
| gateway | `synapse-gateway` | 1.0.0, dev-latest, latest |
| engagement-svc | `synapse/engagement-svc` | 1.0.0, dev-latest |
| knowledge-svc | `synapse/knowledge-svc` | 1.0.0, dev-latest |
| learning-card | `synapse/learning-card` | 1.0.0, dev-latest |
| learning-ai | `synapse/learning-ai` | 1.0.0, dev-latest |

---

## 9. Bastion 접속 정보

| 항목 | 값 |
|---|---|
| **Instance ID** | terraform apply마다 변경됨. `terraform output bastion_instance_id`로 확인 |
| **도구** | kubectl v1.36.1, helm v3.21.0 |
| **EKS 인증** | aws-auth `system:masters` |

```powershell
# 접속
$env:PATH += ";C:\Program Files\Amazon\SessionManagerPlugin\bin"
aws ssm start-session --target i-08399527c6f112cee --region ap-northeast-2

# ArgoCD UI (SSM 포트 포워딩)
aws ssm start-session --target i-08399527c6f112cee --region ap-northeast-2 --document-name AWS-StartPortForwardingSessionToRemoteHost --parameters '{"host":["localhost"],"portNumber":["8080"],"localPortNumber":["9090"]}'
# → http://localhost:9090 (admin / N9nWOZZt25NXzXJr)
```

---

## 10. 비용 관리

- terraform apply 후 시간당 ~$0.41 발생
- 작업 완료 후 반드시: `cd infra/aws/dev && terraform destroy -auto-approve`
- S3 state bucket + DynamoDB lock table은 유지
