# W3/W4 미완료 항목 감사 + 정합 — 설계

- 작성일: 2026-06-08 (W5 Day1)
- 대상 리포: `synapse-gitops`
- 관련: TASK_gitops W3(Step 7/8 + 정리·마감)·W4(Step 9/10), 이슈 #91/#92/#121/#122, PR #136
- 후속(별도): 하위프로젝트 B = 포털 핸드오프 허브 뷰 구축

## 1. 목적과 범위

W3/W4에서 완료되지 못한 항목을 **2026-06-08 현재(PR #136 머지 포함) 기준으로 재대조**하고, 추적에서 새거나 문서와 어긋난 부분을 정합한다. 비용 0 — gitops 문서·이슈 코멘트만 손댄다.

### 범위 (이번 작업)

- 감사 문서(본 문서) — W3/W4 미완료 항목 처분 표 + #92 이중원인 정합 + 신규 발견 + D-043 사인오프 체크리스트
- `TASK_gitops.md` 상태 정합 2곳(W3 Step 7 Status, W4→W5 윈도우 #92 항목)
- #92 GitHub 이슈 정합 코멘트(close 안 함 — OPEN 유지)

### 비범위 (명시 제외)

- 인프라 변경(staging RDS 환경 분리 등) — 윈도우 2 / team-lead 판단
- #91/#121/#122 라이브 검증 — 윈도우 2 (`W5_WINDOW_2.md`)에 이미 계획
- B2 포털 핸드오프 허브 뷰 — 하위프로젝트 B(별도 spec→plan)
- team-lead 사인오프 행위 자체 — 본 작업은 사인오프 **준비물**만 제공

### 성공 기준

처분 표의 모든 항목이 단일 처분값(완료/윈도우2/사인오프대기/대체됨/하위프로젝트)으로 귀속 + TASK/이슈 문서가 현재 코드 상태와 일치 + D-043 사인오프 체크리스트 제공.

## 2. W3/W4 미완료 항목 처분 표

| 항목 | 출처 | 처분 | 근거 |
|------|------|------|------|
| Step 7 staging 4/5 (platform-svc) | W3 | 🔄 윈도우 2 재검증 | #92 — §3 이중원인 정리, gitops 층은 PR #136으로 해소 |
| Step 8 Observability | W3 | ✅ 완료 | A2 실 EKS 1사이클 검증(메트릭 UP·Alertmanager→Slack·스택 Healthy) |
| A1 cross-repo work order | W3 정리 | ✅ 완료 | PR #60 / `synapse-platform-svc#37` |
| A2 ESO IRSA terraform | W3 정리 | ✅ 완료 | PR #61 |
| A3 노드 3→4 증설 | W3 정리→W4 | ✅ 완료(라이브) | W4 prod 재현 시 t3.large×4 적용 |
| A4 staging ACM/TLS terraform | W3 정리→W4 | ↪️ 대체됨 | D-047 nip.io self-signed ACM(#121, 윈도우 2)로 경로 변경 |
| A5 image-updater A안(전용 봇 bypass) | W3 정리→W4 | ↪️ 대체됨 | PR write-back #127(#126 대응)로 전환 |
| B2 포털 핸드오프 허브 뷰 | W3 정리→W4 | 🏗️ 하위프로젝트 B | 별도 빌드(Flutter Runbook Site + build_docs.mjs 확장) |
| W2 S4 engagement-svc Pending | W3 정리 | ✅ 완료 | 노드 capacity(A3)로 해소 경로 확보 + W4 라이브 fleet |
| Step 9 ACM/DNS·외부HTTPS·webhook (3) | W4 | 🔄 윈도우 2 | #121 nip.io 임시도메인. 실 도메인 부재로 W1 이월 |
| Step 9 team-lead 합의 (D-043) | W4 | ⏳ 사인오프 대기 | FR-401~404 prod 5/5 라이브 증명됨(§5 체크리스트) |
| Step 10 team-lead 사인오프 (D-043) | W4 | ⏳ 사인오프 대기 | 롤백 405/406 + 백업 407/408 라이브 검증됨(§5 체크리스트) |

> 처분 범례: ✅ 완료 · 🔄 윈도우 2 라이브 · ⏳ 사인오프 대기 · ↪️ 대체됨(상위 결정으로 경로 변경) · 🏗️ 하위프로젝트로 이관

## 3. #92 이중원인 정합 (감사 핵심)

platform-svc-staging은 **서로 다른 두 층의 원인**이 얽혀 있었고, 이슈 트래커는 ①만 반영 중이었다.

### ① datasource 부재 (이슈 #92 원래 증상)

- 증상: `Failed to configure a DataSource: 'url' attribute is not specified` (profiles staging active)
- 규명: 윈도우 1(2026-06-05) 당시 배포 이미지 `dev-latest`가 `application-staging.yml`이 **platform-svc main에 머지되기 전** 빌드본 → 컨테이너 내 staging 프로파일에 datasource 설정 자체가 부재.
- 현재(2026-06-08) 해소 상태:
  - platform-svc `main:application-staging.yml`이 `datasource.url: ${DB_URL}` / `username: ${DB_USERNAME}` / `password: ${DB_PASSWORD}` 제공 — **확인됨**.
  - gitops `apps/platform-svc/overlays/staging/kustomization.yaml`이 `DB_URL`/`DB_USERNAME`/`DATABASE_NAME=synapse_platform` 주입 — **확인됨(PR #136)**.
- 잔여(윈도우 2): `application-staging.yml` 머지 이후 시점으로 **platform-svc 재빌드**(이미지 `imagePushedAt` > 머지 시각) + staging sync 라이브 재검증.

### ② flyway_schema_history 충돌 (W5 Day1 별개 발견)

- 증상: `flyway_schema_history ... checksum mismatch` — 5서비스가 단일 RDS `synapse` DB를 공유해 다른 서비스 이력을 검증.
- 해소: **PR #136**으로 서비스별 DB 분리(`synapse_platform`/`synapse_engagement`/`synapse_knowledge`/`synapse_learning`/`synapse_ai`). gitops 층 완결.

> ①과 ②는 독립 원인이다. ②는 PR #136으로 코드 해소 완료, ①은 재빌드+라이브 재검증만 남았다. 둘 다 충족되면 #92 close 가능(윈도우 2).

## 4. 신규 발견 — staging가 dev RDS·DB 공유

감사 중 드러난 격리 갭(기존 추적에 없던 항목):

- gitops staging 오버레이의 `DB_URL` 호스트 = **`synapse-dev-postgres`**, DB = `synapse_platform`.
- 즉 dev·staging platform-svc가 **동일 인스턴스 + 동일 DB** 를 공유. PR #136은 서비스별 분리지만 **환경별 분리는 아니다**.
- 영향: 동일 서비스라 flyway checksum 충돌은 없으나, ① 환경 데이터 격리 부재 ② dev/staging 동시 배포 시 마이그레이션 경합 가능성.
- 처분: **본 감사에 기록만**. 인프라 변경(staging 전용 DB/인스턴스 또는 `synapse_platform_staging` 분리)은 비용·사이징 결정이 필요 → **윈도우 2 / team-lead 위임**. 이번 비용 0 범위에서 변경하지 않는다.

## 5. D-043 team-lead 사인오프 체크리스트

Step 9/10은 라이브 증명을 마쳤고 사인오프만 대기 중이다. team-lead가 아래를 확인하고 서명하면 W4 마감.

### Step 9 — prod + 승인 게이트 (FR-401~404)

- [ ] FR-401: `apps/{app}/overlays/prod/` 5종 + `applicationset-prod.yaml` automated 없음(수동 게이트) — 2026-06-01 라이브
- [ ] FR-402: prod sync 권한 분리(`role:prod-deployer`/`gitops-admin`) — rbac can 평가
- [ ] FR-403: PR-merge → staging auto → prod 수동 승인 흐름 — 라이브 OutOfSync→수동 sync
- [ ] FR-404: 첫 prod 배포 **5/5 Healthy** — 2026-06-01 synapse-prod 15/15 파드
- [ ] 워크어라운드 2건 인지: prod 스키마 시드(Hibernate validate), db.t3.small 연결 한계로 데모 시 dev/staging 축소 (런북: `w4-prod-live-reproduction-runbook.md`)
- 잔존 이월(서명 무관): 실 도메인 3항목 → #121 윈도우 2

### Step 10 — 롤백/백업 (FR-405~408)

- [ ] FR-405: ArgoCD History rollback — prod engagement-svc 1-step → Healthy (2026-06-01)
- [ ] FR-406: git revert — PR #80(DEBUG)→PR #81(revert)→INFO 복원 (2026-06-01)
- [ ] FR-407: Velero S3+IRSA 일일 백업 Completed (PR #75)
- [ ] FR-408: 격리 ns 삭제 → velero restore 복구 시뮬 통과

> 체크 완료 = D-043 해소. 미진 항목 발견 시 해당 런북으로 재현 후 재검토.

## 6. 정합 액션 (실제 수정)

1. **`TASK_gitops.md` 2곳 편집**
   - W3 Step 7 Status(라인 ~152): #92 이중원인·PR #136 gitops 층 해소·윈도우 2 재검증으로 갱신 + 날짜 주석.
   - W4→W5 윈도우 #92 항목(라인 ~234): "application-staging.yml main 미머지" → "main 머지 확인 + staging 오버레이 DB_URL 주입(PR #136), 잔여=재빌드·라이브"로 갱신.
2. **#92 이슈 정합 코멘트** — §3 이중원인 타임라인 + 현재 해소 상태 + 잔여(재빌드/라이브) + §4 신규 발견. **OPEN 유지**(라이브 재검증 = 윈도우 2 소관).
3. 본 감사 문서 커밋.

## 7. 산출물 요약

- **문서:** 본 감사 스펙(`docs/superpowers/specs/2026-06-08-w3-w4-incomplete-audit-design.md`)
- **편집:** `TASK_gitops.md`(W3 Step 7 Status, W4 윈도우 #92 항목)
- **이슈:** #92 정합 코멘트(OPEN 유지)
- **후속:** 하위프로젝트 B(포털 핸드오프 허브 뷰) 별도 brainstorming
