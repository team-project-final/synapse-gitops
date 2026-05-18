# Runbook: W4 Prod 환경 승인 게이트 + 롤백/백업 실행 가이드

> **대상**: gitops 트랙 담당자 (@VelkaressiaBlutkrone) 또는 prod 배포 및 DR 담당자
> **소요 시간**: 약 4일 (2026-06-01 ~ 2026-06-05, 6/3 지방선거 제외)
> **전제**: W3 완료 (staging overlay 10 Application + Observability 스택 Prometheus/Grafana/Loki 동작 확인)
>
> 이전 단계: W3 staging + observability runbook 완료 상태

---

## 0. 준비물 체크리스트

- [ ] W3 runbook 완료 확인: `argocd app list`에 10개 `synapse-*-{dev,staging}` Application 표시
- [ ] `kubectl` — EKS 클러스터 연결 확인 (`kubectl get nodes` → Ready)
- [ ] `argocd` CLI — 로그인 상태 (`argocd account get-user-info`)
- [ ] `helm` v3 — Velero 설치용
- [ ] `velero` CLI — 백업/복구 CLI ([설치 가이드](https://velero.io/docs/v1.13/basic-install/))
- [ ] `aws` CLI — S3/IAM/EKS 접근 가능
- [ ] Prometheus + Grafana 접속 가능 (W3에서 설치한 Observability 스택)
- [ ] `gh` CLI 로그인 + 레포 push 권한
- [ ] 작업 디렉토리: `synapse-gitops` 레포 루트, main 최신 sync (`git pull origin main`)

도구 부재 시:
```bash
# macOS
brew install velero
# Windows
choco install velero
# Linux — https://github.com/vmware-tanzu/velero/releases
```

---

## 일정 개요

| 날짜 | 작업 | 소요 |
|---|---|---|
| 06-01 (월) | Step 9 전반: prod overlay + AppProject + RBAC | 1일 |
| 06-02 (화) | Step 9 후반: ApplicationSet 확장 + 권한 검증 + 문서화 | 1일 |
| 06-03 (수) | **지방선거 공휴일 — 작업 없음** | - |
| 06-04 (목) | Step 10 전반: ArgoCD 롤백 검증 + Velero 설치 | 1일 |
| 06-05 (금) | Step 10 후반: 백업 스케줄 + 복구 시뮬 + 모니터링 | 1일 |

---

## Step 9. Prod 환경 + 승인 게이트 (2일)

prod overlay를 작성하고, ArgoCD Manual Sync 기반 승인 게이트를 구성한다. 권한 분리(RBAC)로 비권한 사용자의 prod sync를 차단한다.

📖 **[step9-prod-approval.md](./step9-prod-approval.md)** — 9-A 사전 분석 / 9-B prod overlay 작성 / 9-C AppProject + RBAC / 9-D ApplicationSet 확장 / 9-E 권한 검증 / 9-F 문서화. 트러블슈팅 4건.

요약:
1. prod 네임스페이스 분리 (별도 namespace 추천, 별도 클러스터는 비용상 후순위)
2. 5개 앱 `apps/{app}/overlays/prod/` 작성 (replicas=3, 운영급 리소스, TLS Ingress)
3. ArgoCD AppProject `synapse-prod` — syncPolicy 없음 (manual only)
4. ApplicationSet matrix: 5앱 x 3환경 = 15 Application
5. RBAC 검증 + dev→staging(auto)→prod(manual) 전체 파이프라인 시뮬레이션

검증:
```bash
argocd app list                    # 15개 Application (5 dev + 5 staging + 5 prod)
argocd proj get synapse-prod       # syncWindows, destinations, roles 확인
```

---

## Step 10. 롤백 + 백업 체계 (2일)

Velero를 설치하고 일일 백업 스케줄을 구성한다. staging에서 복구 시뮬레이션을 실행해 RTO/RPO 목표를 검증한다.

📖 **[step10-rollback-backup.md](./step10-rollback-backup.md)** — 10-A 사전 분석 / 10-B ArgoCD 롤백 검증 / 10-C Velero 설치 / 10-D 백업 스케줄 + 복구 시뮬 / 10-E 백업 모니터링 + 문서화. 트러블슈팅 5건.

요약:
1. 롤백 시나리오 분류 (매니페스트 / 이미지 태그 / 클러스터 전체)
2. ArgoCD History 기반 롤백 + git revert 기반 롤백 검증
3. Velero + AWS plugin (S3 + EBS snapshot) 설치
4. 일일 Schedule 백업 + staging 삭제 → 복구 시뮬레이션 (RTO 30분 이내)
5. 백업 실패 알람 (PrometheusRule)

검증:
```bash
velero backup get               # 최소 1개 Completed
velero schedule get              # daily-backup 존재
kubectl get pods -n staging      # 복구 후 5개 pod Running
```

---

## 검증 체크리스트 (Done 표시용)

- [ ] **FR-GO-401**: `argocd app list` → 15개 앱 (5앱 x 3환경) (P0)
- [ ] **FR-GO-402**: prod Application `Sync Policy: <none>` (Manual) (P0)
- [ ] **FR-GO-403**: 비권한 계정 prod sync RBAC 거부 (P0)
- [ ] **FR-GO-404**: 권한 계정(`gitops-admin`) prod sync 성공 (P0)
- [ ] **FR-GO-405**: `velero backup get` → 최소 1개 `Completed` (P0)
- [ ] **FR-GO-406**: staging 삭제 → Velero restore → 5개 앱 복구, RTO 30분 이내 (P1)
- [ ] **FR-GO-407**: `velero schedule get` → daily-backup 동작 확인 (P1)
- [ ] **FR-GO-408**: Grafana에서 Velero 백업 실패 알람 rule 확인 (P2)

---

## 트러블슈팅 (공통)

### ArgoCD prod sync가 자동으로 실행됨
ApplicationSet 템플릿에서 prod 조건 분기 확인. `argocd app get synapse-*-prod -o json | jq '.spec.syncPolicy'` → `null`이어야 함.

### Velero 백업이 PartiallyFailed
`velero backup logs <name>`으로 상세 확인. IRSA 미설정이 가장 흔한 원인. `kubectl get sa velero -n velero -o yaml`에서 role-arn annotation 확인.

### kubectl 연결 끊김
`aws eks update-kubeconfig --name synapse-dev --region ap-northeast-2` 재실행.

---

## 도움 요청

- HISTORY에 "도움 요청" 기록 + Slack #synapse-gitops
- ArgoCD RBAC: https://argo-cd.readthedocs.io/en/stable/operator-manual/rbac/
- Velero: https://velero.io/docs/
