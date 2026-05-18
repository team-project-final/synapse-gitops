# Runbook: 장애 Runbook 작성 + 시뮬레이션 + On-call 체계 (Step 11 상세)

> **소요 시간**: 2일 (약 7.5시간 실작업)
> **결과**: 장애 Runbook 5개 작성, team-lead 따라하기 1회 통과, On-call 체계 정리
> **상위 문서**: [w5-stabilize-runbook.md](./w5-stabilize-runbook.md) Step 11
> **사전 조건**: W4 완료 (prod 15 Applications + Velero 백업 + 롤백 검증), staging 정상 가동

---

## 11-A. 장애 유형 도출 (30분)

5개 장애 시나리오를 확정하고 symptom → cause → action 매핑을 정리한다.

| # | 장애 유형 | Symptom | Cause | Action |
|---|---|---|---|---|
| 1 | Pod CrashLoopBackOff | Pod 재시작 반복, BackOff 상태 | 앱 시작 실패, 설정 오류 | 로그 확인 → 원인 수정 → 재배포 |
| 2 | OOM Killed | Pod 재시작 + reason: OOMKilled | 메모리 limit 초과 | limit 상향 또는 앱 최적화 |
| 3 | ArgoCD Sync 실패 | OutOfSync + SyncFailed | 잘못된 manifest, RBAC 거부 | manifest 수정 → 재sync |
| 4 | TLS 인증서 만료 | HTTPS 인증서 오류, 502 | cert-manager 갱신 실패 | 인증서 재발급/수동 갱신 |
| 5 | DB 연결 실패 | connection refused/timeout | SG 차단, 엔드포인트 변경, 시크릿 불일치 | 네트워크+시크릿 점검 |

**Expected**: 5개 시나리오 목록이 팀 합의로 확정됨.

---

## 11-B. Runbook 작성 (4시간)

`docs/runbooks/incidents/` 하위에 5개 독립 문서를 작성한다.

```bash
mkdir -p docs/runbooks/incidents
```

### 작성 파일 및 핵심 진단 명령

**1. pod-crashloop.md** — Pod CrashLoopBackOff
```bash
kubectl get pods -n <namespace> | grep CrashLoopBackOff
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --previous
```
조치: `--previous` 로그 에러 확인 → ConfigMap/Secret 마운트 점검 → probe 설정 점검 → 이미지 태그 확인 → 수정 후 ArgoCD sync

**2. oom-killed.md** — OOM Killed
```bash
kubectl get pods -n <namespace> -o json | jq '.items[] | select(.status.containerStatuses[]?.lastState.terminated.reason=="OOMKilled") | .metadata.name'
kubectl top pods -n <namespace>
```
조치: P95 메모리 확인 → `resources.limits.memory`를 P95×1.3으로 상향 → overlay 패치 → git push → sync

**3. argocd-sync-failed.md** — ArgoCD Sync 실패
```bash
argocd app list | grep -v Synced
argocd app get <app-name> --show-operation
argocd app diff <app-name>
```
조치: 에러 메시지 확인 → `kustomize build` 로컬 검증 → AppProject sourceRepos/destinations 점검 → 수정 후 `argocd app sync`

**4. cert-expired.md** — TLS 인증서 만료
```bash
kubectl get cert -n <namespace> -o wide
kubectl logs -n cert-manager deploy/cert-manager -f
openssl s_client -connect <domain>:443 2>/dev/null | openssl x509 -noout -dates
```
조치: Certificate Ready 상태 확인 → DNS 검증/Rate limit 점검 → 필요 시 `kubectl delete cert` 후 재생성 대기

**5. db-connection-failed.md** — DB 연결 실패
```bash
kubectl logs deploy/<app> -n <namespace> | grep -i "connection\|refused\|timeout"
aws rds describe-db-instances --query 'DBInstances[?DBInstanceIdentifier==`synapse-<env>`].Endpoint'
```
조치: RDS 상태 확인(available) → Security Group 인바운드 점검 → Secret vs 실제 엔드포인트 비교 → ESO ExternalSecret 상태 확인

### 각 문서 필수 섹션

모든 장애 Runbook: `## 증상` → `## 진단` → `## 조치` → `## 회피 방법` → `## 사후 점검`

### 검증
```bash
ls -la docs/runbooks/incidents/   # 5개 파일 존재
for f in docs/runbooks/incidents/*.md; do
  echo "=== $f ===" && grep -c "## 증상\|## 진단\|## 조치" "$f"
done   # 각 파일 3 이상
```

---

## 11-C. 시뮬레이션 (2시간)

staging에서 3개 시나리오를 재현하고 Runbook 따라 복구한다.

