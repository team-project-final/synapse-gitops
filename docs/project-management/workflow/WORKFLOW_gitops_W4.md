# WORKFLOW: @VelkaressiaBlutkrone — Week 4

> **Task 문서**: [TASK_gitops.md](../task/TASK_gitops.md)
> **기간**: 2026-06-01 ~ 2026-06-05, 4 영업일 (6/3 지방선거 제외)
> **주제**: prod 환경 + 승인 게이트 + 롤백/백업 전략

---

## Step 9: prod 환경 + 승인 게이트

### 1.1 사전 분석
- [ ] prod 클러스터 / 네임스페이스 분리 정책 (별도 클러스터 권장)
- [ ] 승인 게이트 방식 결정 (ArgoCD Manual Sync vs GH Environment Approval)
- [ ] prod 접근 권한 분리 (별도 IAM/RBAC)
- [ ] 변경 관리 절차 (PR 라벨 + 리뷰어 합의)
- [ ] ACM 인증서 ARN 매핑 (HTTPS 종료) — W1 Step 1.2에서 이월 (D-041)
- [ ] DNS 레코드 정의 (argocd.<도메인> + prod 앱 도메인) — W1 Step 1.2에서 이월 (D-041)
- [ ] 외부 도메인으로 ArgoCD UI 접속 + TLS 인증서 유효 — W1 Step 1.3에서 이월 (D-041)
- [ ] webhook endpoint 외부 도달 (curl 또는 GitHub webhook ping) — W1 Step 1.3에서 이월 (D-041)

### 1.2 prod overlay + 정책 작성
- [ ] apps/<app>/overlays/prod/kustomization.yaml × 5
- [ ] prod resources: replicas 3+, requests 운영급
- [ ] prod ExternalSecret (synapse/prod/<app>/*)
- [ ] AppProject `synapse-prod`에 Manual Sync 정책
- [ ] prod sync 권한 그룹 정의 (예: gitops-admin)

### 1.3 적용 + 검증
- [ ] prod 매니페스트 적용 (단, Application은 syncPolicy 없음)
- [ ] dev/staging → prod 승격 PR 1회 시뮬레이션
- [ ] 권한 없는 계정으로 prod sync 시도 → 거부 확인
- [ ] 권한 있는 계정으로 prod sync → 성공 확인
- [ ] prod 도메인으로 5개 앱 응답 확인
- [ ] dev 전용 도메인 패턴 적용 (dev-<app>.<도메인>) — W2 Step 4.1에서 이월 (D-041)
- [ ] dev Ingress 또는 Service LoadBalancer 정의 + 적용 — W2 Step 4.3에서 이월 (D-041)
- [ ] dev 도메인으로 5개 앱 도달 (HTTP 200) — W2 Step 4.4에서 이월 (D-041)

### 1.4 문서화 + 핸드오프
- [ ] prod 배포 절차 README (PR → 리뷰 → 머지 → ArgoCD 승인 → 검증)
- [ ] prod 권한 신청 절차 문서화
- [ ] team-lead와 권한 모델 검토 + 합의
- [ ] HISTORY에 prod 첫 배포 일자 기록

**Step 9 Status**: [ ] Not Started / [ ] In Progress / [ ] Done

---

## Step 10: 롤백 / 백업 전략

### 1.1 사전 분석
- [ ] 롤백 시나리오 분류 (단일 앱 매니페스트 / 이미지만 / 클러스터 전체)
- [ ] 백업 대상 결정 (etcd, PV, Velero 범위)
- [ ] RTO/RPO 목표 합의 (예: RTO 30분, RPO 1시간)
- [ ] 백업 저장소 결정 (S3 + 별도 리전)

### 1.2 롤백 절차 구현
- [ ] ArgoCD History rollback 절차 검증 (UI에서 1 step 이전 sync)
- [ ] git revert + 자동 sync로 롤백 절차 검증
- [ ] Image Updater 사용 시 태그 강제 고정 절차
- [ ] DB 마이그레이션이 포함된 경우 롤백 가이드 (forward-only 정책 등)

### 1.3 백업 / 복구 시뮬레이션
- [ ] Velero 설치 + S3 BackupStorageLocation 설정
- [ ] 일일 스케줄 백업 정의
- [ ] staging에서 네임스페이스 삭제 → 복구 시뮬레이션
- [ ] etcd snapshot 정책 정의 (관리형 EKS는 AWS 책임 영역 명시)

### 1.4 문서화 + 검증
- [ ] Runbook 초안에 롤백 절차 포함
- [ ] 백업 모니터링 알람 (백업 실패 시 알림)
- [ ] team-lead와 RTO/RPO 합의 + 사인오프
- [ ] HISTORY 갱신

**Step 10 Status**: [ ] Not Started / [ ] In Progress / [ ] Done
