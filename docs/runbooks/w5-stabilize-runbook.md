# Runbook: W5 안정화 + 운영 Runbook + 프로젝트 종료 실행 가이드

> **대상**: gitops 트랙 담당자 (@VelkaressiaBlutkrone) 또는 운영 인수자
> **소요 시간**: 약 5일 (2026-06-08 ~ 2026-06-12)
> **전제**: W4 완료 (prod overlay 15 Applications 배포, Manual Sync + RBAC, Velero 백업, 롤백 검증)
>
> 이전 단계: W4 runbook 완료 — prod 5개 앱 Synced + Healthy, 백업/복원 1회 이상 성공

---

## 0. 준비물 체크리스트

- [ ] W4 완료 확인: `argocd app list`에 15개 Application (5앱 × 3환경)
- [ ] `kubectl` — 3개 환경 클러스터 연결 (`kubectl get nodes --context <env>` → Ready)
- [ ] `argocd` CLI — 로그인 상태 (`argocd account get-user-info`)
- [ ] `aws` CLI — Cost Explorer, EKS, CloudWatch 접근 가능
- [ ] Grafana/Prometheus 접속 확인
- [ ] `velero` CLI — 백업 상태 확인 (`velero backup get`)
- [ ] Slack #synapse-oncall 채널 접근 권한
- [ ] 작업 디렉토리: `synapse-gitops` 레포 루트, main 최신 sync

도구 부재 시:
```bash
brew install velero awscli kubectl argocd          # macOS
choco install velero awscli kubernetes-cli argocd-cli  # Windows
```

---

## Step 11. 장애 Runbook + 시뮬레이션 (2일)

장애 유형별 Runbook을 작성하고, staging에서 시뮬레이션 후 team-lead 독립 처리를 검증한다.

📖 **[step11-operational-runbook.md](./step11-operational-runbook.md)** — 11-A 장애 유형 도출 / 11-B Runbook 작성 / 11-C 시뮬레이션 / 11-D On-call 체계. 트러블슈팅 3건.

요약:
1. 5개 장애 시나리오 확정 (CrashLoopBackOff, OOM Killed, ArgoCD sync 실패, TLS 인증서 만료, DB 연결 실패)
2. `docs/runbooks/incidents/` 하위에 시나리오별 독립 문서 작성
3. staging에서 3개 시나리오 시뮬레이션 + Runbook 따라 복구
4. team-lead 1회 독립 처리 통과, On-call 체계 정리

검증:
```bash
ls docs/runbooks/incidents/
# pod-crashloop.md  oom-killed.md  argocd-sync-failed.md  cert-expired.md  db-connection-failed.md
kubectl get pods -n staging   # 시뮬레이션 후 원복 확인 — 5개 pod Running
```

---

## Step 12. 비용 최적화 + 안정화 + 핸드오프 (2일)

비용 가시성 확보, HPA/PDB 적용, 잔여 이슈 정리, 운영 인수자 핸드오프.

📖 **[step12-cost-optimization.md](./step12-cost-optimization.md)** — 12-A 비용 가시성 / 12-B 리소스 적정화 / 12-C 안정화 + 회귀 검증 / 12-D 핸드오프 + 종료. 트러블슈팅 4건.

요약:
1. AWS Cost Explorer 태그 정책 확인 + 미적용 자원 태깅
2. Prometheus P95 기반 requests/limits 조정, HPA(platform-svc, engagement-svc), PDB(prod minAvailable:2)
3. W1~W4 잔여 P0/P1 이슈 0건, 전체 환경 헬스체크
4. 핸드오프 문서 검토, 트랜지션 미팅, team-lead 사인오프

검증:
```bash
kubectl get hpa -n prod        # platform-svc, engagement-svc HPA 정상
kubectl get pdb -n prod        # 5개 앱 PDB 표시
for env in dev staging prod; do argocd app list -l environment=$env; done  # 15개 Synced+Healthy
```

---

## 검증 체크리스트

- [ ] 장애 Runbook 5개 작성: `docs/runbooks/incidents/` 하위 5개 파일
- [ ] team-lead Runbook 따라하기 1회 통과
- [ ] On-call 체계 문서화 (연락처, 에스컬레이션, 야간/주말 정책)
- [ ] AWS Cost Explorer 태그 적용: 미태깅 자원 0건
- [ ] HPA 정상 동작 (platform-svc, engagement-svc)
- [ ] PDB 적용 (prod minAvailable: 2)
- [ ] P0/P1 이슈 0건
- [ ] 15개 Application Synced + Healthy
- [ ] 핸드오프 문서 검토 + team-lead 사인오프 완료

---

## 프로젝트 완료 체크리스트

5주간 GitOps 프로젝트 전체 완료 확인:

**인프라 (W1)**: EKS Running, ArgoCD HA, CI 파이프라인 (kubeconform + kustomize build)
**배포 (W2~W3)**: 15 Applications (5앱×3환경), ESO 시크릿 관리, Image Updater
**운영 (W4)**: prod Manual Sync + RBAC, Velero 백업/복원, 롤백 검증
**안정화 (W5)**: 장애 Runbook 5개, On-call 체계, HPA/PDB, 핸드오프

문서 완비:
- [ ] KICKOFF.md, TASK.md, SCOPE.md, HISTORY.md, README.md
- [ ] Runbook: W1~W5 parent + step 상세 + 장애 Runbook 5개

---

## 트러블슈팅

### W4 완료 상태가 불완전
```bash
argocd app list -l environment=prod   # 5개 Synced+Healthy
velero backup get                      # 최근 백업 Completed
```

### Grafana/Prometheus 접속 불가
```bash
kubectl port-forward svc/prometheus-server 9090:9090 -n monitoring
kubectl port-forward svc/grafana 3000:3000 -n monitoring
```

### staging 시뮬레이션 후 원복 누락
```bash
argocd app sync synapse-platform-svc-staging --force
argocd app sync synapse-engagement-svc-staging --force
kubectl get pods -n staging   # 모든 pod Running+Ready
```

---

## 도움 요청

- Slack #synapse-gitops 채널 + HISTORY에 "도움 요청" 기록
- ArgoCD: https://argo-cd.readthedocs.io/
- AWS Cost Explorer: https://docs.aws.amazon.com/cost-management/latest/userguide/
- Velero: https://velero.io/docs/
