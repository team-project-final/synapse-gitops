# local-k8s 재설치 · 진단 · 하드닝 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** minikube 로컬 k8s 스택을 클린 재설치하며 진단하고, 무중단 배포·schema-registry·infra 프로브 등 검증된 개선을 base+local overlay에 반영한다.

**Architecture:** Kustomize base(`apps/<svc>/base`) + 환경별 overlay(local-k8s, dev/staging/prod). 무중단 필드는 base에, PDB/anti-affinity는 prod overlay에, infra·배선 개선은 local-k8s에 적용. 모든 변경은 `kubectl kustomize` 렌더로 선검증 후 클러스터 적용.

**Tech Stack:** minikube v1.38.1, kubectl v1.36.1, kustomize v5.8.1, docker 29.5.2, Confluent cp-kafka/cp-schema-registry 7.7.0, pgvector/pgvector:pg16, Spring Boot(temurin 21), FastAPI(python 3.12).

**설계 문서:** [docs/superpowers/specs/2026-06-03-local-k8s-reinstall-hardening-design.md](../specs/2026-06-03-local-k8s-reinstall-hardening-design.md)

**작업 브랜치:** `feat/local-k8s-reinstall-hardening` (이미 생성됨, spec 커밋 `0073de6` 포함). 모든 작업은 이 브랜치 위에서 수행.

**사전 조건:**
- CWD = `D:\workspace\final-project-syn\synapse-gitops`
- 형제 레포가 `../synapse-*`에 클론되어 있어야 이미지 빌드 가능
- 모든 `kubectl kustomize` 검증은 클러스터 불필요(클라이언트 렌더)

---

## File Structure

### 생성
- `local-k8s/infra/schema-registry.yaml` — cp-schema-registry Deployment + Service (Task 1)
- `apps/<svc>/overlays/prod/pdb.yaml` — 5개 svc PDB (Task 3)

### 수정
- `local-k8s/infra/kustomization.yaml` — schema-registry 등록 (Task 1)
- `local-k8s/apps/{platform-svc,engagement-svc,knowledge-svc,learning-card}/kustomization.yaml` — SCHEMA_REGISTRY_URL 배선 (Task 1)
- `apps/{platform-svc,engagement-svc,knowledge-svc,learning-card,learning-ai,gateway}/base/deployment.yaml` — 무중단 전략·preStop·minReadySeconds (Task 2)
- `apps/{platform-svc,engagement-svc,knowledge-svc,learning-card,learning-ai}/overlays/prod/kustomization.yaml` — PDB resource 등록 + anti-affinity patch (Task 3)
- `local-k8s/infra/{postgres,redis,kafka,zookeeper,opensearch}.yaml` — 프로브 + 리소스 (Task 4)
- `scripts/minikube-up.sh` — learning-ai 키 자동주입 단계 (Task 4)
- `local-k8s/apps/*/kustomization.yaml` 또는 `local-k8s/secrets.yaml` — 설정 일관성/위생 (Task 5, 감사 결과 반영)
- `local-k8s/README.md`, 메모리 — 문서 갱신 (Task 7)

### 스크래치(커밋 안 함)
- `/tmp/local-k8s-baseline/` — P0/P3 렌더·파드 스냅샷 저장

---

## Task 0: P0 진단 · 베이스라인 캡처

**Files:** 없음(읽기/캡처만). 출력은 `/tmp/local-k8s-baseline/`에 저장.

- [ ] **Step 1: minikube 기동 및 도구 확인**

Run:
```bash
minikube status || minikube start --driver=docker --memory=8192 --cpus=4
kubectl version --client
```
Expected: minikube `host: Running`, kubectl client v1.36.x 출력.

- [ ] **Step 2: 변경 전 EKS overlay 렌더 베이스라인 캡처 (회귀 가드용)**

Run:
```bash
mkdir -p /tmp/local-k8s-baseline
for env in dev staging prod; do
  for svc in platform-svc engagement-svc knowledge-svc learning-card learning-ai; do
    kubectl kustomize "apps/$svc/overlays/$env" > "/tmp/local-k8s-baseline/before-$svc-$env.yaml" 2>/dev/null || echo "skip $svc/$env"
  done
done
kubectl kustomize apps/gateway/overlays/dev > /tmp/local-k8s-baseline/before-gateway-dev.yaml
kubectl kustomize local-k8s > /tmp/local-k8s-baseline/before-local-k8s.yaml
ls -1 /tmp/local-k8s-baseline/ | wc -l
```
Expected: 17개 내외 파일 생성(5 svc × 3 env + gateway-dev + local-k8s). 이 파일들은 Task 6에서 after와 diff.

- [ ] **Step 3: 클린 재설치로 현 상태 베이스라인 확보**

