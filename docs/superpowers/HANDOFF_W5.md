# W5 핸드오프: synapse-gitops — 윈도우 2(라이브) 이관

> **작성**: 2026-06-08 (W5 Day1) · **대상**: 다음 세션(1회 on-demand EKS 윈도우, 과금)
> **상태 요약**: 비용 0 작업 전부 완료. 남은 건 **라이브 검증/튜닝 + 팀 결정** 뿐.
> **발표**: 2026-06-15 · **정본 허브**: synapse-shared `HANDOFF_HUB.md`(team-lead 유지, 현행)

---

## 1. 이번 세션 완료 사항 (2026-06-08, 비용 0)

- **Step 11 문서**(PR #137): `incidents/` 5종 + `on-call.md` + `W5_WINDOW_2.md`.
- **W3/W4 감사 + 정합**(PR #138/#140/#141): 처분표, #92 이중원인, **#91·#92 라이브 해소 정합·close**.
- **포털 핸드오프 허브 뷰**(PR #139): `/hub` 상태 대시보드(`parse_hub.mjs`→`hub.json`).
- **Step 12 진행분**(PR #142): P0/P1 0건 달성 · CI 캐싱 · resource 정적 리뷰 · HISTORY 최신화 · #126 옵션 분석.

> **#91·#92는 이미 close** — shared HANDOFF_HUB 06-08 라이브(dev 16/0/0·staging 20/0/0 ALL PASSED, gitops#136)로 해소 확인됨. 윈도우 2 대상 아님.

## 2. 다음 세션 시작점 — 클러스터 상태부터 확인

```bash
aws eks describe-cluster --name synapse-dev --query 'cluster.status' --region ap-northeast-2
```
- **ACTIVE면**(06-08 검증 후 유지 중일 수 있음 — HANDOFF_HUB "Day4 후 destroy 판단"): bring-up 생략 가능, 바로 §3 검증 진입. ArgoCD 터널은 `scripts/lib/eks-tunnel.sh`.
- **없으면/destroy됐으면**: `bash scripts/bring-up.sh`로 부트스트랩(`W5_WINDOW_2.md` Phase 1) 후 진입.

## 3. 윈도우 2 작업 항목 (라이브)

> 주 런북: **`docs/runbooks/W5_WINDOW_2.md`**(Phase 0~6). #91/#92(Phase 2)는 close됐으므로 **Phase 3~5 + 추가 항목** 집중.

| # | 항목 | 근거/런북 | Acceptance |
|---|------|----------|-----------|
| 1 | **#121 prod 외부 노출** | `W5_WINDOW_2.md` Phase 3 · nip.io ingress + `gen-nipio-selfsigned.sh` | `curl --cacert` argocd/dev nip.io 200 + 체인 유효 + webhook ping 200 → #121 close |
| 2 | **#122 IU write-back E2E** | `W5_WINDOW_2.md` Phase 4 · `image-updater-pr.yml`(#127 경로) | ECR 재태그 → IU 감지 → PR 자동생성 → 머지 → 반영 ≤5분 + 롤백 1회 → #122 close |
| 3 | **Step 11 시뮬레이션 3종** | `W5_WINDOW_2.md` Phase 5 · 전용 `incident-sim` 앱(ns synapse-sim) | crashloop/oom/sync 재현 → incidents 런북 따라 복구 |
| 4 | **Step 11 team-lead 따라하기** | Phase 5 | team-lead가 런북만 보고 1택 독립 복구 1회 → Step 11 Done |
| 5 | **Step 11 알람 경로 테스트** | Phase 5 · `on-call.md` amtool | amtool warning → Slack `#synapse-gitops` 수신 |
| 6 | **HPA 동작 검증** | prod overlay `hpa.yaml` 5종 존재 · TASK Step 12 | 트래픽 변동 큰 2개 앱 부하 → replica 스케일아웃/인 관찰 |
| 7 | **resource P95 튜닝** | `docs/runbooks/resource-sizing-review-w5.md` | Grafana P95×1.3 측정 → Java 5종 limit(512Mi tight) 재산정 → overlay patch. dev 축소(비용) |
| 8 | **staging 환경 DB 분리** | 감사 `2026-06-08-w3-w4-incomplete-audit-design.md` §4 | staging가 dev RDS·DB(`synapse_platform`) 공유 → 환경 격리(전용 DB/인스턴스). **team-lead 비용 결정 선행** |

## 4. 전제 · 블로커 (라이브 전 처리)

- **클러스터 비용**: 진입 시 과금 ON → 종료 시 `bash scripts/bring-up.sh --destroy`(또는 HANDOFF_HUB Day4 destroy 판단과 조율).
- **#121 ACM import**: IAM 권한 + 리전(ap-northeast-2) 사전 점검(`W5_WINDOW_2.md` Phase 0).
- **#122 GITOPS_TOKEN**: 유효성 점검(PR write-back 필수).
- **항목 7 선결**: Observability(Grafana/Prometheus) 가동 — bring-up `observability` phase 포함. 메트릭 수집 후 P95.
- **항목 8 선결**: **team-lead 비용 결정** — 전용 인스턴스/DB 추가는 사이징·과금 영향. 미결정 시 항목 8 보류.
- **항목 4 의존**: team-lead 가용 시간. 당일 불가 시 시뮬레이션·알람만 완료, 따라하기는 비동기 후속(Step 11 Done은 따라하기 시점).

## 5. 팀 결정 대기 (윈도우 무관)

- **#126 bypass** — `docs/runbooks/126-deploy-writeback-bypass-analysis.md` 권고 옵션3(전용 자동화 ID). org 시크릿·shared 변경 수반이라 단독 불가. 팀 선택 후 실행.

## 6. 레포 상태

- **main HEAD**: `58e459c` (PR #142 머지)
- **OPEN 이슈**: #121·#122(윈도우2) · #126(팀 결정). #91·#92·#120 close.
- **윈도우 2 런북**: `docs/runbooks/W5_WINDOW_2.md`(정본 실행 절차)
- **CI**: main 보호(PR + validate/diff-comment/parse). validate에 kubeconform/pip 캐싱 추가됨(PR #142).
- **포털**: `/hub` 핸드오프 허브 뷰 — deploy-pages 다음 빌드에서 라이브.

## 7. 비용

~$0.41/hr (EKS+RDS+MSK+Redis+ES). 윈도우 종료 시 `bash scripts/bring-up.sh --destroy`. 유지: S3 state + DynamoDB lock. **항목 8(staging DB 분리)은 인스턴스/DB 추가 시 시간당 비용 증가** → team-lead 결정 전 미실행.
