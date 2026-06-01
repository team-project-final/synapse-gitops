# local-k8s 정리(cleanup) 설계

> **발행일**: 2026-06-01
> **대상**: `local-k8s/` (minikube 로컬 스택) + `apps/*/base` (공유 base)
> **성격**: 품질·일관성 정리 (기능 버그 없음)
> **선행 spec**: [2026-05-26-local-k8s-minikube-design.md](./2026-05-26-local-k8s-minikube-design.md)

## 배경

`local-k8s` 검토 결과 **기능적 결함은 없다**: 정적 렌더 34개 정상, 이미지 transform 전부 `:local`,
kafka(plaintext 9092)·redis·DB 배선이 앱 설정과 일치, 더미 시크릿 커버 정상.
마지막 그린 검증(`6310c97`, `7be0998`) 이후 `apps/*/base` 실질 변화 없음.

다만 품질·일관성 후보 3건을 발견했다. 사용자 승인으로 3건 모두 처리한다.

## 목표

| # | 항목 | 범위 | 리스크 |
|---|---|---|---|
| B | engagement-svc overlay의 미사용 `REDIS_HOST`/`REDIS_PORT` 제거 | local-k8s 내부 | 무위험 |
| C | gateway를 standalone `gateway.yaml` → `apps/gateway/base` 재사용으로 정합 | local-k8s 내부 | 낮음 |
| A | `commonLabels`(deprecated) → `labels:` 전환 | `apps/*/base` 6개 (공유) | 중간 — 검증 필수 |

비목표(YAGNI): infra 매니페스트 영속화·멀티 replica, 신규 서비스 추가, 무관한 리팩터.

## 접근

**원자적 3분할 + 렌더 diff 검증.** B → C → A 순으로 독립 커밋. 각 단계마다 `kubectl kustomize` 렌더를
변경 전/후 diff 하여 의도한 변화만 있는지 증명한다. 단일 일괄 커밋(격리·revert 곤란)과
`kustomize edit fix` 자동 마이그레이션(버전 동작 의존)은 기각.

## 상세 설계

### B — engagement dead config 제거

`local-k8s/apps/engagement-svc/kustomization.yaml`의 ConfigMap 패치에서 다음 2줄 삭제:

```yaml
REDIS_HOST: redis
REDIS_PORT: "6379"
```

근거: `synapse-engagement-svc/src/main/resources/`에 redis 참조 0건 → 해당 키는 어떤 yml도 읽지 않는 dead config.

**검증**: 렌더 diff에 해당 2개 키 제거만 나타날 것.

### C — gateway base 정합

현재 `local-k8s/gateway.yaml`(standalone Deployment+Service)을 다른 5개 앱과 동일한 base-재사용 overlay로 교체.

신규 `local-k8s/apps/gateway/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../../apps/gateway/base
patches:
  - patch: |
      $patch: delete
      apiVersion: external-secrets.io/v1
      kind: ExternalSecret
      metadata:
        name: gateway-external-secret
  - patch: |
      apiVersion: v1
      kind: ConfigMap
      metadata:
        name: gateway-config
      data:
        SPRING_DATA_REDIS_HOST: redis
        SPRING_DATA_REDIS_PORT: "6379"
images:
  - name: ghcr.io/team-project-final/synapse-gateway
    newName: synapse-gateway
    newTag: local
```

부가 변경:
- `local-k8s/secrets.yaml`에 `gateway-secret`(`SPRING_DATA_REDIS_PASSWORD: redis_local`) 추가.
- 최상위 `local-k8s/kustomization.yaml`: `gateway.yaml` 항목을 `apps/gateway`로 교체.
- standalone `local-k8s/gateway.yaml` 삭제.

근거: base `gateway-config`의 라우트 4개(`PLATFORM/ENGAGEMENT/KNOWLEDGE/LEARNING_SVC_URI`)가
standalone과 **완전 동일**. base 채택의 유일한 실질 변화는 liveness probe + resource limits 추가(개선, 허용).

**검증**: 렌더된 gateway Deployment의 env 라우트 4개 동일 + redis 3키 주입 유지, Service `80→8080` 동일,
ExternalSecret 미포함, 전체 리소스 수 34 유지.

**확인됨**: base ExternalSecret name = `gateway-external-secret`, apiVersion = `external-secrets.io/v1` (위 delete 패치에 반영).

### A — commonLabels deprecation 해소

`apps/{engagement-svc,gateway,knowledge-svc,learning-ai,learning-card,platform-svc}/base/kustomization.yaml` 6개:

```yaml
commonLabels:
  app.kubernetes.io/managed-by: kustomize
```
→
```yaml
labels:
  - pairs:
      app.kubernetes.io/managed-by: kustomize
    includeSelectors: true
```

**함정**: `commonLabels`는 라벨을 `metadata.labels`뿐 아니라 **selector·template.labels에도 주입**한다
(렌더 확인: base 파생 Deployment의 `matchLabels`에 `app.kubernetes.io/managed-by: kustomize` 존재).
`includeSelectors: true` 없이 전환하면 selector가 바뀌어 → **live 클러스터(dev/staging/prod, ArgoCD 관리)의
immutable selector 충돌**로 apply/sync 실패. `includeSelectors: true`로 byte-identical 출력 보장.

**검증(필수)**: local-k8s + dev + staging + prod **모든 overlay**의 변경 전/후 `kubectl kustomize` 렌더를
diff → **0 diff**(완전 동일) 확인. selector 보존을 증명하여 live 매니페스트 충돌 없음 보장.

## 검증 전략 (전체)

1. 각 단계 커밋 전: 해당 overlay 렌더 변경 전/후 저장 → `diff`로 의도한 변화만 확인.
2. A 단계: 4개 overlay(local/dev/staging/prod) 모두 0 diff 확인.
3. 최종: `kubectl kustomize local-k8s` 리소스 수 34 유지, deprecation 경고 0.
4. (선택) minikube 가용 시 `bash scripts/minikube-up.sh`로 gateway 라우팅 스모크.

## 영향받는 파일

- `local-k8s/apps/engagement-svc/kustomization.yaml` (수정, B)
- `local-k8s/apps/gateway/kustomization.yaml` (신규, C)
- `local-k8s/gateway.yaml` (삭제, C)
- `local-k8s/secrets.yaml` (수정, C)
- `local-k8s/kustomization.yaml` (수정, C)
- `apps/*/base/kustomization.yaml` 6개 (수정, A)
- `local-k8s/README.md` (gotcha 표·렌더 수 변동 시 정합, 종결)
</content>
</invoke>
