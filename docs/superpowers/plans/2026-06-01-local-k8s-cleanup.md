# local-k8s 정리(cleanup) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** local-k8s 품질·일관성 3건 정리 — B(engagement dead config 제거)·C(gateway base 정합)·A(commonLabels deprecation 해소) — 기능 변화 없이.

**Architecture:** kustomize overlay 변경. 테스트 프레임워크가 없으므로 검증은 `kubectl kustomize` **렌더 diff**로 한다(변경 전 baseline 캡처 → 변경 → 재렌더 → 기대 delta 확인). B→C→A 순 원자적 커밋. A는 `includeSelectors: true`로 모든 overlay 렌더를 byte-identical 유지(ArgoCD 관리 live selector 충돌 방지).

**Tech Stack:** kustomize (kubectl built-in), bash, git. 브랜치: `chore/local-k8s-cleanup` (생성됨).

**선행 spec:** `docs/superpowers/specs/2026-06-01-local-k8s-cleanup-design.md`

**렌더 검증 루트 17개** (A 단계에서 전부 0-diff 확인):
```
apps/engagement-svc/overlays/{dev,staging,prod}
apps/gateway/overlays/dev
apps/knowledge-svc/overlays/{dev,staging,prod}
apps/learning-ai/overlays/{dev,staging,prod}
apps/learning-card/overlays/{dev,staging,prod}
apps/platform-svc/overlays/{dev,staging,prod}
local-k8s
```

---

## Task 1: B — engagement dead config 제거

**Files:**
- Modify: `local-k8s/apps/engagement-svc/kustomization.yaml:23-24`

- [ ] **Step 1: 변경 전 baseline 렌더 캡처**

Run:
```bash
kubectl kustomize local-k8s > /tmp/lk8s_before_B.yaml 2>/dev/null
grep -c "REDIS_HOST\|REDIS_PORT" /tmp/lk8s_before_B.yaml
```
Expected: `2` (engagement configmap의 두 키)

- [ ] **Step 2: 두 줄 삭제**

`local-k8s/apps/engagement-svc/kustomization.yaml`에서 아래 두 줄을 제거:
```yaml
        REDIS_HOST: redis
        REDIS_PORT: "6379"
```
삭제 후 해당 ConfigMap 패치 data 블록은 다음과 같다:
```yaml
      data:
        DATABASE_HOST: postgres
        DATABASE_PORT: "5432"
        DATABASE_NAME: synapse
        SPRING_DATASOURCE_URL: jdbc:postgresql://postgres:5432/synapse
        SPRING_DATASOURCE_USERNAME: synapse
        KAFKA_BROKERS: kafka:9092
```

- [ ] **Step 3: 재렌더 + diff (기대 delta = 2키 제거만)**

Run:
```bash
kubectl kustomize local-k8s > /tmp/lk8s_after_B.yaml 2>/dev/null
diff /tmp/lk8s_before_B.yaml /tmp/lk8s_after_B.yaml
```
Expected: `REDIS_HOST: redis`·`REDIS_PORT: "6379"` 두 줄만 `<`(삭제)로 표시. 그 외 변화 없음.

- [ ] **Step 4: 리소스 수 불변 확인**

Run:
```bash
grep -c "^kind:" /tmp/lk8s_after_B.yaml
```
Expected: `34`

- [ ] **Step 5: Commit**

```bash
git add local-k8s/apps/engagement-svc/kustomization.yaml
git commit -m "fix(local-k8s): engagement-svc 미사용 REDIS_HOST/PORT 제거 (dead config)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: C — gateway base 정합

**Files:**
- Create: `local-k8s/apps/gateway/kustomization.yaml`
- Modify: `local-k8s/secrets.yaml` (gateway-secret 추가)
- Modify: `local-k8s/kustomization.yaml` (gateway.yaml → apps/gateway)
- Delete: `local-k8s/gateway.yaml`

- [ ] **Step 1: 변경 전 baseline 렌더 캡처**

Run:
```bash
kubectl kustomize local-k8s > /tmp/lk8s_before_C.yaml 2>/dev/null
grep -c "^kind:" /tmp/lk8s_before_C.yaml
```
Expected: `34`

- [ ] **Step 2: gateway overlay 생성**

Create `local-k8s/apps/gateway/kustomization.yaml`:
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

- [ ] **Step 3: gateway-secret 추가**

`local-k8s/secrets.yaml` 끝에 다음 블록을 추가(맨 앞 `---` 포함):
```yaml
---
apiVersion: v1
kind: Secret
metadata: { name: gateway-secret }
type: Opaque
stringData:
  SPRING_DATA_REDIS_PASSWORD: redis_local   # infra/redis.yaml 의 --requirepass 값과 일치