Run:
```bash
kubectl delete ns synapse-local --ignore-not-found
bash scripts/minikube-up.sh 2>&1 | tee /tmp/local-k8s-baseline/minikube-up-before.log
```
Expected: 스크립트가 이미지 6개 빌드/적재 후 `apply -k`, 롤아웃 대기. learning-ai는 키 미주입 시 CrashLoop 가능(정상).

- [ ] **Step 4: 파드·이벤트·재시작 베이스라인 캡처**

Run:
```bash
kubectl -n synapse-local get pods -o wide > /tmp/local-k8s-baseline/pods-before.txt
kubectl -n synapse-local get events --sort-by=.lastTimestamp > /tmp/local-k8s-baseline/events-before.txt
kubectl -n synapse-local get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.containerStatuses[0].restartCount}{"\n"}{end}' > /tmp/local-k8s-baseline/restarts-before.txt
cat /tmp/local-k8s-baseline/restarts-before.txt
```
Expected: 워크로드별 재시작 횟수 기록. learning-ai 외 0에 가까워야 함. 비정상 재시작(인프라 미준비로 인한 앱 CrashLoop)이 보이면 Task 4 프로브 개선의 효과 측정 기준이 됨.

- [ ] **Step 5: 진단 메모 작성(커밋 안 함)**

`/tmp/local-k8s-baseline/diagnosis.md`에 7차원 관측 결과 기록(서비스/파드/게이트웨이/시크릿/디플로이먼트/설정/무중단). 특히:
  - schema-registry 미존재로 인한 Avro 관련 에러 로그: `kubectl -n synapse-local logs deploy/platform-svc | grep -i "schema\|avro\|8086" | head`
  - DDL 설정: platform-svc만 `DDL_AUTO=update`인지 재확인

Expected: diagnosis.md에 §3 카탈로그 항목별 실제 관측 1줄씩.

---

## Task 1: schema-registry 추가 + 전 Java svc 배선 (commit 1)

**Files:**
- Create: `local-k8s/infra/schema-registry.yaml`
- Modify: `local-k8s/infra/kustomization.yaml`
- Modify: `local-k8s/apps/platform-svc/kustomization.yaml`
- Modify: `local-k8s/apps/engagement-svc/kustomization.yaml`
- Modify: `local-k8s/apps/knowledge-svc/kustomization.yaml`
- Modify: `local-k8s/apps/learning-card/kustomization.yaml`

- [ ] **Step 1: schema-registry 매니페스트 생성**

Create `local-k8s/infra/schema-registry.yaml`:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata: { name: schema-registry, labels: { app: schema-registry } }
spec:
  replicas: 1
  selector: { matchLabels: { app: schema-registry } }
  template:
    metadata: { labels: { app: schema-registry } }
    spec:
      # k8s 서비스링크 env(SCHEMA_REGISTRY_*)가 cp 이미지 설정과 충돌하는 것 방지
      enableServiceLinks: false
      containers:
        - name: schema-registry
          image: confluentinc/cp-schema-registry:7.7.0
          env:
            - { name: SCHEMA_REGISTRY_HOST_NAME, value: schema-registry }
            - { name: SCHEMA_REGISTRY_KAFKASTORE_BOOTSTRAP_SERVERS, value: "PLAINTEXT://kafka:9092" }
            - { name: SCHEMA_REGISTRY_LISTENERS, value: "http://0.0.0.0:8081" }
          ports: [ { containerPort: 8081 } ]
          readinessProbe:
            httpGet: { path: /subjects, port: 8081 }
            initialDelaySeconds: 20
            periodSeconds: 10
            failureThreshold: 12
          livenessProbe:
            tcpSocket: { port: 8081 }
            initialDelaySeconds: 40
            periodSeconds: 15
          resources:
            requests: { cpu: 100m, memory: 256Mi }
            limits: { cpu: 500m, memory: 512Mi }
---
apiVersion: v1
kind: Service
metadata: { name: schema-registry }
spec:
  selector: { app: schema-registry }
  ports: [ { port: 8081, targetPort: 8081 } ]
```

- [ ] **Step 2: infra kustomization에 등록**

Modify `local-k8s/infra/kustomization.yaml` — `resources:` 목록에 kafka.yaml 다음 줄로 추가:
```yaml
  - kafka.yaml
  - schema-registry.yaml
  - opensearch.yaml
```

- [ ] **Step 3: Java svc 4개 overlay configmap에 SCHEMA_REGISTRY_URL 추가**

각 파일의 `data:` 블록 마지막에 한 줄 추가. 정확한 앵커는 각 파일의 기존 마지막 data 키:

`local-k8s/apps/platform-svc/kustomization.yaml` — `KAFKA_BROKERS: kafka:9092` 다음에:
```yaml
        KAFKA_BROKERS: kafka:9092
        SCHEMA_REGISTRY_URL: http://schema-registry:8081
```

`local-k8s/apps/engagement-svc/kustomization.yaml` — `SPRING_DATA_REDIS_PORT: "6379"` 다음에:
```yaml
        SPRING_DATA_REDIS_PORT: "6379"
        SCHEMA_REGISTRY_URL: http://schema-registry:8081
