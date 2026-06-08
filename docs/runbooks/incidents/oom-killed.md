# Incident: OOMKilled

> 대상 환경: synapse-dev / synapse-staging / synapse-prod (EKS)
> 배경: W4에서 리소스 한도 기반 환경 운영 학습 (노드 t3.large×4 증설 이력)

## 증상

- Pod 재시작 반복 + `kubectl describe pod` 의 Last State: `Terminated, Reason: OOMKilled, Exit Code: 137`
- 메모리 사용량이 limit 근접 후 급락하는 그래프 반복 (Grafana)

## 진단

```bash
# 1. OOMKilled 대상 식별
kubectl get pods -n <ns> -o json | jq -r '.items[] | select(.status.containerStatuses[]?.lastState.terminated.reason=="OOMKilled") | .metadata.name'
# 2. 현재 사용량 vs limit
kubectl top pods -n <ns>
kubectl get deploy <svc> -n <ns> -o jsonpath='{.spec.template.spec.containers[0].resources}'
# 3. 추세 확인 — Grafana "Synapse 개요" 대시보드 메모리 패널에서 P95 확인
```

- Java 서비스(5svc + gateway)는 힙 외 메모리(metaspace/direct buffer) 포함해 limit을 초과할 수 있음 — JVM 옵션(`-XX:MaxRAMPercentage`) 확인.
- 기동 직후 OOM이면 limit 절대 부족, 장시간 후 OOM이면 릭 의심.

## 조치

**limit 상향은 반드시 git 경유** — dev/staging은 selfHeal이라 `kubectl patch`가 즉시 원복된다 (긴급 패치 불가, sim 환경 제외).

1. `apps/<svc>/overlays/<env>/kustomization.yaml` 의 리소스 패치에서 `resources.limits.memory`를 **P95 × 1.3** 으로 상향
2. PR → CI(렌더 diff 코멘트로 변경 확인) → 머지 → dev/staging auto sync (prod 수동 sync)
3. 복구 확인: `kubectl top pods -n <ns>` 사용량/limit 비율 < 0.8

장시간 후 재발(릭 의심)이면 limit 상향은 임시조치 — 힙덤프와 함께 서비스 레포로 이관.

## 에스컬레이션 기준

- limit 상향 후에도 24h 내 재발 → L2 + 해당 서비스 레포 이슈 (메모리 릭 조사)
- 동일 시간대 다중 서비스 OOM (노드 메모리 압박 의심) → **즉시 L2**, 노드 capacity 검토 (W3 A3 이력: 노드 3→4 증설)

## 회피 방법

- Step 12 "Resource request/limit 적정성 리뷰"에서 전 svc P95 기준 재산정
- Grafana 메모리 패널 + Alertmanager 메모리 사용률 알람 (PrometheusRule)

## 사후 점검

- [ ] 변경한 limit 값과 근거(P95)를 PR 본문에 기록
- [ ] `troubleshooting-infra.md` Discovery Log 추가 (신규 패턴인 경우)
- [ ] 동일 svc의 다른 환경(staging/prod) limit도 함께 점검
