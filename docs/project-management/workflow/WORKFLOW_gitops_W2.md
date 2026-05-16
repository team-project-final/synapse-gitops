# WORKFLOW: @VelkaressiaBlutkrone — Week 2

> **Task 문서**: [TASK_gitops.md](../task/TASK_gitops.md)
> **기간**: 2026-05-19 ~ 2026-05-23, 5 영업일
> **주제**: dev 환경 5개 앱 자동 배포 + Secret 관리 + 이미지 sync

---

## Step 4: dev overlay 5개 앱 완성

### 1.1 사전 분석
- [ ] 5개 앱별 리소스 요구사항 수집 (메모리/CPU/replica)
- [ ] 환경 변수 / ConfigMap 목록 정리
- [ ] Service 포트 / Health endpoint 표준 합의
- [ ] dev 전용 도메인 패턴 결정 (dev-<app>.<도메인>)

### 1.2 base 매니페스트 작성
- [ ] apps/platform-svc/base/{deployment,service,configmap}.yaml
- [ ] apps/engagement-svc/base/* 동일 구조
- [ ] apps/knowledge-svc/base/* 동일 구조
- [ ] apps/learning-card/base/* 동일 구조
- [ ] apps/learning-ai/base/* 동일 구조
- [ ] kustomization.yaml로 base 리소스 묶기

### 1.3 dev overlay 작성
- [ ] apps/<app>/overlays/dev/kustomization.yaml × 5
- [ ] dev용 replicaCount=1, resources.requests 최소화
- [ ] dev 전용 ConfigMap patch (LOG_LEVEL=DEBUG 등)
- [ ] Ingress 또는 Service LoadBalancer 정의

### 1.4 적용 + 검증
- [ ] git push → ArgoCD 5개 앱 모두 Synced + Healthy 확인
- [ ] 각 앱 Pod 로그 정상 (startup error 없음)
- [ ] /actuator/health 또는 동등 endpoint 200 응답
- [ ] dev 도메인으로 5개 앱 도달

**Step 4 Status**: [ ] Not Started / [ ] In Progress / [ ] Done

---

## Step 5: Secret 관리 (External Secrets Operator)

### 1.1 사전 분석
- [ ] Secret 저장소 결정 (AWS Secrets Manager vs Parameter Store vs Vault)
- [ ] ESO vs SOPS vs Sealed Secrets 비교 후 선택
- [ ] IRSA 권한 설계 (서비스 계정 → IAM Role)
- [ ] 시크릿 명명 규칙 (예: synapse/<env>/<app>/<key>)

### 1.2 ESO 설치 + 구성
- [ ] external-secrets helm chart 또는 매니페스트 적용
- [ ] IRSA 어노테이션 + IAM Policy 생성 (Secrets Manager read)
- [ ] ClusterSecretStore 정의 (AWS provider)
- [ ] 테스트 ExternalSecret로 sync 동작 확인

### 1.3 5개 앱 적용
- [ ] platform-svc ExternalSecret 정의 (DB 비밀번호, JWT 키, OAuth 시크릿)
- [ ] engagement-svc ExternalSecret 정의
- [ ] knowledge-svc ExternalSecret 정의
- [ ] learning-card ExternalSecret 정의
- [ ] learning-ai ExternalSecret 정의
- [ ] 기존 평문 Secret 모두 제거

### 1.4 보안 검증 + 문서화
- [ ] gitleaks 또는 trufflehog로 git history 스캔 → 0건
- [ ] ESO sync 실패 시 알람 설정
- [ ] README에 새 시크릿 추가 절차 문서화
- [ ] HISTORY에 결정 배경 + 대안 비교 기록

**Step 5 Status**: [ ] Not Started / [ ] In Progress / [ ] Done

---

## Step 6: 이미지 태그 자동 sync

### 1.1 사전 분석
- [ ] ArgoCD Image Updater vs git PR 기반 비교
- [ ] 각 svc 레포의 이미지 태그 규칙 통일 합의
- [ ] semver vs sha 태그 정책 결정
- [ ] write-back 방식 결정 (git commit vs annotation)

### 1.2 구현
- [ ] ArgoCD Image Updater 설치 (선택한 경우)
- [ ] 각 Application에 image-updater annotation 추가
- [ ] 또는 svc 레포의 release 워크플로우에서 gitops 레포로 PR 생성하는 스크립트
- [ ] write-back PR의 자동 머지 정책 정의

### 1.3 적용 + 검증
- [ ] 5개 앱 모두 새 이미지 푸시 → dev 자동 반영 확인
- [ ] 평균 반영 시간 측정 (목표 5분 이내)
- [ ] 롤백 케이스: 잘못된 이미지 → 이전 태그로 복귀 가능
- [ ] image 태그 변경 이력이 git log에 남는지 확인

### 1.4 문서화 + 인수인계
- [ ] 이미지 태그 정책 문서화
- [ ] 자동 sync 비활성화 절차 (긴급 상황 대비)
- [ ] svc 팀에 새 이미지 푸시 → 배포 흐름 공유
- [ ] HISTORY 갱신

**Step 6 Status**: [ ] Not Started / [ ] In Progress / [ ] Done