```

- [ ] **Step 4: 최상위 kustomization에서 gateway 교체**

`local-k8s/kustomization.yaml`의 `- gateway.yaml` 줄을 `- apps/gateway`로 교체. 결과:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: synapse-local
resources:
  - namespace.yaml
  - infra
  - secrets.yaml
  - apps/gateway
  - apps/platform-svc
  - apps/engagement-svc
  - apps/knowledge-svc
  - apps/learning-card
  - apps/learning-ai
```

- [ ] **Step 5: standalone gateway.yaml 삭제**

Run:
```bash
git rm local-k8s/gateway.yaml
```

- [ ] **Step 6: 재렌더 + 기능 동치 검증**

Run:
```bash
kubectl kustomize local-k8s > /tmp/lk8s_after_C.yaml 2>/dev/null
echo "--- 리소스 수(기대 36) ---"; grep -c "^kind:" /tmp/lk8s_after_C.yaml
echo "--- gateway 라우트 4개(기대 각 1) ---"; grep -c "_SVC_URI" /tmp/lk8s_after_C.yaml
echo "--- gateway redis 주입(기대 HOST/PORT/PASSWORD 존재) ---"; grep "SPRING_DATA_REDIS" /tmp/lk8s_after_C.yaml | sort -u
echo "--- gateway-config ConfigMap 추가됨 ---"; grep -c "name: gateway-config" /tmp/lk8s_after_C.yaml
echo "--- gateway-secret 추가됨 ---"; grep -c "name: gateway-secret" /tmp/lk8s_after_C.yaml
echo "--- ExternalSecret 미포함(기대 0) ---"; grep -c "kind: ExternalSecret" /tmp/lk8s_after_C.yaml
echo "--- Service 80→8080 ---"; grep -A3 "name: gateway$" /tmp/lk8s_after_C.yaml | grep -c "targetPort: 8080"
```
Expected:
- 리소스 수: `36` (34 + gateway-config ConfigMap + gateway-secret Secret)
- `_SVC_URI`: `4` (PLATFORM/ENGAGEMENT/KNOWLEDGE/LEARNING)
- redis: `SPRING_DATA_REDIS_HOST`, `SPRING_DATA_REDIS_PORT`, `SPRING_DATA_REDIS_PASSWORD` 모두 존재
- gateway-config: `1` 이상, gateway-secret: `1` 이상
- ExternalSecret: `0`
- Service targetPort 8080: `1` 이상

- [ ] **Step 7: 라우트 회귀 확인 (before/after 라우트 값 동일)**

Run:
```bash
diff <(grep "_SVC_URI" /tmp/lk8s_before_C.yaml | sort) <(grep "_SVC_URI" /tmp/lk8s_after_C.yaml | sort)
```
Expected: diff 없음(라우트 4개 값 완전 동일).

- [ ] **Step 8: Commit**

