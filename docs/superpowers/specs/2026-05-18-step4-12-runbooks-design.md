# Design Spec: Step 4~12 실행 런북 문서화

> **작성일**: 2026-05-18
> **범위**: Step 4~12 (W2~W5) 런북 13개 파일 작성
> **패턴 기준**: 기존 W1 런북 (step1-aws-account-setup.md, step2-terraform-tfvars.md, step3-terraform-apply.md, w1-argocd-bootstrap-runbook.md)

---

## 1. 목적

TASK/WORKFLOW 문서가 "무엇을 할지"를 정의하고 있으나, 실행 방법(명령어, 검증, 트러블슈팅)을 담은 런북이 Step 1~3에만 존재한다. Step 4~12의 런북을 동일 패턴으로 작성하여 실행 가이드를 완성한다.

---

## 2. 파일 구조

```
docs/runbooks/
├── w2-dev-deploy-runbook.md              # W2 상위 (Step 4/5/6)
├── step4-dev-overlay.md                  # Step 4 상세
├── step5-eso-secrets.md                  # Step 5 상세
├── step6-image-sync.md                   # Step 6 상세
├── w3-staging-observability-runbook.md   # W3 상위 (Step 7/8)
├── step7-staging-overlay.md              # Step 7 상세
├── step8-observability.md                # Step 8 상세
├── w4-prod-rollback-runbook.md           # W4 상위 (Step 9/10)
├── step9-prod-approval.md                # Step 9 상세
├── step10-rollback-backup.md             # Step 10 상세
├── w5-stabilize-runbook.md               # W5 상위 (Step 11/12)
├── step11-operational-runbook.md         # Step 11 상세
└── step12-cost-optimization.md           # Step 12 상세
```

---

## 3. 템플릿

### 3.1 상위 런북 (주차별)

```markdown
# Runbook: W{N} {주제} 실행 가이드

> **대상**: gitops 트랙 담당자 (@VelkaressiaBlutkrone)
> **소요 시간**: 약 {합계}
> **전제**: W{N-1} 완료

## 0. 준비물 체크리스트
- 도구, 인증, 사전 상태

## {Step}. {제목} ({시간})
📖 **[파일](./파일)** — 요약
요약: 핵심 명령 + 완료 신호

## 검증 체크리스트 (PRD 매핑)
- FR-GO-XXX: 검증 명령

## 트러블슈팅 (공통)
```

### 3.2 상세 런북 (Step별)

```markdown
# Runbook: {제목} (Step {N} 상세)

> **소요 시간**: 약 {시간}
> **결과**: {검증 가능 한 줄}
> **상위 문서**: [링크]
> **사전 조건**: {이전 Step}

## {N}-A. {단계} ({시간})
명령어 (bash / PowerShell 분기), Expected 출력

## 검증
## 자주 막히는 지점
## 다음 단계
```

---

## 4. Step별 내용 설계

### Step 4: dev overlay 5개 앱 완성 (W2, 2일)

- **4-A. 사전 분석**: 5개 앱별 리소스/포트/헬스체크 정리
- **4-B. base 매니페스트 작성**: deployment, service, configmap × 5앱
- **4-C. dev overlay 작성**: kustomization.yaml × 5, replicas=1, resources 최소
- **4-D. ArgoCD sync + 검증**: git push → 5앱 Synced+Healthy, Pod 로그, 헬스체크
- **검증**: `argocd app list`, `kubectl get pods -n dev`, 각 앱 /health 200
- **트러블슈팅**: ImagePullBackOff, CrashLoopBackOff, kustomize build 실패

### Step 5: Secret 관리 — ESO (W2, 1.5일)

- **5-A. 사전 분석**: ESO vs SOPS vs Sealed Secrets 비교 (추천: ESO)
- **5-B. ESO 설치**: helm chart, IRSA 어노테이션, IAM Policy
- **5-C. ClusterSecretStore 구성**: AWS Secrets Manager backend
- **5-D. 5개 앱 ExternalSecret 작성**: DB 비밀번호, JWT, OAuth 등
- **5-E. 보안 검증**: gitleaks 스캔, 평문 Secret 제거
- **검증**: `kubectl get externalsecret -A`, SecretSynced=True × 5
- **트러블슈팅**: IRSA 권한 부족, SecretStore 연결 실패, sync 주기

### Step 6: 이미지 태그 자동 sync (W2, 1.5일)

- **6-A. 사전 분석**: ArgoCD Image Updater vs GitHub Actions PR 방식 비교
- **6-B. 구현**: Image Updater 설치 + annotation 또는 CI PR 스크립트
- **6-C. write-back 설정**: git commit 방식 + 자동 머지 정책
- **6-D. 검증**: 테스트 이미지 푸시 → 5분 내 dev 반영, git log 이력
- **트러블슈팅**: ECR 인증, write-back 권한, 반영 지연