### 사전 준비
```bash
kubectl get pods -n staging -o wide > /tmp/staging-pods-before.txt
argocd app list -l environment=staging > /tmp/staging-apps-before.txt
```

### 시나리오 1: CrashLoopBackOff

```bash
# 환경변수를 잘못 설정해 시작 실패 유도
kubectl set env deploy/platform-svc -n staging STARTUP_FAIL=true
# → pod-crashloop.md 따라 진단 → 원인 확인
kubectl set env deploy/platform-svc -n staging STARTUP_FAIL-   # 원복
```

### 시나리오 2: OOM Killed

```bash
# memory limit 극단적 축소
kubectl patch deploy engagement-svc -n staging --type='json' \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/memory","value":"10Mi"}]'
# → oom-killed.md 따라 진단 → limit 원복
kubectl patch deploy engagement-svc -n staging --type='json' \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/memory","value":"256Mi"}]'
```

### 시나리오 3: ArgoCD Sync 실패

```bash
# 잘못된 패치를 staging overlay에 push
git checkout -b test/sync-failure-simulation
# kustomization.yaml에 존재하지 않는 리소스 참조 추가
git add -A && git commit -m "test: intentional sync failure" && git push -u origin test/sync-failure-simulation
# → argocd-sync-failed.md 따라 진단 → 수정
git checkout main && git push origin --delete test/sync-failure-simulation
```

### team-lead 검증

1. team-lead에게 Runbook 5개 전달
2. 시나리오 1개 선택 → staging 장애 유발
3. team-lead가 Runbook만 보고 독립 복구
4. 1회 통과 = 검증 완료, 실패 시 Runbook 보완 후 재시도

### 시뮬레이션 후 원복

```bash
for app in platform-svc engagement-svc knowledge-svc learning-card learning-ai; do
  argocd app sync "synapse-${app}-staging" --force --prune
done
kubectl get pods -n staging   # 모든 pod Running+Ready
diff /tmp/staging-pods-before.txt <(kubectl get pods -n staging -o wide)
```

---

## 11-D. On-call 체계 (1시간)

### 연락처 + 에스컬레이션

| 레벨 | 조건 | 응답 SLA | 해결 SLA | 채널 |
|---|---|---|---|---|
| L1 | 알람 발생 | 5분 | 30분 시도 | #synapse-oncall |
| L2 | L1 30분 미해결 | 10분 | 2시간 | #synapse-gitops |
| L3 | 서비스 전체 영향 / L2 2시간 초과 | 즉시 | 4시간 | team-lead DM |

### Alertmanager → Slack 경로

```yaml
# alertmanager.yaml 핵심 설정
route:
  receiver: 'slack-oncall'
  routes:
    - match: { severity: critical }
      receiver: 'pagerduty-l2'
    - match: { severity: warning }
      receiver: 'slack-oncall'
receivers:
  - name: 'slack-oncall'
    slack_configs:
      - channel: '#synapse-oncall'
        send_resolved: true
  - name: 'pagerduty-l2'
    pagerduty_configs:
      - service_key: '<PAGERDUTY_SERVICE_KEY>'
```

### 야간/주말 정책

| 시간대 | 정책 |
|---|---|
| 평일 09:00~18:00 | L1 즉시 대응 |
| 평일 야간 | critical만 PagerDuty, warning은 다음 영업일 |
| 주말/공휴일 | critical만 PagerDuty, L2 30분 내 응답 |

### 알람 경로 테스트
```bash
kubectl exec -n monitoring deploy/alertmanager -- amtool alert add \
  alertname="TestAlert" severity="warning" namespace="staging" \
  --annotation.summary="On-call 경로 테스트 (무시 가능)" \
  --end="$(date -u -d '+5 minutes' +%Y-%m-%dT%H:%M:%S.000Z)"
# → #synapse-oncall 수신 확인
```

---

## 자주 막히는 지점

### 시뮬레이션 후 staging 원복 누락

해결: ArgoCD 강제 sync로 git 상태 원복. 시뮬레이션 전/후 스냅샷 비교 필수.

### 알람 경로 테스트 시 실제 On-call 알림

해결: 테스트는 `severity: warning` 사용 (Slack만 전달). PagerDuty 테스트는 웹 콘솔 Test 기능 활용.

### Runbook 명령이 환경에 따라 다름

해결: 모든 kubectl 명령에 `--context <context-name>` 명시. 실행 전 `kubectl config current-context` 확인 습관화.

---

## 다음 단계

→ **[step12-cost-optimization.md](./step12-cost-optimization.md)** (비용 최적화 + 안정화 + 핸드오프)