```

`local-k8s/apps/knowledge-svc/kustomization.yaml` — `SPRING_DATA_REDIS_PORT: "6379"` 다음에:
```yaml
        SPRING_DATA_REDIS_PORT: "6379"
        SCHEMA_REGISTRY_URL: http://schema-registry:8081
```

`local-k8s/apps/learning-card/kustomization.yaml` — `SPRING_DATA_REDIS_PORT: "6379"` 다음에:
```yaml
        SPRING_DATA_REDIS_PORT: "6379"
        SCHEMA_REGISTRY_URL: http://schema-registry:8081
```

> learning-ai는 이미 `LEARNING_AI_SCHEMA_REGISTRY_URL: http://schema-registry:8081`을 가지고 있으므로 수정 불필요.

- [ ] **Step 4: 렌더 검증 (클러스터 불필요)**

Run:
```bash
kubectl kustomize local-k8s | grep -c "schema-registry"
kubectl kustomize local-k8s | grep "SCHEMA_REGISTRY_URL"
```
Expected: schema-registry 매치 ≥ 6 (Deployment·Service·env 4개 svc + learning-ai). `SCHEMA_REGISTRY_URL: http://schema-registry:8081`가 4번(platform/engagement/knowledge/learning-card), `LEARNING_AI_SCHEMA_REGISTRY_URL`이 1번 출력.

- [ ] **Step 5: EKS 회귀 미발생 확인**

Run:
```bash
kubectl kustomize apps/platform-svc/overlays/dev | diff /tmp/local-k8s-baseline/before-platform-svc-dev.yaml - && echo "NO EKS DIFF (정상)"
```
Expected: `NO EKS DIFF (정상)` — Task 1은 local-k8s만 건드리므로 EKS overlay 변화 없음.

- [ ] **Step 6: Commit**

```bash
git add local-k8s/infra/schema-registry.yaml local-k8s/infra/kustomization.yaml local-k8s/apps/platform-svc/kustomization.yaml local-k8s/apps/engagement-svc/kustomization.yaml local-k8s/apps/knowledge-svc/kustomization.yaml local-k8s/apps/learning-card/kustomization.yaml
git commit -m "feat(local-k8s): schema-registry 추가 + 전 Java svc SCHEMA_REGISTRY_URL 배선

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: base 무중단 배포 전략 + preStop/minReadySeconds (commit 2)

**Files (수정):** 6개 base deployment
- `apps/platform-svc/base/deployment.yaml`
- `apps/engagement-svc/base/deployment.yaml`
- `apps/knowledge-svc/base/deployment.yaml`
- `apps/learning-card/base/deployment.yaml`
- `apps/learning-ai/base/deployment.yaml`
- `apps/gateway/base/deployment.yaml`

각 파일에 **3곳**을 편집한다. 6개 파일 모두 동일 구조이므로 편집 블록은 같고, 앵커만 svc명/이미지명으로 달라진다.

- [ ] **Step 1: deployment spec에 strategy + minReadySeconds 추가**

각 파일에서 `spec:` 바로 아래 `replicas: 1` 다음 줄(= `selector:` 앞)에 삽입. 예) platform-svc:

기존:
```yaml
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: platform-svc
```
변경:
```yaml
spec:
  replicas: 1
  minReadySeconds: 5
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0
      maxSurge: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: platform-svc
```
나머지 5개 파일도 동일 — `matchLabels`의 `app.kubernetes.io/name` 값이 각 svc명(engagement-svc/knowledge-svc/learning-card/learning-ai/gateway)이라 앵커가 고유하다.

- [ ] **Step 2: template.spec에 terminationGracePeriodSeconds 추가**

각 파일에서 `    spec:` (template 하위) → `      containers:` 사이에 삽입:

기존:
```yaml
    spec:
      containers:
```
변경:
```yaml
    spec:
      terminationGracePeriodSeconds: 40
      containers:
```
(파일당 1회만 등장 — Edit 고유성 확보됨)

- [ ] **Step 3: 컨테이너에 preStop lifecycle 추가**

각 파일에서 컨테이너 `image:` 줄 다음에 삽입. 예) platform-svc:

기존:
```yaml
        - name: platform-svc
          image: ghcr.io/team-project-final/synapse-platform-svc:latest
          ports:
```
변경:
```yaml
        - name: platform-svc
          image: ghcr.io/team-project-final/synapse-platform-svc:latest
          lifecycle:
            preStop:
              exec:
                command: ["sh", "-c", "sleep 5"]
          ports:
