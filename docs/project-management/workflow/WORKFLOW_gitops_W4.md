# WORKFLOW: @VelkaressiaBlutkrone — Week 4

> **Task 문서**: [TASK_gitops.md](../task/TASK_gitops.md)
> **기간**: 2026-06-01 ~ 2026-06-05, 4 영업일 (6/3 지방선거 제외)
> **주제**: prod 환경 + 승인 게이트 + 롤백/백업 전략

---

## Step 9: prod 환경 + 승인 게이트

### 1.1 사전 분석
- [x] prod 클러스터 / 네임스페이스 분리 정책 — 논리 분리(dev 클러스터 내 `synapse-prod` ns) 채택 (D-042, spec §2)
- [x] 승인 게이트 방식 결정 — ArgoCD Manual Sync (D-042)
- [x] prod 접근 권한 분리 — ArgoCD RBAC `role:prod-deployer` + 로컬 계정 `gitops-admin` (D-042)
- [x] 변경 관리 절차 — 변경 게이트=기존 main PR 보호, prod 이미지=명시적 PR 승격 (D-042)
- [ ] ACM 인증서 ARN 매핑 (HTTPS 종료) — W1 Step 1.2에서 이월 (D-041). 실 도메인 부재로 미충족, 라이브 기동 후 (FR-404)
- [ ] DNS 레코드 정의 (argocd.<도메인> + prod 앱 도메인) — W1 Step 1.2에서 이월 (D-041). 실 도메인 부재
- [ ] 외부 도메인으로 ArgoCD UI 접속 + TLS 인증서 유효 — W1 Step 1.3에서 이월 (D-041). 실 도메인 부재
- [ ] webhook endpoint 외부 도달 (curl 또는 GitHub webhook ping) — W1 Step 1.3에서 이월 (D-041). 실 도메인 부재

