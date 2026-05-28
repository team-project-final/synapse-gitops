# WORKFLOW: @VelkaressiaBlutkrone — Week 5

> **Task 문서**: [TASK_gitops.md](../task/TASK_gitops.md)
> **기간**: 2026-06-08 ~ 2026-06-12, 5 영업일
> **주제**: Runbook + 장애 시나리오 검증 + Cost 최적화 + 안정화

---

## Step 11: Runbook + 장애 시나리오

### 1.1 사전 분석
- [ ] 자주 발생할 장애 유형 도출 (Pod CrashLoop, OOM, sync 실패, 인증서 만료, DB 연결 실패)
- [ ] 각 장애의 신호(symptom) → 원인(cause) → 조치(action) 매핑
- [ ] On-call 로테이션 합의 (W5 이후 운영)
- [ ] 에스컬레이션 기준 (level 1 / 2 / 3)
- [ ] PR 영향 범위(diff) 코멘트 도구 후보 비교 (Atlantis, kustomize-diff GH action) — W1 Step 3.1에서 이월 (D-041, 선택)
- [ ] PR diff 코멘트 GitHub Action 도입 — W1 Step 3.2에서 이월 (D-041, 선택)

### 1.2 Runbook 작성
- [ ] docs/runbook/pod-crashloop.md
- [ ] docs/runbook/oom-killed.md
- [ ] docs/runbook/argocd-sync-failed.md
- [ ] docs/runbook/cert-expired.md
- [ ] docs/runbook/db-connection-failed.md
- [ ] 각 문서: 진단 명령 + 단계별 조치 + 회피 방법 + 사후 점검

### 1.3 시뮬레이션 + 검증
- [ ] staging에서 Pod 강제 kill → Runbook 따라 복구
- [ ] staging에서 메모리 limit 일부러 낮춰 OOM 유발 → 복구
- [ ] staging에서 ArgoCD sync 실패 유도 (잘못된 manifest) → 복구
- [ ] team-lead가 Runbook만 보고 1회 처리 가능한지 확인

### 1.4 On-call 체계 + 문서화
- [ ] On-call 연락처 + Slack 채널 정리
- [ ] 알람 → On-call 전달 경로 확인 (PagerDuty 또는 Slack)
- [ ] 야간/주말 에스컬레이션 정책
- [ ] Runbook 위치 README 링크

**Step 11 Status**: [ ] Not Started / [ ] In Progress / [ ] Done

---

## Step 12: Cost 최적화 + 안정화

### 1.1 사전 분석
- [ ] AWS Cost Explorer 태그 정책 확인 (Project=synapse, Environment=dev/staging/prod)
- [ ] 현재 비용 분포 측정 (EC2/EBS/네트워크/Secrets Manager 등)
- [ ] 5개 앱 P95 메모리/CPU 사용량 측정 (Prometheus)
- [ ] 미사용 리소스 식별 (orphan LoadBalancer, unattached EBS, idle Pod)

### 1.2 리소스 적정화
- [ ] resources.requests/limits 적정값으로 5개 앱 조정
- [ ] HPA 정의 (CPU 또는 메모리 기반, 트래픽 변동 큰 2개 앱)
- [ ] PDB 정의 (prod 환경 최소 가용성)
- [ ] 미사용 리소스 정리

### 1.3 안정화 + 회귀 검증
- [ ] W1~W4 잔여 P1 이슈 목록 점검 + 처리
- [ ] 전체 환경 (dev/staging/prod) 헬스체크 통과 확인
- [ ] CI/CD 평균 실행 시간 점검 (회귀 없는지)
- [ ] 알람 false-positive 비율 점검 + 룰 조정
- [ ] kustomize build 결과 캐싱 (CI 속도 개선) — W1 Step 3.2에서 이월 (D-041, 선택)

### 1.4 핸드오프 + 종료
- [ ] 핸드오프 문서 최종 검토 (KICKOFF, TASK, Runbook, README)
- [ ] 운영 인수자 또는 후속 담당자에게 트랜지션 미팅
- [ ] HISTORY에 5주차 회고 기록 (잘된 점, 아쉬운 점, 다음 사이클 권고)
- [ ] team-lead 사인오프

**Step 12 Status**: [ ] Not Started / [ ] In Progress / [ ] Done