```
각 파일 이미지명(`synapse-<svc>`)·포트가 고유하므로 앵커 충돌 없음. 모든 base 이미지(temurin jammy/alpine, python:3.12-slim)에 `sh` 존재 확인됨 → preStop 동작 보장.

- [ ] **Step 4: 렌더 검증 — 무중단 필드 존재**

Run:
```bash
for svc in platform-svc engagement-svc knowledge-svc learning-card learning-ai; do
  echo "=== $svc ==="
  kubectl kustomize "apps/$svc/overlays/dev" | grep -E "maxUnavailable|maxSurge|minReadySeconds|terminationGracePeriodSeconds|preStop"
done
kubectl kustomize apps/gateway/overlays/dev | grep -E "maxUnavailable|preStop"
```
Expected: 각 svc에서 `maxUnavailable: 0`, `maxSurge: 1`, `minReadySeconds: 5`, `terminationGracePeriodSeconds: 40`, `preStop` 출력.

- [ ] **Step 5: 렌더 검증 — local-k8s도 무중단 필드 반영**

Run:
```bash
kubectl kustomize local-k8s | grep -c "preStop"
```
Expected: 6 (앱 6개). local-k8s overlay가 base를 재사용하므로 자동 반영.

- [ ] **Step 6: EKS 회귀 가드 — 의도한 diff만 확인**

Run:
```bash
kubectl kustomize apps/platform-svc/overlays/dev > /tmp/after-platform-dev.yaml
diff /tmp/local-k8s-baseline/before-platform-svc-dev.yaml /tmp/after-platform-dev.yaml
```
Expected: 추가된 줄이 strategy/minReadySeconds/terminationGracePeriodSeconds/lifecycle preStop **뿐**. 그 외 변경 없음.

- [ ] **Step 7: Commit**

```bash
git add apps/platform-svc/base/deployment.yaml apps/engagement-svc/base/deployment.yaml apps/knowledge-svc/base/deployment.yaml apps/learning-card/base/deployment.yaml apps/learning-ai/base/deployment.yaml apps/gateway/base/deployment.yaml
git commit -m "feat(infra): base 무중단 배포 전략(maxUnavailable=0) + preStop/minReadySeconds

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: prod PDB + pod anti-affinity (commit 3)

**Files:**
- Create: `apps/{platform-svc,engagement-svc,knowledge-svc,learning-card,learning-ai}/overlays/prod/pdb.yaml` (5개)
- Modify: 위 5개 svc의 `overlays/prod/kustomization.yaml`

> 5개 prod overlay 모두 replicas=3 확인됨 → `minAvailable: 1` 안전. gateway는 prod overlay 없음 → 대상 아님.

- [ ] **Step 1: PDB 매니페스트 5개 생성**

`apps/platform-svc/overlays/prod/pdb.yaml`:
```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: platform-svc-pdb
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: platform-svc
```
나머지 4개도 동일 형식, `name`과 `matchLabels` 값만 각 svc명으로:
- `apps/engagement-svc/overlays/prod/pdb.yaml` → name `engagement-svc-pdb`, label `engagement-svc`
- `apps/knowledge-svc/overlays/prod/pdb.yaml` → name `knowledge-svc-pdb`, label `knowledge-svc`
- `apps/learning-card/overlays/prod/pdb.yaml` → name `learning-card-pdb`, label `learning-card`
- `apps/learning-ai/overlays/prod/pdb.yaml` → name `learning-ai-pdb`, label `learning-ai`

- [ ] **Step 2: 각 prod kustomization에 PDB resource 등록 + anti-affinity patch 추가**

각 `overlays/prod/kustomization.yaml`의 `resources:`에 pdb.yaml 추가하고, `patches:` 목록에 anti-affinity patch 추가.

`apps/platform-svc/overlays/prod/kustomization.yaml` — `resources:` 수정:
```yaml
resources:
  - ../../base
  - pdb.yaml
```
그리고 `patches:` 목록 끝에 추가:
```yaml
  - target:
      kind: Deployment
      name: platform-svc
    patch: |
      - op: add
        path: /spec/template/spec/affinity
        value:
          podAntiAffinity:
            preferredDuringSchedulingIgnoredDuringExecution:
              - weight: 100
                podAffinityTerm:
                  labelSelector:
                    matchLabels:
                      app.kubernetes.io/name: platform-svc
                  topologyKey: kubernetes.io/hostname
```
나머지 4개 prod kustomization도 동일 — `name`/`matchLabels` 값만 각 svc명으로 치환.

- [ ] **Step 3: 렌더 검증 — prod에 PDB + anti-affinity 존재**

Run:
```bash
for svc in platform-svc engagement-svc knowledge-svc learning-card learning-ai; do
  echo "=== $svc prod ==="
  kubectl kustomize "apps/$svc/overlays/prod" | grep -E "PodDisruptionBudget|minAvailable|podAntiAffinity|topologyKey"
done
```
Expected: 각 svc prod에서 `kind: PodDisruptionBudget`, `minAvailable: 1`, `podAntiAffinity`, `topologyKey` 출력.

- [ ] **Step 4: dev/staging에는 PDB/anti-affinity 미반영 확인**

