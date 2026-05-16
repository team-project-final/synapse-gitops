# SCOPE: gitops

> **담당**: @VelkaressiaBlutkrone
> **트랙**: gitops (단일 트랙)
> **레포**: [synapse-gitops](https://github.com/team-project-final/synapse-gitops)

---

## In Scope

### 매니페스트 / GitOps
- ArgoCD 설치 및 부트스트랩 (HA 구성)
- ApplicationSet / app-of-apps 패턴으로 5개 앱 관리
- Kustomize base + dev/staging/prod overlay 구조
- 환경별 values 분리 (resources, replicas, env vars)
- Helm 차트 사용 시 ArgoCD Helm 통합

### 환경 운영
- dev / staging / prod 3개 환경 자동 sync
- 환경 간 승격(promote) 절차
- 이미지 태그 자동 갱신 (ArgoCD Image Updater 또는 webhook)
- Ingress / TLS 인증서 자동화 (cert-manager)
- DNS 자동화 (external-dns)

### 보안
- Secret 관리 (External Secrets Operator + AWS Secrets Manager, 또는 SOPS + KMS)
- git에 평문 시크릿 0건 보장
- RBAC 정책 (ArgoCD project별 권한 분리)
- 네트워크 정책 (NetworkPolicy)

### Observability
- Prometheus + Grafana 스택 설치
- Loki 또는 CloudWatch Logs 로그 수집
- 기본 알람 규칙 (앱 다운, 메모리/CPU 임계치, 5xx 비율)

### CI / 검증
- `validate-manifests.yml` 강화 (kustomize build + yamllint + kubeval/kubeconform)
- PR 시 영향받는 manifest diff 코멘트
- 커밋 서명 또는 SLSA 수준 검토

### 백업 / 복구
- Velero 또는 etcd snapshot 기반 클러스터 백업
- 데이터 볼륨 백업 정책
- 롤백 시나리오 1회 이상 실제 검증

### 문서
- 운영 Runbook (장애 시 조치)
- 환경별 접속/배포 가이드
- 핸드오프 문서

---

## Out of Scope

### 인프라 자체 프로비저닝
- EKS 클러스터 생성 (Terraform/CDK — 별도 트랙 또는 외부 작업)
- VPC / Subnet / IAM Role 생성
- RDS / ElastiCache / MSK(Kafka) 프로비저닝
- ACM 인증서 발급

### 애플리케이션 코드
- 각 svc 레포의 Spring Boot 코드
- Dockerfile (각 svc 레포 책임)
- 단위/통합 테스트

### 비즈니스 운영
- 사용자 데이터 마이그레이션
- 결제/Stripe 운영
- 고객 지원

---

## Boundary 명확화

| 영역 | gitops 트랙 | 다른 트랙 |
|---|---|---|
| 이미지 빌드 | 사용만 | 각 svc 트랙 (CI에서 ghcr push) |
| 이미지 태그 변경 → 배포 | 자동화 책임 | 트리거만 발생시킴 |
| DB 마이그레이션 | Job 매니페스트 정의 책임 | platform/engagement/... 각 svc가 SQL 작성 |
| 환경 변수 정의 | values.yaml에 적용 | 각 svc가 정의 |
| Secret 값 | 저장소 운영 책임 | 값 자체는 각 트랙 담당이 등록 |
| 로깅 포맷 | 수집 인프라 책임 | 각 svc가 로그 라이브러리 선택 |
| 알람 임계치 | 기본값 책임 | 각 svc가 SLO 정의 후 조정 요청 |