```bash
git add local-k8s/apps/gateway/kustomization.yaml local-k8s/secrets.yaml local-k8s/kustomization.yaml local-k8s/gateway.yaml
git commit -m "refactor(local-k8s): gateway standalone → apps/gateway/base 재사용 정합

다른 5개 앱과 동일한 base-overlay 패턴으로 통일. 라우트 4개 동일, liveness probe·resource limits 추가(개선). gateway-config/gateway-secret 2개 리소스 증가(34→36).

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: A — commonLabels deprecation 해소

**Files:**
- Modify: `apps/engagement-svc/base/kustomization.yaml`
- Modify: `apps/gateway/base/kustomization.yaml`
- Modify: `apps/knowledge-svc/base/kustomization.yaml`
- Modify: `apps/learning-ai/base/kustomization.yaml`
- Modify: `apps/learning-card/base/kustomization.yaml`
- Modify: `apps/platform-svc/base/kustomization.yaml`

- [ ] **Step 1: 변경 전 17개 루트 baseline 렌더 캡처**

Run:
```bash
mkdir -p /tmp/render_before
for d in apps/*/overlays/* local-k8s; do
  [ -f "$d/kustomization.yaml" ] || continue
  kubectl kustomize "$d" > "/tmp/render_before/$(echo "$d" | tr / _).yaml" 2>/dev/null
done
ls /tmp/render_before | wc -l
```
Expected: `17`

- [ ] **Step 2: 6개 base kustomization 전환**

각 파일에서 아래 블록을
```yaml
commonLabels:
  app.kubernetes.io/managed-by: kustomize
```
다음으로 교체:
```yaml
labels:
  - pairs:
      app.kubernetes.io/managed-by: kustomize
    includeSelectors: true
```
대상 6개: `apps/{engagement-svc,gateway,knowledge-svc,learning-ai,learning-card,platform-svc}/base/kustomization.yaml`.

- [ ] **Step 3: deprecation 경고 사라졌는지 확인**

Run:
```bash
kubectl kustomize local-k8s 2>&1 >/dev/null | grep -c "commonLabels"
```
Expected: `0`

- [ ] **Step 4: 17개 루트 재렌더 + 0-diff 검증 (핵심)**

Run:
```bash
FAIL=0
for d in apps/*/overlays/* local-k8s; do
  [ -f "$d/kustomization.yaml" ] || continue
  key="$(echo "$d" | tr / _).yaml"
  kubectl kustomize "$d" 2>/dev/null > "/tmp/render_after_$key"
  if ! diff -q "/tmp/render_before/$key" "/tmp/render_after_$key" >/dev/null; then
    echo "DIFF DETECTED: $d"; diff "/tmp/render_before/$key" "/tmp/render_after_$key" | head -20; FAIL=1
  fi
done
[ "$FAIL" = "0" ] && echo "ALL 17 ROOTS: 0 DIFF (PASS)" || echo "FAIL — selector/라벨 변동 있음"
```
Expected: `ALL 17 ROOTS: 0 DIFF (PASS)`
> 만약 diff가 나오면 `includeSelectors: true` 누락 또는 들여쓰기 오류 — 수정 후 재실행. 0-diff 전까지 commit 금지.

- [ ] **Step 5: Commit**

```bash
git add apps/engagement-svc/base/kustomization.yaml apps/gateway/base/kustomization.yaml apps/knowledge-svc/base/kustomization.yaml apps/learning-ai/base/kustomization.yaml apps/learning-card/base/kustomization.yaml apps/platform-svc/base/kustomization.yaml
git commit -m "chore(gitops): commonLabels(deprecated) → labels includeSelectors:true

selector 보존 위해 includeSelectors:true 사용 — 17개 overlay 렌더 0-diff 검증 완료. ArgoCD 관리 live selector 충돌 없음.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: README 정합 + 마무리

**Files:**
- Modify: `local-k8s/README.md`

- [ ] **Step 1: 렌더 수 갱신**

`local-k8s/README.md`의 `kubectl kustomize local-k8s    # 34 리소스 렌더`를
`kubectl kustomize local-k8s    # 36 리소스 렌더`로 수정.

- [ ] **Step 2: 최종 렌더 sanity**

Run:
```bash
kubectl kustomize local-k8s >/dev/null 2>warn.txt; grep -c "commonLabels" warn.txt; rm -f warn.txt
kubectl kustomize local-k8s 2>/dev/null | grep -c "^kind:"
```
Expected: 경고 `0`, 리소스 수 `36`

- [ ] **Step 3: Commit**

```bash
git add local-k8s/README.md
git commit -m "docs(local-k8s): README 렌더 수 36 정합 (gateway base 정합 반영)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 4: (선택) minikube 스모크 — 환경 가용 시에만**

Run:
```bash
bash scripts/minikube-up.sh
kubectl -n synapse-local port-forward svc/gateway 8080:80 &
sleep 5
curl -fsS http://localhost:8080/api/platform/actuator/health
```
Expected: gateway 라우팅 통해 platform health 응답(UP). minikube 미가용 시 이 스텝은 건너뜀(렌더 검증으로 충분).

---

## 완료 기준

- [ ] B/C/A/README 4개 커밋, 브랜치 `chore/local-k8s-cleanup`
- [ ] `kubectl kustomize local-k8s` 경고 0 · 리소스 36
- [ ] 17개 overlay 렌더 A 전후 0-diff (selector 보존 증명)
- [ ] PR 생성(사용자 요청 시)
</content>