Run:
```bash
kubectl kustomize apps/platform-svc/overlays/dev | grep -cE "PodDisruptionBudget|podAntiAffinity"
```
Expected: `0` — PDB/anti-affinity는 prod overlay에만.

- [ ] **Step 5: Commit**

```bash
git add apps/platform-svc/overlays/prod apps/engagement-svc/overlays/prod apps/knowledge-svc/overlays/prod apps/learning-card/overlays/prod apps/learning-ai/overlays/prod
git commit -m "feat(prod): svc별 PodDisruptionBudget(minAvailable=1) + pod anti-affinity

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: infra 프로브 + 리소스 + learning-ai 키 자동주입 (commit 4)

**Files (수정):**
- `local-k8s/infra/postgres.yaml`, `redis.yaml`, `kafka.yaml`, `zookeeper.yaml`, `opensearch.yaml`
- `scripts/minikube-up.sh`

- [ ] **Step 1: postgres 프로브 + 리소스**

`local-k8s/infra/postgres.yaml`의 postgres 컨테이너(`volumeMounts:` 앞)에 추가:
```yaml
          readinessProbe:
            exec:
              command: ["pg_isready", "-U", "synapse", "-d", "synapse"]
            initialDelaySeconds: 10
            periodSeconds: 5
            failureThreshold: 12
          livenessProbe:
            exec:
              command: ["pg_isready", "-U", "synapse"]
            initialDelaySeconds: 30
            periodSeconds: 15
          resources:
            requests: { cpu: 100m, memory: 256Mi }
            limits: { cpu: 500m, memory: 512Mi }
```

- [ ] **Step 2: redis 프로브 + 리소스**

`local-k8s/infra/redis.yaml`의 redis 컨테이너(`ports:` 다음)에 추가:
```yaml
          readinessProbe:
            exec:
              command: ["redis-cli", "-a", "redis_local", "ping"]
            initialDelaySeconds: 5
            periodSeconds: 5
          livenessProbe:
            tcpSocket: { port: 6379 }
            initialDelaySeconds: 15
            periodSeconds: 15
          resources:
            requests: { cpu: 50m, memory: 64Mi }
            limits: { cpu: 250m, memory: 256Mi }
```

- [ ] **Step 3: kafka 프로브 + 리소스**

`local-k8s/infra/kafka.yaml`의 kafka 컨테이너(`ports:` 다음)에 추가:
```yaml
          readinessProbe:
            tcpSocket: { port: 9092 }
            initialDelaySeconds: 20
            periodSeconds: 10
            failureThreshold: 12
          livenessProbe:
            tcpSocket: { port: 9092 }
            initialDelaySeconds: 40
            periodSeconds: 15
          resources:
            requests: { cpu: 250m, memory: 512Mi }
            limits: { cpu: 1000m, memory: 1Gi }
```

- [ ] **Step 4: zookeeper 프로브 + 리소스**

`local-k8s/infra/zookeeper.yaml`의 zookeeper 컨테이너(`ports:` 다음)에 추가:
```yaml
          readinessProbe:
            tcpSocket: { port: 2181 }
            initialDelaySeconds: 10
            periodSeconds: 10
          livenessProbe:
            tcpSocket: { port: 2181 }
            initialDelaySeconds: 20
            periodSeconds: 15
          resources:
            requests: { cpu: 100m, memory: 128Mi }
            limits: { cpu: 500m, memory: 256Mi }
```
> zookeeper.yaml의 실제 컨테이너 포트/구조를 먼저 Read로 확인 후 앵커 정합. 포트가 2181이 아니면 그 값으로 교체.

- [ ] **Step 5: opensearch 프로브 + 리소스**

`local-k8s/infra/opensearch.yaml`의 opensearch 컨테이너(`ports:` 다음)에 추가:
```yaml
          readinessProbe:
            httpGet: { path: /_cluster/health, port: 9200 }
            initialDelaySeconds: 30
            periodSeconds: 10
            failureThreshold: 12
          livenessProbe:
            tcpSocket: { port: 9200 }
            initialDelaySeconds: 60
            periodSeconds: 20
          resources:
            requests: { cpu: 250m, memory: 512Mi }
            limits: { cpu: 1000m, memory: 768Mi }
