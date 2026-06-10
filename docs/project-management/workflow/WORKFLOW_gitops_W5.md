# WORKFLOW: @VelkaressiaBlutkrone — Week 5

> **Task 문서**: [TASK_gitops.md](../task/TASK_gitops.md)
> **기간**: 2026-06-08 ~ 2026-06-12, 5 영업일
> **주제**: Runbook + 장애 시나리오 검증 + Cost 최적화 + 안정화

---

## Step 11: Runbook + 장애 시나리오

### 1.1 사전 분석
- [x] 자주 발생할 장애 유형 도출 (Pod CrashLoop, OOM, sync 실패, 인증서 만료, DB 연결 실패)
- [x] 각 장애의 신호(symptom) → 원인(cause) → 조치(action) 매핑
- [x] On-call 로테이션 합의 (W5 이후 운영)
- [x] 에스컬레이션 기준 (level 1 / 2 / 3)
- [x] PR 영향 범위(diff) 코멘트 도구 후보 비교 (Atlantis, kustomize-diff GH action) — W1 Step 3.1에서 이월 (D-041, 선택)
- [x] PR diff 코멘트 GitHub Action 도입 — W1 Step 3.2에서 이월 (D-041, 선택) <!-- 기구현: validate-manifests.yml diff-comment job(47a7c67) -->

### 1.2 Runbook 작성
- [x] docs/runbook/pod-crashloop.md <!-- docs/runbooks/incidents/pod-crashloop.md -->
- [x] docs/runbook/oom-killed.md
- [x] docs/runbook/argocd-sync-failed.md
- [x] docs/runbook/cert-expired.md
- [x] docs/runbook/db-connection-failed.md
- [x] 각 문서: 진단 명령 + 단계별 조치 + 회피 방법 + 사후 점검

### 1.3 시뮬레이션 + 검증
- [x] staging에서 Pod 강제 kill → Runbook 따라 복구 <!-- 2026-06-08 윈도우2 incident-sim crashloop 재현·복구 -->
- [x] staging에서 메모리 limit 일부러 낮춰 OOM 유발 → 복구
- [x] staging에서 ArgoCD sync 실패 유도 (잘못된 manifest) → 복구
- [x] team-lead가 Runbook만 보고 1회 처리 가능한지 확인 <!-- 2026-06-09 #155 operator 드릴로 충족 -->

### 1.4 On-call 체계 + 문서화
- [x] On-call 연락처 + Slack 채널 정리
- [x] 알람 → On-call 전달 경로 확인 (PagerDuty 또는 Slack) <!-- amtool→route slack #synapse-gitops 검증 -->
- [x] 야간/주말 에스컬레이션 정책
- [x] Runbook 위치 README 링크

**Step 11 Status**: [x] Done (런북 5종 + 윈도우2 라이브 시뮬 3종·알람 검증 + #155 operator 드릴로 따라하기 충족 — 2026-06-09)

---

## Step 12: Cost 최적화 + 안정화

### 1.1 사전 분석
- [ ] AWS Cost Explorer 태그 정책 확인 (Project=synapse, Environment=dev/staging/prod)
- [ ] 현재 비용 분포 측정 (EC2/EBS/네트워크/Secrets Manager 등)
- [ ] 5개 앱 P95 메모리/CPU 사용량 측정 (Prometheus) <!-- 라이브 메트릭 윈도우 위임 -->
- [ ] 미사용 리소스 식별 (orphan LoadBalancer, unattached EBS, idle Pod)

### 1.2 리소스 적정화
- [ ] resources.requests/limits 적정값으로 5개 앱 조정 <!-- 정적 리뷰 완료(resource-sizing-review-w5.md), P95 튜닝 윈도우 위임 -->
- [x] HPA 정의 (CPU 또는 메모리 기반, 트래픽 변동 큰 2개 앱) <!-- 2026-06-08 윈도우2: engagement HPA min3→max6 스케일아웃/인 관찰 -->
- [ ] PDB 정의 (prod 환경 최소 가용성)
- [ ] 미사용 리소스 정리

### 1.3 안정화 + 회귀 검증
- [x] W1~W4 잔여 P1 이슈 목록 점검 + 처리 <!-- OPEN 이슈 0건(2026-06-09) -->
- [x] 전체 환경 (dev/staging/prod) 헬스체크 통과 확인 <!-- dev 16/0/0·staging 20/0/0 ALL PASSED -->
- [x] CI/CD 평균 실행 시간 점검 (회귀 없는지)
- [ ] 알람 false-positive 비율 점검 + 룰 조정
- [x] kustomize build 결과 캐싱 (CI 속도 개선) — W1 Step 3.2에서 이월 (D-041, 선택) <!-- build sub-second라 kubeconform+pip 캐싱으로 대체 -->

### 1.4 핸드오프 + 종료
- [x] 핸드오프 문서 최종 검토 (KICKOFF, TASK, Runbook, README) <!-- 2026-06-10 일정문서 4종 동기화 -->
- [ ] 운영 인수자 또는 후속 담당자에게 트랜지션 미팅
- [ ] HISTORY에 5주차 회고 기록 (잘된 점, 아쉬운 점, 다음 사이클 권고)
- [ ] team-lead 사인오프

**Step 12 Status**: [ ] Not Started / [x] In Progress / [ ] Done (HPA·P1 0건·CI캐싱·핸드오프검토 완료. 비용 가시성·P95 튜닝·team-lead 사인오프 잔여 — 2026-06-10)
