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
- [x] ACM 인증서 ARN 매핑 (HTTPS 종료) — **nip.io 임시 도메인 완결**: self-signed ACM import (#121, PR #123, 06-08 윈도우2)
- [x] DNS 레코드 정의 (argocd.<도메인> + prod 앱 도메인) — **nip.io 임시 도메인**으로 충족 (#121)
- [x] 외부 도메인으로 ArgoCD UI 접속 + TLS 인증서 유효 — **완결**: `curl --cacert` argocd 200, 체인 `Verify return code 0` (#121, 06-08 라이브)
- [x] webhook endpoint 외부 도달 (curl 또는 GitHub webhook ping) — **완결**: `/api/webhook` 200 (#121, 06-08 라이브)
<!-- 2026-06-10 W4 마감: 실 도메인 항목을 nip.io 임시 도메인 라이브 증명(#121)으로 완결(team-lead 결정). 실 도메인 확보 시 docs/argocd-tls-migration.md 절차로 전환. -->


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
- [x] dev 전용 도메인 패턴 적용 (dev-<app>.<도메인>) — **nip.io 임시 도메인** 적용 (#121, 06-08)
- [x] dev Ingress 또는 Service LoadBalancer 정의 + 적용 — nip.io ingress + ALB 컨트롤러 부트스트랩 (#121, PR #123/#124)
- [x] dev 도메인으로 5개 앱 도달 (HTTP 200) — **완결**: nip.io 경유 `dev/actuator/health` 200 (#121, 06-08 라이브)

### 1.4 문서화 + 핸드오프
- [x] prod 배포 절차 README (PR → 리뷰 → 머지 → ArgoCD 승인 → 검증) — `argocd/README.md` (PR #74)
- [x] prod 권한 신청 절차 문서화 — `argocd/README.md` RBAC/계정 섹션 (PR #74)
- [x] team-lead와 권한 모델 검토 + 합의 — **D-043 사인오프 완료 (2026-06-10, velka 겸임)**
- [x] HISTORY에 prod 첫 배포 일자 기록 — HISTORY 2026-05-28(거버넌스) + 2026-06-01(5/5 재현, D-043)
- [x] docs-portal 배포 복구 — deploy-pages 익명 체크아웃 전환(PR #83)으로 6일간 끊겼던 포털 정상화, W4 런북(롤백/백업/라이브 재현)이 https://team-project-final.github.io/synapse-gitops/ 에 실제 공개 (HISTORY 2026-06-01 CI 참조)

**Step 9 Status**: [ ] Not Started / [ ] In Progress / [x] Done (FR-401~404 전부 라이브 증명 — 2026-06-01 prod 5/5 Healthy. 실 도메인 항목은 nip.io 임시 도메인 라이브(#121)으로 완결. **D-043 team-lead 사인오프 완료 — 2026-06-10, velka 겸임**)

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
- [x] Image Updater 5개 앱 새 이미지 푸시 → dev 자동 반영 E2E 검증 — **#122 라이브 close**: engagement-svc 1.0.0→1.0.1 write-back PR 자동생성→sync (06-08 윈도우2)
- [x] Image Updater 평균 반영 시간 측정 (목표 5분 이내) — **45초** (목표 충족, #122)
- [x] Image Updater 롤백 케이스: 잘못된 이미지 → 이전 태그 복귀 가능 — **19초** revert PR #150 → 이전 태그 복귀 (#122)

### 1.3 백업 / 복구 시뮬레이션
- [x] Velero 설치 + S3 BackupStorageLocation 설정 — 라이브 설치(IRSA+S3), BSL Available (FR-407)
- [x] 일일 스케줄 백업 정의 — `velero-schedule.yaml` + 라이브 백업 Completed + S3 저장 (FR-407)
- [x] staging에서 네임스페이스 삭제 → 복구 시뮬레이션 — 격리 ns 백업→삭제→restore 복구 확인 (FR-408)
- [x] etcd snapshot 정책 정의 (관리형 EKS는 AWS 책임 영역 명시) — runbook 명시

### 1.4 문서화 + 검증
- [x] Runbook 초안에 롤백 절차 포함 — `docs/runbooks/w4-prod-rollback-backup-runbook.md`
- [x] 백업 모니터링 알람 (백업 실패 시 알림) — `velero.rules` PrometheusRule (W3 Alertmanager 재사용)
- [x] team-lead와 RTO/RPO 합의 + 사인오프 — **D-043 사인오프 완료 (2026-06-10, velka 겸임)**
- [x] HISTORY 갱신 — HISTORY 2026-05-28 + 2026-06-01 라이브 재현 섹션 (D-043) + 2026-06-10 W4 마감

**Step 10 Status**: [ ] Not Started / [ ] In Progress / [x] Done (롤백 405/406 라이브 검증(2026-06-01) + 백업/복구(407/408) + 알람 + 런북 Done. image-updater E2E 3항목 #122 라이브 close(06-08). **D-043 team-lead 사인오프 완료 — 2026-06-10, velka 겸임**)

---

## 2026-06-02 후속 — MSK 토픽·인증 terraform 편입 (D-044)

> 본격 작업: spec/plan `…2026-06-02-w4-remaining-msk-terraform-tls…`, 브랜치 `docs/w4-remaining-msk-terraform-tls`. HISTORY 2026-06-02 참조.

- [x] **MSK 인증 모델 B(TLS-only) 확정** (D-044) — `msk.tf` 무변경, 서비스 코드/config 무변경. A(SASL/IAM)는 W5+ 백로그.
- [x] **9개 Kafka 토픽 terraform 선언화** — `infra/aws/dev/kafka-topics/`(Mongey/kafka). 라이브 재기동에서 bastion apply로 9/9 생성 입증(RF=2). 기존 bastion 수동 스크립트 제거.
- [x] **bastion→MSK SG 9094 인바운드 추가**(vpc.tf) — "bastion 차단"의 네트워크 실체 해소.
- [x] **shared `KAFKA_AUTH_MATRIX` TLS-only 정합** — 브랜치 `docs/kafka-auth-tls-only`(team-lead 검토 후 push).

### 사인오프 패키지 (✅ D-043 사인오프 완료 — 2026-06-10, velka 겸임)
- **권한 모델**: ArgoCD RBAC `role:prod-deployer`(prod sync 허용) + 로컬 `gitops-admin`. FR-403로 거부/허용 라이브 증명(2026-06-01). 신청 절차 `argocd/README.md`.
- **RTO/RPO**: RTO 30분 / RPO 1시간. 롤백(FR-405/406)·백업복구(FR-407/408) 라이브 검증 완료. 런북 `w4-prod-rollback-backup-runbook.md`.

### 이월 정정 (차단사유 → 해소)
- **image-updater E2E (W2 이월)** — ✅ **해소**: #122로 ArgoCD/image-updater 부트스트랩 + bastion access-entry(#87) 후 06-08 윈도우2 write-back E2E 라이브 close(반영 45s·롤백 19s).
- **실 도메인 3항목 (W1 이월)** — ✅ **nip.io 임시 도메인 완결**(#121, 06-08). 실 도메인 확보 시 `docs/argocd-tls-migration.md` 전환.
- **브로커 주소 자동화 / A안 SASL/IAM** — W5 백로그(`docs/superpowers/W5-scoping.md`). 브로커 주소는 #88(ConfigMap terraform)로 해소.
