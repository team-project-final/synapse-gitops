# Incident: Pod CrashLoopBackOff

> 대상 환경: synapse-dev / synapse-staging / synapse-prod (EKS)
> 관련 실사례: T-050, T-051, T-052, T-054, T-055, T-056, T-057, T-072 (`docs/runbooks/troubleshooting-infra.md`)

## 증상

- `kubectl get pods -n <ns>` 에서 STATUS `CrashLoopBackOff`, RESTARTS 증가
- ArgoCD UI에서 해당 App `Degraded` (Synced 상태여도 발생 — T-053)
- Alertmanager → `#synapse-gitops` 에 KubePodCrashLooping 계열 알람

## 진단

실행 전 컨텍스트 확인: `kubectl config current-context`

```bash
# 1. 대상 식별
kubectl get pods -n <ns> | grep -v Running
# 2. 이벤트·종료 사유
kubectl describe pod <pod> -n <ns>          # Events, Last State, Exit Code
# 3. 직전 컨테이너 로그 (핵심)
kubectl logs <pod> -n <ns> --previous --tail=100
```

로그 에러를 **프로젝트 빈발 원인 체크리스트** 순으로 대조:

| # | 로그 패턴 | 원인 (실사례) | 확인 명령 |
|---|---|---|---|
| 1 | `Could not resolve placeholder '<KEY>'` | ExternalSecret 미동기화 / SM 키 부재 (T-030/031/054) | `kubectl get externalsecret -n <ns>` → SecretSynced 아닌 항목 |
| 2 | `missing table` / `missing column` / Flyway 에러 | DB 스키마 미시드 — prod는 Hibernate validate (T-050/056, D-024) | 해당 svc Flyway 이력·DB 스키마 확인 |
| 3 | `AES secret key must be 32 bytes` | SM 시크릿 형식 오류 (T-055, D-030) | SM 값이 Base64 32B인지 |
| 4 | 기동은 되나 probe 실패 반복 | 포트 불일치 (T-051) 또는 probe 타이밍 (T-052, D-028) | containerPort vs probe port vs Service targetPort; initialDelay |
| 5 | 정상 로그인데 구버전 동작 | 구 이미지 캐시 (T-057/072) | Pod imageID(digest) vs ECR 최신 digest |

> local-k8s(minikube)는 별도: kafka `enableServiceLinks`, 이미지 로드 이슈 — `local-k8s/README.md` 참조.

## 조치

1. 원인 특정 후 **수정은 git 경유** (dev/staging은 selfHeal — kubectl 수정 즉시 원복됨):
   - 매니페스트 원인 → `apps/<svc>/overlays/<env>/` 수정 → PR → 머지 → auto sync (prod는 수동 sync)
   - SM 시크릿 원인 → AWS SM 값 수정 → ExternalSecret 강제 갱신:
     ```bash
     kubectl annotate externalsecret <name> -n <ns> force-sync="$(date +%s)" --overwrite
     kubectl rollout restart deploy/<svc> -n <ns>
     ```
   - 서비스 코드/스키마 원인 → 해당 서비스 레포에 이슈 이관 (`synapse-<svc>` 레포)
2. 복구 확인: `kubectl get pods -n <ns> -w` → Running + READY, ArgoCD Healthy

## 에스컬레이션 기준

- L1 30분 내 원인 미특정 → L2 (team-lead)
- 다중 서비스 동시 CrashLoop (인프라 공통 원인 의심: ESO/DB/MSK) → **즉시 L2**
- 서비스 코드 원인 → 해당 서비스 레포 이슈 + 서비스 담당 멘션

## 회피 방법

- PR 단계에서 kubeconform/yamllint/렌더 diff CI가 매니페스트 오류 차단 (`validate-manifests.yml`)
- 신규 svc 온보딩 시 `docs/runbooks/frontend-deploy-prereqs.md` 선행조건 체크 (ECR·SM 시드)
- probe 설정은 Spring 기동 시간 반영 (D-028: initialDelaySeconds/startupProbe)

## 사후 점검

- [ ] 새 원인이면 `troubleshooting-infra.md` Discovery Log에 T-항목 추가
- [ ] 재발성 원인이면 본 런북 체크리스트에 행 추가
- [ ] 해당 환경 fleet 전체 Healthy 재확인