### Step 7: staging 환경 overlay (W3, 2일)

- **7-A. 사전 분석**: 네임스페이스 분리, 승격 트리거, 도메인 패턴
- **7-B. staging overlay 작성**: kustomization.yaml × 5, replicas=2
- **7-C. ApplicationSet 확장**: matrix에 staging 추가 → 10 Application
- **7-D. 승격 시뮬레이션**: dev → staging 1회 검증
- **검증**: `argocd app list` 10개, staging 도메인 헬스체크
- **트러블슈팅**: 네임스페이스 충돌, Ingress 라우팅, TLS

### Step 8: Observability 스택 (W3, 2일)

- **8-A. 사전 분석**: kube-prometheus-stack, 로그 백엔드, 알람 채널
- **8-B. 메트릭 스택 설치**: Prometheus + Grafana helm, ServiceMonitor × 5
- **8-C. 로그 스택**: Loki + Promtail, Grafana Explore 연동
- **8-D. 대시보드 + 알람**: Synapse 개요 대시보드, PrometheusRule 3개+
- **8-E. 알람 테스트**: 의도적 알람 1건 → 채널 도달 확인
- **검증**: Grafana UI 접속, 메트릭 조회, 알람 수신
- **트러블슈팅**: scrape target 누락, 알람 미발송, Grafana 인증

### Step 9: prod 환경 + 승인 게이트 (W4, 2일)

- **9-A. 사전 분석**: 클러스터 분리, 승인 방식, 권한 모델
- **9-B. prod overlay + AppProject**: kustomization.yaml × 5, Manual Sync
- **9-C. RBAC 적용**: prod sync 권한 그룹, 비권한 거부 검증
- **9-D. 승격 검증**: dev → staging → prod 전체 흐름 1회
- **검증**: 15 Application(5×3환경), 권한 분리, prod 도메인 응답
- **트러블슈팅**: sync 정책 혼동, RBAC 거부, 인증서

### Step 10: 롤백 / 백업 전략 (W4, 2일)

- **10-A. 사전 분석**: 롤백 시나리오 분류, RTO/RPO, 백업 저장소
- **10-B. ArgoCD 롤백 검증**: History rollback + git revert
- **10-C. Velero 설치 + 백업**: S3 BackupStorageLocation, 일일 스케줄
- **10-D. 복구 시뮬레이션**: staging 네임스페이스 삭제 → 복구
- **검증**: 백업 성공 로그, 복구 시뮬 통과, 백업 모니터링 알람
- **트러블슈팅**: Velero 권한, 백업 크기, 복구 순서

### Step 11: Runbook + 장애 시나리오 (W5, 2일)

- **11-A. 장애 유형 도출**: CrashLoop, OOM, sync 실패, 인증서 만료, DB 연결
- **11-B. 5개 시나리오 Runbook 작성**: 각각 symptom → cause → action
- **11-C. 시뮬레이션**: staging에서 3개 이상 장애 유발 → 복구
- **11-D. On-call 체계**: 연락처, Slack 채널, 에스컬레이션
- **검증**: team-lead 따라하기 1회 통과
- **트러블슈팅**: 시뮬레이션 환경 정리, 알람 경로

### Step 12: Cost 최적화 + 안정화 (W5, 2일)

- **12-A. 비용 가시성**: Cost Explorer 태그, 현재 분포 측정
- **12-B. 리소스 적정화**: requests/limits 조정, HPA × 2앱, PDB
- **12-C. 안정화**: P0/P1 이슈 0건 확인, 전체 헬스체크
- **12-D. 핸드오프**: 최종 문서 검토, 인수 미팅, HISTORY 회고
- **검증**: HPA 동작, Cost Explorer 태그 보임, P0/P1 0건
- **트러블슈팅**: HPA 미동작, 태그 누락, 비용 이상

---

## 5. 작성 원칙

1. WORKFLOW 체크리스트를 실행 순서로 변환
2. 의사결정 지점에서 선택지 + 추천안 제시
3. 트러블슈팅은 "예상 케이스"로 작성 (실행 후 실제 케이스 추가)
4. OS별 명령 분기 (bash / PowerShell)
5. 비용 영향이 있는 Step에 비용 추정 포함
6. 각 런북 끝에 "다음 단계" 링크로 연결

---

## 6. 범위 외

- 실제 매니페스트/코드 작성 (런북 실행 시 수행)
- TASK/WORKFLOW/PRD 문서 수정 (기존 유지)
- W1 런북 변경 (기존 유지)