```
> opensearch는 이미 `-Xms256m -Xmx256m` 설정 → limit 768Mi는 JVM heap + off-heap 여유.

- [ ] **Step 6: minikube-up.sh에 learning-ai 키 자동주입 단계 추가**

`scripts/minikube-up.sh`의 `kubectl apply -k` 다음(`==> 4) 롤아웃 대기` 앞)에 삽입:
```bash
echo "==> 3.5) learning-ai OpenAI 키 자동주입 (LEARNING_AI_OPENAI_API_KEY env 또는 ../.learning-ai-key 파일 존재 시)"
LAI_KEY="${LEARNING_AI_OPENAI_API_KEY:-}"
if [ -z "$LAI_KEY" ] && [ -f "$SIB/.learning-ai-key" ]; then LAI_KEY="$(cat "$SIB/.learning-ai-key")"; fi
if [ -n "$LAI_KEY" ]; then
  kubectl -n synapse-local create secret generic learning-ai-secret \
    --from-literal=LEARNING_AI_OPENAI_API_KEY="$LAI_KEY" \
    --from-literal=LEARNING_AI_ANTHROPIC_API_KEY=sk-mock \
    --from-literal=DATABASE_PASSWORD=synapse_local \
    --dry-run=client -o yaml | kubectl apply -f -
  kubectl -n synapse-local rollout restart deploy/learning-ai
  echo "    키 주입 완료."
else
  echo "    키 없음 — learning-ai는 CrashLoop으로 남습니다(나머지 10개 워크로드는 정상). README §learning-ai 참조."
fi
```
> `$SIB/.learning-ai-key`는 `.gitignore` 대상(레포 밖 형제 디렉터리). 키는 절대 커밋하지 않음.

- [ ] **Step 7: 렌더 검증 — 프로브/리소스 반영**

Run:
```bash
kubectl kustomize local-k8s | grep -cE "readinessProbe"
kubectl kustomize local-k8s | grep -E "pg_isready|redis-cli|_cluster/health"
bash -n scripts/minikube-up.sh && echo "스크립트 문법 OK"
```
Expected: readinessProbe 매치 수가 Task 1 대비 증가(앱 + infra 5종 + schema-registry). `pg_isready`/`redis-cli`/`_cluster/health` 각 출력. 스크립트 문법 OK.

- [ ] **Step 8: Commit**

```bash
git add local-k8s/infra/postgres.yaml local-k8s/infra/redis.yaml local-k8s/infra/kafka.yaml local-k8s/infra/zookeeper.yaml local-k8s/infra/opensearch.yaml scripts/minikube-up.sh
git commit -m "feat(local-k8s): infra 프로브+리소스 + learning-ai 키 자동주입

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: 설정 일관성(DDL/Flyway) + 위생 (commit 5)

**Files:** P1 감사 결과에 따라 조건부. 후보:
- `local-k8s/apps/platform-svc/kustomization.yaml` (DDL 정책)
- `local-k8s/secrets.yaml` (unused 키)
- `local-k8s/apps/*/kustomization.yaml` (imagePullPolicy)

- [ ] **Step 1: DDL/Flyway 일관성 결정**

Run:
```bash
kubectl kustomize local-k8s | grep -iE "DDL_AUTO|HIBERNATE_DDL"
```
Expected: platform-svc만 `update`. 나머지 4 svc는 Flyway 의존(키 없음).

판단:
- platform-svc base에 Flyway 마이그레이션이 존재하면 → local overlay의 `SPRING_JPA_HIBERNATE_DDL_AUTO: update`를 `validate`로 변경(다른 svc와 일관).
- Flyway 마이그레이션이 없거나 불완전하면 → `update` 유지하되 주석으로 사유 명시.

확인:
```bash
ls ../synapse-platform-svc/src/main/resources/db/migration/ | head
```
마이그레이션 파일이 충분하면 platform-svc/kustomization.yaml에서:
```yaml
        SPRING_JPA_HIBERNATE_DDL_AUTO: validate
```
로 변경. 불충분하면 변경 없이 주석만 보강.

- [ ] **Step 2: unused 시크릿 키 정리 (선택)**

`local-k8s/secrets.yaml`에서 앱이 안 읽는 키 확인 후 정리. 예: learning-card `API_KEY: mock`이 실제 참조되지 않으면 주석 처리. 확인:
```bash
grep -riE "API_KEY|S3_ACCESS_KEY" ../synapse-learning-svc/learning-card/src ../synapse-knowledge-svc/src | grep -v test | head
```
참조 없으면 해당 키에 `# unused (검증: <날짜>)` 주석. **삭제보다 주석 권장**(과확신 방지).

- [ ] **Step 3: imagePullPolicy 명시 (선택)**

minikube 재적재 후 stale 이미지 방지를 위해 local-k8s 앱 overlay에 `imagePullPolicy: IfNotPresent` 명시 검토. 6개 app overlay에 patch 추가:
```yaml
  - target:
      kind: Deployment
      name: platform-svc
    patch: |
      - op: add
        path: /spec/template/spec/containers/0/imagePullPolicy
        value: IfNotPresent
```
> `:local` 태그는 기본 IfNotPresent라 기능상 무변화 — 명시화 가치가 낮으면 P1 판단으로 생략 가능. 생략 시 diagnosis.md에 사유 기록.

- [ ] **Step 4: 렌더 검증**

Run:
```bash
kubectl kustomize local-k8s > /dev/null && echo "렌더 성공"
kubectl kustomize apps/platform-svc/overlays/dev | grep -iE "DDL_AUTO" || echo "dev DDL 무변경(정상 — local만 수정)"
```
Expected: 렌더 성공. EKS overlay의 DDL 설정은 변화 없음.

