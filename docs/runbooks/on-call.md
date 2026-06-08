# On-call 체계 (gitops 트랙)

> 실제 팀 구성(트랙 1인 + team-lead) 기준 2레벨 간소화 — 2026-06-08 설계 결정.
> 알람 경로: Alertmanager → Slack `#synapse-gitops` (W3 Step 8에서 실 webhook 검증 완료)

## 에스컬레이션 레벨

| 레벨 | 담당 | 조건 | 응답 SLA | 해결 SLA |
|---|---|---|---|---|
| L1 | gitops 트랙 담당 (@VelkaressiaBlutkrone) | 알람 발생 / 이슈 접수 | 5분 (업무시간) | 30분 시도 후 판단 |
| L2 | team-lead | L1 30분 미해결 · 다중 서비스 영향 · 비용/사이징 결정 필요 | 10분 | 2시간 |

**즉시 L2 조건** (L1 시도 생략):
- 전 서비스 동시 장애 (DB/ESO/ArgoCD 컨트롤러 등 공통 인프라)
- prod 환경 장애
- 비용 결정이 필요한 조치 (인스턴스 증설, 노드 증설)

## 채널

| 용도 | 채널 |
|---|---|
| 알람 수신·1차 소통 | Slack `#synapse-gitops` |
| 장애 기록·서비스팀 이관 | GitHub 이슈 (`synapse-gitops`, 서비스 원인은 해당 `synapse-<svc>` 레포) |
| 크로스 트랙 통보 | `synapse-shared` 이슈 허브 (예: shared#20 패턴) |

## 야간/주말 정책

| 시간대 | 정책 |
|---|---|
| 평일 09:00–18:00 | L1 즉시 대응 |
| 평일 야간 | critical만 대응, warning은 다음 영업일 |
| 주말/공휴일 | critical만 대응 (L2 직행 가능) |

> critical = prod 장애·전 서비스 영향. 그 외는 warning으로 간주.
> 야간·주말 critical은 L1 단계를 생략하고 **즉시 L2 직행**한다(위 "즉시 L2 조건"과 동일).

## 장애 유형 → 런북 인덱스

| 증상 | 런북 |
|---|---|
| Pod 재시작 반복 (CrashLoopBackOff) | [incidents/pod-crashloop.md](./incidents/pod-crashloop.md) |
| OOMKilled (Exit 137) | [incidents/oom-killed.md](./incidents/oom-killed.md) |
| OutOfSync 지속·sync Failed | [incidents/argocd-sync-failed.md](./incidents/argocd-sync-failed.md) |
| 인증서 만료·TLS 오류 | [incidents/cert-expired.md](./incidents/cert-expired.md) |
| DB connection refused/timeout | [incidents/db-connection-failed.md](./incidents/db-connection-failed.md) |
| 그 외 인프라 이슈 | [troubleshooting-infra.md](./troubleshooting-infra.md) (T-카탈로그) |

## 알람 경로 테스트 — ⚠️ 윈도우 실행 항목 (클러스터 필요)

```bash
# Alertmanager pod명 확인 (릴리스명에 따라 다름)
kubectl get pods -n monitoring | grep alertmanager
# 테스트 알람 주입 — severity=warning 사용 (실 on-call 소음 방지)
kubectl exec -n monitoring <alertmanager-pod> -- amtool alert add \
  alertname=OncallPathTest severity=warning namespace=synapse-staging \
  --annotation=summary="on-call 경로 테스트 (무시 가능)" \
  --alertmanager.url=http://localhost:9093
# → Slack #synapse-gitops 수신 확인 (W5_WINDOW_2.md Phase 5)
```

## 사후 (포스트모템) 규칙

- 30분 이상 장애·prod 장애는 GitHub 이슈에 타임라인 기록 (감지→진단→조치→복구 시각)
- 신규 원인은 `troubleshooting-infra.md` Discovery Log에 T-항목 추가
- 런북이 부족했다면 해당 incidents 문서를 같은 PR에서 보강
