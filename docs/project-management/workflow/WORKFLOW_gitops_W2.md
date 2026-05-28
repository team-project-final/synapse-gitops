# WORKFLOW: @VelkaressiaBlutkrone — Week 2

> **Task 문서**: [TASK_gitops.md](../task/TASK_gitops.md)
> **기간**: 2026-05-19 ~ 2026-05-23, 5 영업일
> **주제**: dev 환경 5개 앱 자동 배포 + Secret 관리 + 이미지 sync

---

## Step 4: dev overlay 5개 앱 완성

### 1.1 사전 분석
- [x] 5개 앱별 리소스 요구사항 수집 (메모리/CPU/replica)
- [x] 환경 변수 / ConfigMap 목록 정리
- [x] Service 포트 / Health endpoint 표준 합의
<!-- 2026-05-28 D-041로 W4 Step 9 (prod 도메인 흐름)로 이월: dev 전용 도메인 패턴 결정 (dev-<app>.<도메인>). 사유: 도메인 미확보, staging-<app> 패턴과 묶어 prod 도메인 확보 시 동시 결정. -->

### 1.2 base 매니페스트 작성
- [x] apps/platform-svc/base/{deployment,service,configmap}.yaml
- [x] apps/engagement-svc/base/* 동일 구조
- [x] apps/knowledge-svc/base/* 동일 구조
- [x] apps/learning-card/base/* 동일 구조
- [x] apps/learning-ai/base/* 동일 구조
- [x] kustomization.yaml로 base 리소스 묶기

### 1.3 dev overlay 작성
- [x] apps/<app>/overlays/dev/kustomization.yaml × 5
- [x] dev용 replicaCount=1, resources.requests 최소화
- [x] dev 전용 ConfigMap patch (LOG_LEVEL=DEBUG 등)
<!-- 2026-05-28 D-041로 W4 Step 9로 이월: Ingress 또는 Service LoadBalancer 정의. 사유: ACM/도메인 확보 후. -->

### 1.4 적용 + 검증
- [x] git push → ArgoCD 5개 앱 모두 Synced + Healthy 확인 (kind)
- [x] EKS 배포: 3/5 Pod 정상 (engagement-svc, knowledge-svc, learning-card)
- [x] EKS 배포: platform-svc 정상 기동 (9차 세션: PR #40 환경변수 14개 + Flyway V28 + AES 키 수정)
- [x] EKS 배포: learning-ai 정상 기동 (9차 세션: 포트 8090 통일 PR #38 자동 해결)
- [x] /actuator/health 200 응답 (5/5 — 9차 세션 5/5 Healthy 달성)
<!-- 2026-05-28 D-041로 W4 Step 9로 이월: dev 도메인으로 5개 앱 도달. 사유: Ingress 미설정, ACM/도메인 확보 후. -->
- [x] KAFKA_BROKERS endpoint 갱신 (PR #34, terraform re-apply 후 MSK 주소 변경)
- [x] liveness probe initialDelaySeconds 30s → 90s (PR #35, D-028)
- [x] EKS cluster SG를 RDS/Redis/MSK/OpenSearch SG에 추가 (D-026)

**Step 4 Status**: [ ] Not Started / [x] In Progress / [ ] Done (EKS 3/5 Healthy, 2개 앱 레벨 미해결)

---

## Step 5: Secret 관리 (External Secrets Operator)

### 1.1 사전 분석
- [x] Secret 저장소 결정 (AWS Secrets Manager vs Parameter Store vs Vault) → AWS SM 채택
- [x] ESO vs SOPS vs Sealed Secrets 비교 후 선택 → ESO 채택
- [x] IRSA 권한 설계 (서비스 계정 → IAM Role)
- [x] 시크릿 명명 규칙 (예: synapse/<env>/<app>/<key>)

### 1.2 ESO 설치 + 구성
- [x] external-secrets helm chart 또는 매니페스트 적용 (kind: fake provider 검증)
- [x] IRSA 어노테이션 + IAM Policy 생성 (Role: `synapse-dev-eso-role`, 8차 세션 trust policy 갱신)
- [x] ClusterSecretStore 정의 (AWS provider) — `infra/external-secrets/cluster-secret-store.yaml`
- [x] 테스트 ExternalSecret로 sync 동작 확인 (kind: fake provider)

### 1.3 5개 앱 적용
- [x] platform-svc ExternalSecret 정의 (DB 비밀번호, JWT 키, OAuth 시크릿)
- [x] engagement-svc ExternalSecret 정의
- [x] knowledge-svc ExternalSecret 정의
- [x] learning-card ExternalSecret 정의
- [x] learning-ai ExternalSecret 정의
- [x] 기존 평문 Secret 모두 제거

### 1.4 보안 검증 + 문서화
- [x] gitleaks 또는 trufflehog로 git history 스캔 → 0건 (gitleaks 8.30.1 / 114 commits / 0 leaks, 2026-05-26)
<!-- 2026-05-28 D-041로 W3 Step 8 (Observability)로 이월: ESO sync 실패 시 알람 설정. 사유: W3 PrometheusRule + Alertmanager 스택에 알람 룰 추가가 자연스러움. -->
- [x] README에 새 시크릿 추가 절차 문서화
- [x] HISTORY에 결정 배경 + 대안 비교 기록

**Step 5 Status**: [ ] Not Started / [ ] In Progress / [x] Done (매니페스트 + provider swap 완료)

---

## Step 6: 이미지 태그 자동 sync

### 1.1 사전 분석
- [x] ArgoCD Image Updater vs git PR 기반 비교 → Image Updater 채택
- [x] 각 svc 레포의 이미지 태그 규칙 통일 합의
- [x] semver vs sha 태그 정책 결정 → semver (`^[0-9]+\.[0-9]+\.[0-9]+$`)
- [x] write-back 방식 결정 (git commit vs annotation) → git commit (kustomization)

### 1.2 구현
- [x] ArgoCD Image Updater 설치 (kind 검증 완료)
- [x] 각 Application에 image-updater annotation 추가 (ApplicationSet)
- [x] ImageUpdater CR 작성 (`argocd/image-updater.yaml`)
- [x] ECR 이미지 경로로 교체 완료

### 1.3 적용 + 검증
- [ ] 5개 앱 모두 새 이미지 푸시 → dev 자동 반영 확인 — EKS 배포 후
- [ ] 평균 반영 시간 측정 (목표 5분 이내) — EKS 배포 후
- [ ] 롤백 케이스: 잘못된 이미지 → 이전 태그로 복귀 가능 — EKS 배포 후
- [x] image 태그 변경 이력이 git log에 남는지 확인 (write-back-method: git 설정)

### 1.4 문서화 + 인수인계
- [x] 이미지 태그 정책 문서화
- [x] 자동 sync 비활성화 절차 (긴급 상황 대비) — `docs/runbooks/image-updater-ecr-setup.md` "긴급 정지 / 자동 sync 비활성화 절차" 섹션
- [x] svc 팀에 새 이미지 푸시 → 배포 흐름 공유 — `docs/synapse-developer-guide.md` §5 "GitOps 배포 흐름" (PR #28, 808줄 통합 가이드)
- [x] HISTORY 갱신

**Step 6 Status**: [ ] Not Started / [ ] In Progress / [x] Done (매니페스트 + ECR 교체 완료)