- [ ] **Step 5: Commit**

```bash
git add -A local-k8s/
git commit -m "fix(local-k8s): 설정 일관성(DDL/Flyway) + 시크릿/이미지정책 위생

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: P3 재검증 (재설치 + Avro 왕복 + 무중단 스모크 + EKS diff)

**Files:** 없음(검증만). 실패 시 해당 Task로 복귀.

- [ ] **Step 1: 클린 재설치**

Run:
```bash
kubectl delete ns synapse-local --ignore-not-found
bash scripts/minikube-up.sh 2>&1 | tee /tmp/local-k8s-baseline/minikube-up-after.log
```
Expected: 전 워크로드 롤아웃 성공. (키 자동주입 설정 시 learning-ai 포함)

- [ ] **Step 2: 전 워크로드 Ready 확인 (성공 기준 1)**

Run:
```bash
kubectl -n synapse-local get pods
kubectl -n synapse-local get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.containerStatuses[0].ready}{"\n"}{end}'
```
Expected: 인프라(postgres/redis/kafka/zookeeper/opensearch/**schema-registry**) + 앱이 모두 `true`. learning-ai는 키 주입 시 Ready.

- [ ] **Step 3: Avro 왕복 검증 (성공 기준 2)**

Run:
```bash
# schema-registry 기동 확인
kubectl -n synapse-local exec deploy/schema-registry -- curl -s localhost:8081/subjects
# platform-svc 로그에서 schema-registry 연결(8086 폴백 에러 부재) 확인
kubectl -n synapse-local logs deploy/platform-svc | grep -iE "schema|avro" | tail
# 토픽에 등록된 subject 확인 (이벤트 발행 후)
kubectl -n synapse-local exec deploy/schema-registry -- curl -s localhost:8081/subjects
```
Expected: `/subjects`가 200 응답(빈 배열 또는 등록된 subject). platform-svc 로그에 `localhost:8086 연결 거부` 류 에러 **없음**. 이벤트 1건 발행 후 subject 목록에 스키마 등장.

> 이벤트 트리거: gateway 경유 회원가입 호출 등으로 `platform.auth.user-registered-v1` 발행 → consumer(engagement/audit) 로그에서 수신 확인.

- [ ] **Step 4: 무중단 롤아웃 스모크 (성공 기준 3)**

Run (터미널 A — port-forward):
```bash
kubectl -n synapse-local port-forward svc/gateway 8080:80
```
Run (터미널 B — 부하 루프 후 롤아웃):
```bash
( for i in $(seq 1 200); do
    code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/api/platform/actuator/health)
    echo "$code"; sleep 0.2
  done ) > /tmp/local-k8s-baseline/smoke-codes.txt &
sleep 2
kubectl -n synapse-local rollout restart deploy/platform-svc
kubectl -n synapse-local rollout status deploy/platform-svc --timeout=180s
wait
echo "=== 5xx/연결실패 카운트 ==="
grep -vE "^200|^401|^403" /tmp/local-k8s-baseline/smoke-codes.txt | sort | uniq -c
```
Expected: 5xx(`5..`)·`000`(연결실패) **0건**. (401/403은 인증 미설정 health 응답일 수 있어 무중단 판단에서 제외 — 연결 자체는 성공.)

> 주의: local replica=1 + maxSurge=1 → 롤아웃 중 신규 파드 Ready 후 구파드 종료라 무손실 기대. preStop 5s가 endpoint 디레지스터를 보장.

- [ ] **Step 5: EKS 회귀 가드 — after 렌더 diff (성공 기준 4)**

Run:
```bash
for env in dev staging prod; do
  for svc in platform-svc engagement-svc knowledge-svc learning-card learning-ai; do
    kubectl kustomize "apps/$svc/overlays/$env" 2>/dev/null | diff "/tmp/local-k8s-baseline/before-$svc-$env.yaml" - > "/tmp/local-k8s-baseline/diff-$svc-$env.txt" 2>/dev/null
  done
done
echo "=== 변경된 줄 요약 (무중단/PDB/affinity 외 변경이 있으면 의심) ==="
for f in /tmp/local-k8s-baseline/diff-*.txt; do
  [ -s "$f" ] && echo "--- $f ---" && grep -E "^[<>]" "$f" | grep -viE "strategy|RollingUpdate|maxUnavailable|maxSurge|minReadySeconds|terminationGracePeriod|lifecycle|preStop|sleep|PodDisruptionBudget|minAvailable|affinity|topologyKey|podAffinityTerm|labelSelector|weight|preferredDuring|matchLabels|app.kubernetes.io|exec|command|sh|-c" | head
