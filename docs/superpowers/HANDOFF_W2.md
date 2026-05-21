# W2 핸드오프: 다음 세션 이어받기 (v8)

> **최종 갱신**: 2026-05-21 (9차 세션 완료 — **5/5 Healthy** 달성)
> **현재 상태**: **5/5 서비스 Healthy**. 전체 dev 환경 정상 운영 중.
> **남은 작업**: staging sync 검증, MSK 토픽 생성, W3 E2E 검증
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
| terraform re-apply + destroy | 인프라 재기동 → 서비스 디버깅 → destroy 완료 |
| synapse-shared 문서 현행화 | HANDOFF, ARGOCD guide, TEAM_CHECKLIST 업데이트 |
| EKS 인증 모드 변경 | CONFIG_MAP → API_AND_CONFIG_MAP + bastion access entry (D-027) |
| 인프라 SG 수정 | EKS cluster SG를 RDS/Redis/MSK/OpenSearch SG에 추가 (D-026) |
| liveness probe 수정 | initialDelaySeconds 30s → 90s/60s (PR #35) |
| KAFKA_BROKERS 갱신 | MSK 재생성으로 endpoint 변경 (PR #34) |
| **platform-svc fix** | `ddl-auto: update` 추가 ([platform-svc PR #26](https://github.com/team-project-final/synapse-platform-svc/pull/26) → dev 머지) |
| **learning-ai fix** | 포트 8000 → 8090 통일 (gitops [PR #38](https://github.com/team-project-final/synapse-gitops/pull/38) → main 머지) |
| TASK/WORKFLOW 문서 갱신 | W2 Step 4~7 진행 상태 업데이트 (PR #37) |

### 9차 세션 (5/5 Healthy 달성 + 세션 기동 자동화 문서)

| 작업 | 산출물 |
|---|---|
| terraform apply (46 리소스 프로비저닝) | 인프라 전체 재기동 |
| EKS 인증 모드 + bastion access entry | API_AND_CONFIG_MAP + ClusterAdmin policy |
| SG 수정 (D-026) | EKS cluster SG → RDS/Redis/MSK/OpenSearch 4개 SG 인바운드 추가 |
| ArgoCD 설치 (`--server-side`) | CRD 크기 제한 해결 (T-020) |
| ESO 설치 + OIDC trust policy 갱신 | IRSA annotation + OIDC ID 불일치 해결 (D-021 반복) |
| ClusterSecretStore + AppProject + ApplicationSet | `curl \| kubectl apply` 패턴 (Bastion에 git 없음) |
| **platform-svc 환경변수 14개 추가** | ExternalSecret 11개 시크릿 + ConfigMap 3개 (PR #40) |
| **platform-svc ECR re-push** (2회) | ddl-auto fix + Flyway V28 migration 포함 |
| **Flyway V28 migration 추가** | `provider_id` → `provider_user_id` 컬럼명 수정 (D-029) |
| **AES 키 포맷 수정** | hex 16B → Base64 32B (FieldEncryptor 요구사항, D-030) |
| AWS SM 시크릿 11개 생성 | JWT RSA 키페어, AES 키, Stripe/OAuth2 placeholder |
| **5/5 Healthy 달성** | dev 환경 전체 서비스 정상 |
| **staging 4/5 Healthy** | staging sync 완료 (platform-svc는 staging 프로필 수정 필요) |
| **MSK 토픽 5개 생성** | kafka-client Pod 경유, replication-factor=2 |
| **KAFKA_BROKERS 갱신** (PR #42) | MSK 재생성으로 브로커 주소 변경 (ejn12p → dchj3l) |
| 세션 기동 runbook 작성 | `docs/runbooks/w2-session-bootstrap-runbook.md` (12단계) |
| 인프라 트러블슈팅 가이드 작성 | `docs/runbooks/troubleshooting-infra.md` (22개 문제/해결) |

---

## 2. 현재 서비스 상태

| 서비스 | ArgoCD | Pod | 비고 |
|---|---|---|---|
| **knowledge-svc** | Synced / **Healthy** | Running / Ready | 완전 정상 |
| **engagement-svc** | Synced / **Healthy** | Running / Ready | SG 수정 후 정상 |
| **learning-card** | Synced / **Healthy** | Running / Ready | SG + probe delay 후 정상 |
| **learning-ai** | Synced / **Healthy** | Running / Ready | ✅ 포트 8090 통일 (PR #38) → 9차 세션에서 자동 해결 확인 |
| **platform-svc** | Synced / **Healthy** | Running / Ready | ✅ 9차 세션에서 해결 (환경변수 14개 추가 + Flyway V28 + AES 키 수정) |

---

## 3. 다음 세션 작업 순서

```
1. terraform apply + 기본 설정 (매 세션 반복)
   └── 상세 절차: docs/runbooks/w2-session-bootstrap-runbook.md (10단계)
   └── 트러블슈팅: docs/runbooks/troubleshooting-infra.md (16개 항목)
        ↓
2. ✅ 5/5 Healthy 달성 (9차 세션 완료)
        ↓
3. staging sync (다음 세션)
   ├── argocd app sync synapse-*-staging (5개)
   └── synapse-staging namespace 5/5 Healthy
        ↓
4. MSK 토픽 생성 (선행 가능)
   ├── scripts/create-kafka-topics.sh 실행 (Bastion에서)
   ├── Schema Registry 등록
   └── docs/guides/MSK_TOPIC_SETUP.md 참조
        ↓
5. W3 E2E 검증 (팀원 Kafka 구현 완료 후)
   ├── kafka-e2e-test.sh --all 실행
   ├── dev → staging 프로모션 테스트
   └── 비용 관리: terraform destroy 필수
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
[x] 서비스 안정화 — **5/5 Healthy 달성** (9차 세션)
[x] platform-svc 환경변수 14개 추가 (PR #40)
[x] platform-svc Flyway V28 migration (provider_id → provider_user_id)
[x] AWS SM 시크릿 11개 생성 (JWT RSA, AES, Stripe, OAuth2)
[x] 세션 기동 runbook + 트러블슈팅 가이드 작성
[x] staging ArgoCD sync — 4/5 Healthy (platform-svc staging 프로필 미존재)
[x] MSK 토픽 5개 생성 (kafka-client Pod 경유)
[x] KAFKA_BROKERS 주소 갱신 (PR #42)
[ ] staging platform-svc: application-staging.yml 추가 필요
[ ] W3 E2E 검증 (팀원 Kafka 구현 완료 후)
```

---

## 5. 핵심 파일 위치

### 가이드 문서

| 순서 | 문서 | 용도 |
|---|---|---|
| 0 | `docs/synapse-developer-guide.md` | **올인원 개발자 가이드 (808줄)** |
| 1 | `docs/runbooks/w2-session-bootstrap-runbook.md` | **매 세션 인프라 기동 10단계 절차** |
| 2 | `docs/runbooks/troubleshooting-infra.md` | **인프라 트러블슈팅 가이드 (16개 항목)** |
| 3 | `docs/runbooks/w2-terraform-apply-quickstart.md` | terraform apply 전체 절차 |
| 4 | `docs/runbooks/w2-eks-transition.md` | EKS provider swap 절차 |
| 5 | `docs/runbooks/argocd-ui-access.md` | ArgoCD UI 접속 |
| 6 | `docs/runbooks/bastion-ssm-access.md` | Bastion SSM 접근 절차 |

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
| D-024 | platform-svc: `mfa_credentials` 테이블 미존재 | ✅ ddl-auto: update (PR #26) + ECR re-push로 해결 |
| D-025 | AWS SM 시크릿에 placeholder 값 → 실제 RDS PW로 교체 필요 | ✅ 8개 시크릿 값 업데이트 완료 |
| D-026 | EKS managed node group은 terraform `eks_nodes` SG가 아닌 자체 `eks-cluster-sg-*` 사용 | 매 terraform apply 후 RDS/Redis/MSK/OpenSearch SG에 EKS cluster SG 수동 추가 필요. terraform 코드에 `aws_eks_cluster.main.vpc_config[0].cluster_security_group_id` 참조 추가 권장 |
| D-027 | EKS 인증 모드 CONFIG_MAP → API_AND_CONFIG_MAP 변경 | access entry로 bastion role 등록. terraform eks.tf에 `access_config` 블록 추가 권장 |
| D-028 | liveness probe initialDelaySeconds 30s 부족 | Spring Boot 4.0 + DB migration 기동 ~40-60초. PR #35에서 90s로 수정 |
| D-029 | platform-svc: Flyway `provider_id` vs JPA `provider_user_id` 컬럼명 불일치 | ✅ V28 migration으로 컬럼 rename 해결 |
| D-030 | platform-svc: AES 키 포맷 오류 (hex 16B vs Base64 32B) | ✅ FieldEncryptor가 Base64 디코딩 후 32B 검증. `openssl rand -base64 32`로 생성 |
| D-031 | platform-svc: PR #24 이후 환경변수 14개 누락 (Stripe/OAuth2/crypto) | ✅ ExternalSecret 11개 + ConfigMap 3개 추가 (PR #40) |

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
| [#36](https://github.com/team-project-final/synapse-gitops/pull/36) | `docs/session8-final` | 핸드오프 v7 D-026~D-028 | Merged |
| [#37](https://github.com/team-project-final/synapse-gitops/pull/37) | `docs/session8-task-update` | TASK/WORKFLOW W2 갱신 | Merged |
| [#38](https://github.com/team-project-final/synapse-gitops/pull/38) | `fix/learning-ai-port-mismatch` | learning-ai 포트 8000→8090 | Merged |
| [#39](https://github.com/team-project-final/synapse-gitops/pull/39) | `docs/session8-handoff-final` | 핸드오프 v8 최종 | Merged |
| [#40](https://github.com/team-project-final/synapse-gitops/pull/40) | `fix/platform-svc-env-vars` | platform-svc 환경변수 14개 + 세션 runbook + 트러블슈팅 | Merged |
| [#41](https://github.com/team-project-final/synapse-gitops/pull/41) | `docs/session9-handoff` | 핸드오프 v9 (5/5 Healthy) | Merged |
| [#42](https://github.com/team-project-final/synapse-gitops/pull/42) | `fix/kafka-brokers-and-docs` | KAFKA_BROKERS 갱신 + 트러블슈팅 추가 | Merged |

### 서비스 레포

| 레포 | PR | 상태 |
|---|---|---|
| synapse-engagement-svc | [#7](https://github.com/team-project-final/synapse-engagement-svc/pull/7) | Merged → dev |
| synapse-knowledge-svc | [#16](https://github.com/team-project-final/synapse-knowledge-svc/pull/16) | Merged → dev |
| synapse-learning-svc | [#17](https://github.com/team-project-final/synapse-learning-svc/pull/17) | Merged → dev (learning-card Dockerfile) |
| synapse-learning-svc | [#18](https://github.com/team-project-final/synapse-learning-svc/pull/18) | Merged → dev (learning-ai Dockerfile fix) |
| **synapse-platform-svc** | [#26](https://github.com/team-project-final/synapse-platform-svc/pull/26) | **Merged → dev** (ddl-auto: update) |

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