### 1.2 prod overlay + 정책 작성
- [x] apps/<app>/overlays/prod/kustomization.yaml × 5 (PR #74, 렌더 5/5 OK)
- [x] prod resources: replicas 3+, requests 운영급 (replicas=3)
- [x] prod ExternalSecret (synapse/prod/<app>/*)
- [x] AppProject `synapse-prod`에 Manual Sync 정책 (`applicationset-prod.yaml` automated 없음)
- [x] prod sync 권한 그룹 정의 (예: gitops-admin)

### 1.3 적용 + 검증
- [x] prod 매니페스트 적용 (단, Application은 syncPolicy 없음) — 라이브 apply, 5개 OutOfSync 확인 (FR-402)
- [x] dev/staging → prod 승격 PR 1회 시뮬레이션 — prod 이미지=명시적 PR 승격 경로 결정 (D-042)
- [x] 권한 없는 계정으로 prod sync 시도 → 거부 확인 — `argocd admin settings rbac can` 평가 No (FR-403)
- [x] 권한 있는 계정으로 prod sync → 성공 확인 — gitops-admin can sync Yes, 2026-06-01 라이브 5/5 기동 (FR-403/404)
- [x] prod 도메인으로 5개 앱 응답 확인 — 2026-06-01 라이브 재현: synapse-prod 15/15 Healthy, readiness probe(=/actuator/health 200)로 충족(실 도메인 미적용은 W1 이월). 인프라 증설(t3.large×4/db.t3.small) 적용 (FR-404, D-043)
- [ ] dev 전용 도메인 패턴 적용 (dev-<app>.<도메인>) — W2 Step 4.1에서 이월 (D-041). 실 도메인 부재
- [ ] dev Ingress 또는 Service LoadBalancer 정의 + 적용 — W2 Step 4.3에서 이월 (D-041)
- [ ] dev 도메인으로 5개 앱 도달 (HTTP 200) — W2 Step 4.4에서 이월 (D-041). 실 도메인 부재

### 1.4 문서화 + 핸드오프
- [x] prod 배포 절차 README (PR → 리뷰 → 머지 → ArgoCD 승인 → 검증) — `argocd/README.md` (PR #74)
- [x] prod 권한 신청 절차 문서화 — `argocd/README.md` RBAC/계정 섹션 (PR #74)
- [ ] team-lead와 권한 모델 검토 + 합의 — 사인오프 대기
- [x] HISTORY에 prod 첫 배포 일자 기록 — HISTORY 2026-05-28(거버넌스) + 2026-06-01(5/5 재현, D-043)

**Step 9 Status**: [ ] Not Started / [ ] In Progress / [x] Done (FR-401~404 전부 라이브 증명 — 2026-06-01 prod 5/5 Healthy. 실 도메인 3항목만 W1 이월 잔존(port-forward 대체), team-lead 합의 대기 — D-043)

---

## Step 10: 롤백 / 백업 전략

### 1.1 사전 분석
- [x] 롤백 시나리오 분류 (단일 앱 매니페스트 / 이미지만 / 클러스터 전체) — runbook `w4-prod-rollback-backup-runbook.md`
- [x] 백업 대상 결정 (etcd, PV, Velero 범위) — Velero ns 최소(synapse-prod/staging)+PV, etcd=관리형 EKS AWS 책임
- [x] RTO/RPO 목표 합의 (예: RTO 30분, RPO 1시간) — RTO 30분/RPO 1시간 설정 (사인오프는 1.4)
- [x] 백업 저장소 결정 (S3 + 별도 리전) — 전용 S3 버킷 (별도 리전 미적용, 캡스톤 한계)

### 1.2 롤백 절차 구현
- [x] ArgoCD History rollback 절차 검증 (UI에서 1 step 이전 sync) — 2026-06-01 라이브: prod engagement-svc `argocd app rollback` 1-step → Synced/Healthy (FR-405)
- [x] git revert + 자동 sync로 롤백 절차 검증 — 2026-06-01 라이브: PR #80(DEBUG)→sync→PR #81(git revert)→sync→INFO 복원 (FR-406)
- [x] Image Updater 사용 시 태그 강제 고정 절차 — prod=명시적 PR 승격(image-updater 어노테이션 없음), runbook
- [x] DB 마이그레이션이 포함된 경우 롤백 가이드 (forward-only 정책 등) — runbook §4 (Flyway forward-only, 데이터=RDS PITR)
- [ ] Image Updater 5개 앱 새 이미지 푸시 → dev 자동 반영 E2E 검증 — W2 Step 6.3에서 이월 (D-041, A안 실행 필요)
- [ ] Image Updater 평균 반영 시간 측정 (목표 5분 이내) — W2 Step 6.3에서 이월 (D-041)
- [ ] Image Updater 롤백 케이스: 잘못된 이미지 → 이전 태그 복귀 가능 — W2 Step 6.3에서 이월 (D-041)

### 1.3 백업 / 복구 시뮬레이션
- [x] Velero 설치 + S3 BackupStorageLocation 설정 — 라이브 설치(IRSA+S3), BSL Available (FR-407)
- [x] 일일 스케줄 백업 정의 — `velero-schedule.yaml` + 라이브 백업 Completed + S3 저장 (FR-407)
- [x] staging에서 네임스페이스 삭제 → 복구 시뮬레이션 — 격리 ns 백업→삭제→restore 복구 확인 (FR-408)
- [x] etcd snapshot 정책 정의 (관리형 EKS는 AWS 책임 영역 명시) — runbook 명시

### 1.4 문서화 + 검증
- [x] Runbook 초안에 롤백 절차 포함 — `docs/runbooks/w4-prod-rollback-backup-runbook.md`
- [x] 백업 모니터링 알람 (백업 실패 시 알림) — `velero.rules` PrometheusRule (W3 Alertmanager 재사용)
- [ ] team-lead와 RTO/RPO 합의 + 사인오프 — 사인오프 대기
- [x] HISTORY 갱신 — HISTORY 2026-05-28 + 2026-06-01 라이브 재현 섹션 (D-043)

**Step 10 Status**: [ ] Not Started / [ ] In Progress / [x] Done (롤백 405/406 라이브 검증(2026-06-01) + 백업/복구(407/408) + 알람 + 런북 Done. image-updater E2E 3항목만 W2 이월 잔존, team-lead 사인오프 대기 — D-043)