done
echo "=== 위에 추가 출력이 없으면 의도한 diff만 = 통과 ==="
```
Expected: dev/staging diff는 무중단 base 필드(strategy/preStop/minReadySeconds/grace)만. prod diff는 그에 더해 PDB/anti-affinity. 그 외 비의도 변경 출력 0줄.

- [ ] **Step 6: 재시작 횟수 before/after 비교 (infra 프로브 효과)**

Run:
```bash
kubectl -n synapse-local get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.containerStatuses[0].restartCount}{"\n"}{end}' > /tmp/local-k8s-baseline/restarts-after.txt
echo "=== BEFORE ==="; cat /tmp/local-k8s-baseline/restarts-before.txt
echo "=== AFTER ==="; cat /tmp/local-k8s-baseline/restarts-after.txt
```
Expected: after의 앱 재시작 횟수가 before 이하(인프라 프로브로 기동 레이스 완화 → 0 지향).

- [ ] **Step 7: 검증 실패 시 분기**

- Avro 실패(8086 폴백 에러 잔존) → Task 1 Step 3 배선 재확인.
- 무중단 스모크 5xx 발생 → preStop sleep 증가(5→10) 또는 readiness initialDelay 조정 후 Task 2 재커밋.
- EKS 비의도 diff → 해당 base 편집 재검토.

---

## Task 7: P4 문서 · 정리 (commit 6)

**Files:**
- Modify: `local-k8s/README.md`
- Modify: 메모리 `local-k8s-install-gaps.md` (또는 신규 메모리)

- [ ] **Step 1: README에 schema-registry + 무중단 반영**

`local-k8s/README.md` 갱신:
- 인프라 목록에 schema-registry 추가, 포트표에 `Schema Registry | 8081` 추가.
- "설계 노트" 표에 무중단 전략(maxUnavailable=0/preStop), infra 프로브, schema-registry 행 추가.
- learning-ai 키 주입을 `minikube-up.sh` 자동주입(`$SIB/.learning-ai-key` 또는 env) 기준으로 갱신.

- [ ] **Step 2: 메모리 갱신**

`C:\Users\deepe\.claude\projects\D--workspace-final-project-syn\memory\local-k8s-install-gaps.md` 갱신:
- "미커밋" 표현 제거(PR #94/#95/#96 병합 완료 + 본 하드닝 PR 반영).
- 추가된 개선(schema-registry, 무중단 base 필드, infra 프로브, 키 자동주입) 1줄씩.
- `MEMORY.md` 인덱스 한 줄 갱신.

- [ ] **Step 3: 최종 렌더 스모크 + 커밋**

Run:
```bash
kubectl kustomize local-k8s > /dev/null && echo "local-k8s 렌더 OK"
git add local-k8s/README.md
git commit -m "docs(local-k8s): schema-registry/무중단/프로브 반영 + 키 자동주입 안내

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 4: PR 생성 (사용자 승인 후)**

Run:
```bash
git push -u origin feat/local-k8s-reinstall-hardening
gh pr create --base main --title "feat(local-k8s): 재설치 하드닝 — schema-registry/무중단/infra 프로브" --body "설계: docs/superpowers/specs/2026-06-03-local-k8s-reinstall-hardening-design.md / 계획: docs/superpowers/plans/2026-06-03-local-k8s-reinstall-hardening.md"
```
> push/PR은 사용자가 명시 요청할 때만.

---

## Self-Review

**1. Spec coverage:**
- A1~A3(무중단 base) → Task 2 ✅ / A4~A5(PDB·anti-affinity) → Task 3 ✅ / A6(graceful shutdown) → §5 후속 분리, Task 7 메모리 기록 ✅
- B1(infra 프로브) → Task 4 ✅ / B2(infra 리소스) → Task 4 ✅ / B3(schema-registry) → Task 1 ✅
- C1~C2(schema-registry 배선) → Task 1 ✅ / C3(키 자동주입) → Task 4 ✅ / C4(DDL/Flyway) → Task 5 ✅
- D1~D2(서비스/게이트웨이) → Task 0 진단 기록(변경 없음) ✅ / D3(unused 시크릿) → Task 5 ✅ / D4(imagePullPolicy) → Task 5 ✅
- 성공 기준 1~5 → Task 6 Step 2~6에서 각각 검증 ✅

**2. Placeholder scan:** "TBD/TODO/적절히 처리" 없음. 모든 코드 스텝에 실제 YAML/명령 제시. Task 5는 조건부지만 각 분기의 구체 변경·판단 기준·확인 명령 명시.

**3. Type/이름 일관성:** 서비스명(`platform-svc`/`engagement-svc`/`knowledge-svc`/`learning-card`/`learning-ai`/`gateway`), 라벨 키(`app.kubernetes.io/name`), schema-registry URL(`http://schema-registry:8081`), 시크릿 키(`LEARNING_AI_OPENAI_API_KEY`)가 전 Task에서 일관. PDB minAvailable=1은 prod replicas=3 확인에 근거.
