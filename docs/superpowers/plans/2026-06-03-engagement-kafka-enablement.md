# engagement-svc Kafka 활성화 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** engagement-svc의 Kafka 이벤트 소비/발행을 minikube에서 완전 활성화(런타임 검증)하고, EKS dev에서 동작 가능하도록 git 매니페스트(base env 일관성 + in-cluster Confluent schema-registry + dev overlay 활성화)를 완비한다.

**Architecture:** 두 배포 표면을 다룬다 — (1) local-k8s(minikube): ConfigMap에 `KAFKA_BOOTSTRAP_SERVERS`+`KAFKA_ENABLED=true` 추가 후 #21 포함 이미지 재빌드·재배포해 런타임 검증. (2) EKS `apps/`: engagement base에 #99 패턴(`KAFKA_BOOTSTRAP_SERVERS` 주입) 추가, 신규 `apps/schema-registry/` 컴포넌트를 standalone Argo Application으로 배포, engagement dev overlay에 `KAFKA_ENABLED`+`SCHEMA_REGISTRY_URL` 추가. EKS 런타임은 클러스터 부재로 이연(태스크 A).

**Tech Stack:** Kubernetes, Kustomize 5.x, ArgoCD, Confluent cp-schema-registry 7.7.0, minikube, yamllint(default braces/brackets max-spaces-inside:0 → block 스타일 필수).

**작업 브랜치:** `feat/engagement-kafka-enablement` (이미 체크아웃됨, spec 커밋 `beff9d2` 포함).

**검증 도구:** 로컬 렌더는 `kubectl kustomize <dir>`. minikube ns는 `synapse-local`. 형제 레포 루트 `D:/workspace/final-project-syn`.

---

## File Structure

생성:
- `apps/schema-registry/base/deployment.yaml` — cp-schema-registry 워크로드(MSK kafkastore)
- `apps/schema-registry/base/service.yaml` — ClusterIP :8081
- `apps/schema-registry/base/kustomization.yaml` — base 묶음
- `apps/schema-registry/overlays/dev/kustomization.yaml` — synapse-dev ns
- `argocd/schema-registry.yaml` — standalone Argo Application(dev)
- `docs/runbooks/engagement-kafka-enablement.md` — EKS 검증 절차/리스크

수정:
- `apps/engagement-svc/base/deployment.yaml` — KAFKA_BOOTSTRAP_SERVERS/SPRING_KAFKA_BOOTSTRAP_SERVERS env 주입(#99 패턴)
- `apps/engagement-svc/overlays/dev/kustomization.yaml` — ConfigMap에 KAFKA_ENABLED, SCHEMA_REGISTRY_URL 추가
- `local-k8s/apps/engagement-svc/kustomization.yaml` — ConfigMap에 KAFKA_BOOTSTRAP_SERVERS, KAFKA_ENABLED 추가 + NOTE 갱신

---

## Task 1: EKS schema-registry base 매니페스트 생성

**Files:**
- Create: `apps/schema-registry/base/deployment.yaml`
- Create: `apps/schema-registry/base/service.yaml`
- Create: `apps/schema-registry/base/kustomization.yaml`

- [ ] **Step 1: deployment.yaml 작성** (block 스타일 — flow 브레이스 금지)

`apps/schema-registry/base/deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: schema-registry
  labels:
    app.kubernetes.io/name: schema-registry
    app.kubernetes.io/part-of: synapse
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: schema-registry
  template:
    metadata:
      labels:
        app.kubernetes.io/name: schema-registry
        app.kubernetes.io/part-of: synapse
    spec:
      # k8s 서비스링크 env(SCHEMA_REGISTRY_*)가 cp 이미지 설정과 충돌하는 것 방지
      enableServiceLinks: false
      containers:
        - name: schema-registry
          image: confluentinc/cp-schema-registry:7.7.0
          env:
            # kafkastore bootstrap = MSK 주소. 앱들과 동일한 kafka-brokers ConfigMap을 사용한다.
            # (dev/EKS는 terraform k8s-kafka-config가 synapse-dev ns에 생성)
            - name: KAFKA_BROKERS
              valueFrom:
                configMapKeyRef:
                  name: kafka-brokers
                  key: KAFKA_BROKERS
            - name: SCHEMA_REGISTRY_HOST_NAME
              value: schema-registry
            # dev MSK 리스너 PLAINTEXT 가정. TLS/IAM/SASL이면 SECURITY_PROTOCOL 등 추가 필요(Runbook 참조).
            - name: SCHEMA_REGISTRY_KAFKASTORE_BOOTSTRAP_SERVERS
              value: "PLAINTEXT://$(KAFKA_BROKERS)"
            - name: SCHEMA_REGISTRY_LISTENERS
              value: "http://0.0.0.0:8081"
            # JVM 앱 — limit 768Mi 내로 힙 고정해 OOMKill 회피
            - name: SCHEMA_REGISTRY_HEAP_OPTS
              value: "-Xms256m -Xmx384m"
          ports:
            - containerPort: 8081
          readinessProbe:
            httpGet:
              path: /subjects
              port: 8081
            initialDelaySeconds: 20
            periodSeconds: 10
            failureThreshold: 12
          # 콜드 클러스터에서 kafka 리더 선출 대기 중 healthy 파드를 죽이지 않도록 grace 확대
          livenessProbe:
            tcpSocket:
              port: 8081
            initialDelaySeconds: 60
            periodSeconds: 15
            failureThreshold: 5
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 768Mi
          # cp 이미지 UID 미확정이라 runAsNonRoot 미적용. 안전 부분집합만(다른 워크로드와 동일).
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
            seccompProfile:
              type: RuntimeDefault
```

- [ ] **Step 2: service.yaml 작성**

`apps/schema-registry/base/service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: schema-registry
  labels:
    app.kubernetes.io/name: schema-registry
    app.kubernetes.io/part-of: synapse
spec:
  type: ClusterIP
  ports:
    - port: 8081
      targetPort: 8081
      protocol: TCP
      name: http
  selector:
    app.kubernetes.io/name: schema-registry
```

- [ ] **Step 3: base kustomization.yaml 작성**

`apps/schema-registry/base/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - deployment.yaml
  - service.yaml
```

---

## Task 2: EKS schema-registry dev overlay 생성

**Files:**
- Create: `apps/schema-registry/overlays/dev/kustomization.yaml`

- [ ] **Step 1: dev overlay 작성**

`apps/schema-registry/overlays/dev/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

namespace: synapse-dev
```

- [ ] **Step 2: 렌더 검증 — `$(KAFKA_BROKERS)` 가 그대로 보존되는지 확인**

Run: `kubectl kustomize apps/schema-registry/overlays/dev`
Expected: 에러 없이 Deployment+Service 출력. env 중
`value: PLAINTEXT://$(KAFKA_BROKERS)` 가 리터럴로 보존(kustomize가 미선언 `$(...)`를 치환하지 않음). `namespace: synapse-dev`가 두 리소스에 적용됨.

만약 kustomize가 `$(KAFKA_BROKERS)` 미해결로 **에러**를 내면(드묾):
deployment.yaml의 해당 값을 `value: "PLAINTEXT://$$(KAFKA_BROKERS)"` 로 변경(`$$`는 kustomize 이스케이프 → 렌더 시 `$(KAFKA_BROKERS)` 한 개로 환원). 재실행해 통과 확인.

- [ ] **Step 3: kubeconform 검증** (CI와 동일 경로)

Run: `kubectl kustomize apps/schema-registry/overlays/dev | kubeconform -strict -ignore-missing-schemas -summary -output text`
Expected: `Valid: 2, Invalid: 0`. (kubeconform 미설치 시 이 스텝은 CI에 위임 — 건너뛰고 Step 2 통과로 충분.)

- [ ] **Step 4: 커밋**

```bash
git add apps/schema-registry/
git commit -m "feat(schema-registry): EKS dev용 in-cluster Confluent SR 컴포넌트 추가"
```

---

## Task 3: schema-registry standalone Argo Application 추가

**Files:**
- Create: `argocd/schema-registry.yaml`

매트릭스 ApplicationSet은 모든 앱에 image-updater ECR semver 주석을 붙이는데,
cp-schema-registry는 Confluent dockerhub 이미지(ECR semver 아님)라 부적합.
별도 standalone Application으로 분리한다.

- [ ] **Step 1: Argo Application 작성**

`argocd/schema-registry.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: synapse-schema-registry-dev
  namespace: argocd
  labels:
    app.kubernetes.io/part-of: synapse
    app.kubernetes.io/component: schema-registry
    environment: dev
spec:
  project: synapse
  source:
    repoURL: https://github.com/team-project-final/synapse-gitops.git
    targetRevision: main
    path: apps/schema-registry/overlays/dev
  destination:
    server: https://kubernetes.default.svc
    namespace: synapse-dev
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

- [ ] **Step 2: yamllint 검증**

Run: `yamllint -c .yamllint argocd/schema-registry.yaml`
Expected: 출력 없음(통과). 경고/에러 시 줄 길이(160)·brace 공백 확인 후 수정.
(yamllint 미설치 시 CI에 위임.)

- [ ] **Step 3: 커밋**

```bash
git add argocd/schema-registry.yaml
git commit -m "feat(argocd): schema-registry dev Application(standalone) 추가"
```

---

## Task 4: engagement base env 일관성 (#99 패턴)

**Files:**
- Modify: `apps/engagement-svc/base/deployment.yaml` (현재 KAFKA_BROKERS env 블록은 36-40행)

engagement base는 `KAFKA_BROKERS`만 주입하나 앱은 `KAFKA_BOOTSTRAP_SERVERS`를 읽음 →
#99가 다른 4개 svc에 적용한 패턴을 engagement에도 적용.

- [ ] **Step 1: env 블록 교체**

`apps/engagement-svc/base/deployment.yaml`에서 아래 기존 블록:

```yaml
          env:
            - name: KAFKA_BROKERS
              valueFrom:
                configMapKeyRef:
                  name: kafka-brokers
                  key: KAFKA_BROKERS
```

를 다음으로 교체:

```yaml
          env:
            - name: KAFKA_BROKERS
              valueFrom:
                configMapKeyRef:
                  name: kafka-brokers
                  key: KAFKA_BROKERS
            # 앱은 spring.kafka.bootstrap-servers=${KAFKA_BOOTSTRAP_SERVERS:localhost:9092} 를 읽음.
            # KAFKA_BROKERS만으론 localhost 폴백 → Kafka 단절. 동일 ConfigMap 값을 앱이 읽는 이름으로도 주입.
            - name: KAFKA_BOOTSTRAP_SERVERS
              valueFrom:
                configMapKeyRef:
                  name: kafka-brokers
                  key: KAFKA_BROKERS
            # SPRING_KAFKA_BOOTSTRAP_SERVERS = spring.kafka.bootstrap-servers 정식 바인딩(일부 프로파일이 이 이름 사용)
            - name: SPRING_KAFKA_BOOTSTRAP_SERVERS
              valueFrom:
                configMapKeyRef:
                  name: kafka-brokers
                  key: KAFKA_BROKERS
```

- [ ] **Step 2: 렌더 검증 (dev overlay 빌드, KAFKA_ENABLED는 아직 없음)**

Run: `kubectl kustomize apps/engagement-svc/overlays/dev`
Expected: 에러 없이 출력. 컨테이너 env에 `KAFKA_BROKERS`, `KAFKA_BOOTSTRAP_SERVERS`,
`SPRING_KAFKA_BOOTSTRAP_SERVERS` 3개가 모두 보임(셋 다 kafka-brokers ConfigMap 참조).

- [ ] **Step 3: 커밋**

```bash
git add apps/engagement-svc/base/deployment.yaml
git commit -m "fix(engagement): base에 KAFKA_BOOTSTRAP_SERVERS 주입 (#99 패턴, env 이름 불일치 해소)"
```

---

## Task 5: engagement EKS dev overlay 활성화

**Files:**
- Modify: `apps/engagement-svc/overlays/dev/kustomization.yaml` (engagement-svc-config ConfigMap patch 내 op 목록)

- [ ] **Step 1: ConfigMap patch에 op 2개 추가**

`apps/engagement-svc/overlays/dev/kustomization.yaml`의 `engagement-svc-config`
ConfigMap patch 블록에서, 마지막 op(`- op: add` `path: /data/SPRING_DATASOURCE_USERNAME`
`value: "synapse_admin"`) **다음 줄에** 아래 2개 op를 추가:

```yaml
      - op: add
        path: /data/KAFKA_ENABLED
        value: "true"
      - op: add
        path: /data/SCHEMA_REGISTRY_URL
        value: "http://schema-registry:8081"
```

(들여쓰기는 기존 op들과 동일하게 `      - op:` = 공백 6칸.)

- [ ] **Step 2: 렌더 검증**

Run: `kubectl kustomize apps/engagement-svc/overlays/dev`
Expected: `engagement-svc-config` ConfigMap data에 `KAFKA_ENABLED: "true"` 와
`SCHEMA_REGISTRY_URL: http://schema-registry:8081` 가 보임.

- [ ] **Step 3: kubeconform 검증**

Run: `kubectl kustomize apps/engagement-svc/overlays/dev | kubeconform -strict -ignore-missing-schemas -summary -output text`
Expected: `Invalid: 0`. (미설치 시 CI 위임.)

- [ ] **Step 4: 커밋**

```bash
git add apps/engagement-svc/overlays/dev/kustomization.yaml
git commit -m "feat(engagement): EKS dev에서 Kafka 활성화(KAFKA_ENABLED, SCHEMA_REGISTRY_URL)"
```

---

## Task 6: local-k8s(minikube) engagement Kafka 활성화

**Files:**
- Modify: `local-k8s/apps/engagement-svc/kustomization.yaml` (ConfigMap patch data, 현재 23·28행 영역 + 29-32행 NOTE)

- [ ] **Step 1: ConfigMap data에 2개 키 추가 + NOTE 갱신**

`local-k8s/apps/engagement-svc/kustomization.yaml`에서 기존:

```yaml
        KAFKA_BROKERS: kafka:9092
        REDIS_HOST: redis
        REDIS_PORT: "6379"
        SPRING_DATA_REDIS_HOST: redis
        SPRING_DATA_REDIS_PORT: "6379"
        SCHEMA_REGISTRY_URL: http://schema-registry:8081
        # NOTE: 다른 Java svc와 달리 KAFKA_BOOTSTRAP_SERVERS를 의도적으로 추가하지 않음.
        # engagement-svc는 application.yml에 spring.kafka.bootstrap-servers 플레이스홀더가 없고
        # 자체 kafka.enabled=${KAFKA_ENABLED:false} 게이트로 Kafka가 기본 비활성 → env만으론 동작 안 함.
        # 로컬에서 Kafka 흐름을 켜려면 앱 레포에 bootstrap-servers 추가 + KAFKA_ENABLED=true 필요(후속 finding).
```

를 다음으로 교체:

```yaml
        KAFKA_BROKERS: kafka:9092
        # 앱(#21)이 spring.kafka.bootstrap-servers=${KAFKA_BOOTSTRAP_SERVERS:localhost:9092}를 읽음.
        KAFKA_BOOTSTRAP_SERVERS: kafka:9092
        # synapse.kafka.enabled 게이트 ON — 컨슈머/프로듀서(Avro) 활성화. SCHEMA_REGISTRY_URL 필수(아래).
        KAFKA_ENABLED: "true"
        REDIS_HOST: redis
        REDIS_PORT: "6379"
        SPRING_DATA_REDIS_HOST: redis
        SPRING_DATA_REDIS_PORT: "6379"
        SCHEMA_REGISTRY_URL: http://schema-registry:8081
```

- [ ] **Step 2: 렌더 검증**

Run: `kubectl kustomize local-k8s/apps/engagement-svc`
Expected: 에러 없이 출력. `engagement-svc-config` ConfigMap data에
`KAFKA_BOOTSTRAP_SERVERS: kafka:9092`, `KAFKA_ENABLED: "true"` 가 보임.

- [ ] **Step 3: 커밋**

```bash
git add local-k8s/apps/engagement-svc/kustomization.yaml
git commit -m "feat(local-k8s): engagement Kafka 활성화(KAFKA_BOOTSTRAP_SERVERS, KAFKA_ENABLED)"
```

---

## Task 7: minikube 런타임 검증 (이미지 재빌드 + 재배포)

**Files:** 없음(검증 전용). 사전조건: minikube `minikube` 프로파일 Running, ns `synapse-local`, kafka/schema-registry Running.

- [ ] **Step 1: 사전 상태 확인**

Run: `kubectl --context minikube -n synapse-local get pods`
Expected: 기존 워크로드(특히 `kafka`, `schema-registry`, `engagement-svc`) Running.
schema-registry가 없거나 NotReady면 먼저 `kubectl -n synapse-local rollout status deploy/schema-registry --timeout=180s`.

- [ ] **Step 2: #21 포함 engagement 이미지 재빌드**

Run:
```bash
docker build -t synapse-engagement-svc:local D:/workspace/final-project-syn/synapse-engagement-svc
```
Expected: `bootJar` 성공, 이미지 빌드 완료. (현재 소스에 #21 `bootstrap-servers` 포함됨.)

- [ ] **Step 3: minikube에 이미지 적재**

Run: `minikube image load synapse-engagement-svc:local`
Expected: 에러 없이 완료(수 초~수십 초).

- [ ] **Step 4: 변경 ConfigMap + 새 이미지 적용**

Run:
```bash
kubectl --context minikube apply -k D:/workspace/final-project-syn/synapse-gitops/local-k8s
kubectl --context minikube -n synapse-local rollout restart deploy/engagement-svc
kubectl --context minikube -n synapse-local rollout status deploy/engagement-svc --timeout=300s
```
Expected: ConfigMap 갱신, engagement-svc 새 파드 Ready(1/1). 롤아웃 성공.

- [ ] **Step 5: Kafka 연결/활성화 로그 확인 (핵심 검증)**

Run:
```bash
kubectl --context minikube -n synapse-local logs deploy/engagement-svc --tail=300 | grep -iE "bootstrap.servers|kafka|schema.registry|consumer|subscrib|level-up|user-registered"
```
Expected(아래 중 다수 충족):
- `bootstrap.servers = [kafka:9092]` (localhost:9092 아님)
- 컨슈머 그룹 `engagement-svc-group` 조인 / 토픽 구독 로그
- schema-registry(`http://schema-registry:8081`) 연결 흔적
- `KafkaAvroSerializer`/Avro 관련 ERROR가 **없을 것**(있으면 SR 연결 실패 → 진단)

`bootstrap.servers = [localhost:9092]` 가 보이면 ConfigMap/이미지 미반영 → Step 2~4 재확인.

- [ ] **Step 6: 전체 회귀 확인**

Run: `kubectl --context minikube -n synapse-local get pods`
Expected: 기존 12/12 워크로드 Running 유지(engagement-svc 새 파드 1/1, 다른 파드 영향 없음).

- [ ] **Step 7: 검증 결과를 spec/plan에 기록 (커밋 불필요한 산출물은 생략 가능)**

로그 발췌(bootstrap.servers, 컨슈머 조인 등)를 Task 8 Runbook의 "검증 로그 예시"에 반영.

---

## Task 8: EKS 검증 Runbook 작성

**Files:**
- Create: `docs/runbooks/engagement-kafka-enablement.md`

- [ ] **Step 1: Runbook 작성**

`docs/runbooks/engagement-kafka-enablement.md`:

```markdown
# Runbook — engagement-svc Kafka 활성화 (EKS dev)

## 개요
engagement-svc Kafka(소비/발행, Avro)를 EKS dev에서 동작시키기 위한 검증 절차.
git 매니페스트는 완비됨(base env 일관성, schema-registry 컴포넌트, dev overlay).
EKS 클러스터 프로비저닝(태스크 A) 직후 아래 순서로 검증한다.

## 선행 조건
- synapse-dev EKS 클러스터 + ArgoCD 존재.
- terraform `k8s-kafka-config`가 `synapse-dev` ns에 `kafka-brokers` ConfigMap
  (key `KAFKA_BROKERS` = MSK bootstrap 주소) 생성. **없으면 SR·engagement 파드가
  configMapKeyRef 실패로 기동 불가** → 1순위 확인.

## 검증 순서
1. **schema-registry 동기화**: ArgoCD `synapse-schema-registry-dev` Application Synced/Healthy.
   `kubectl -n synapse-dev rollout status deploy/schema-registry`.
2. **SR → MSK 연결**: `kubectl -n synapse-dev logs deploy/schema-registry`에서
   kafkastore 연결 성공 확인. 실패 시 아래 "MSK auth" 참조.
3. **SR 헬스**: `kubectl -n synapse-dev exec deploy/schema-registry -- curl -s localhost:8081/subjects`
   → `[]` 또는 subject 목록(200).
4. **engagement 활성화**: engagement 파드 env에 `KAFKA_ENABLED=true`,
   `SCHEMA_REGISTRY_URL=http://schema-registry:8081`, `KAFKA_BOOTSTRAP_SERVERS`(MSK) 확인.
   로그에 `bootstrap.servers = [<MSK>]`, 컨슈머 그룹 조인, Avro ERROR 없음.

## 리스크 / 미검증 항목
- **MSK auth 모드**: local SR은 `PLAINTEXT://kafka:9092` 가정. MSK 리스너가 TLS/IAM/SASL이면:
  - SR: `SCHEMA_REGISTRY_KAFKASTORE_SECURITY_PROTOCOL`(예: SSL/SASL_SSL) +
    필요 시 truststore/SASL 설정 추가.
  - engagement producer/consumer: `spring.kafka.properties.security.protocol` 등 추가
    (앱 레포 또는 overlay env). 앱들도 동일 kafka-brokers 값을 쓰므로 현재 VPC 내
    PLAINTEXT 전제 → 프로비저닝 시 MSK 리스너 설정과 대조.
- **네트워크 경로**: SR 파드 → MSK 9092 도달성(보안그룹/egress). dev는 netpol 미적용이라
  노드 SG가 MSK SG inbound 허용하는지 확인.
- **schema-registry 단일 replica**: dev 적정. prod 확장 시 replica/affinity 별도 검토.

## 검증 로그 예시 (minikube 기준)
<Task 7 Step 5에서 수집한 실제 로그 발췌를 여기에 붙인다.>
```

- [ ] **Step 2: yamllint은 docs/ 비대상 — 스킵. 커밋**

```bash
git add docs/runbooks/engagement-kafka-enablement.md
git commit -m "docs(runbook): engagement Kafka EKS 검증 절차/리스크"
```

---

## Task 9: 최종 통합 검증 + PR

- [ ] **Step 1: 전체 EKS overlay 렌더 회귀 (CI 모사)**

Run:
```bash
cd D:/workspace/final-project-syn/synapse-gitops
for d in apps/*/overlays/*; do echo "--- $d ---"; kubectl kustomize "$d" > /dev/null && echo OK || echo "FAIL $d"; done
```
Expected: 모든 overlay(engagement-svc/*, schema-registry/dev 포함) `OK`.

- [ ] **Step 2: yamllint 전체 (CI 모사, 미설치 시 스킵)**

Run: `yamllint -c .yamllint apps/ argocd/`
Expected: 출력 없음(통과). brace/bracket 공백·trailing space·줄길이(>160 warning) 없을 것.

- [ ] **Step 3: 커밋 로그 확인 + 푸시**

Run: `git log --oneline origin/main..HEAD`
Expected: Task 1~8 커밋 + spec 커밋(`beff9d2`)이 순서대로 보임.

Run: `git push -u origin feat/engagement-kafka-enablement`

- [ ] **Step 4: PR 생성**

```bash
gh pr create --repo team-project-final/synapse-gitops \
  --base main --head feat/engagement-kafka-enablement \
  --title "feat: engagement-svc Kafka 활성화 (local 런타임 검증 + EKS dev 매니페스트)" \
  --body "$(cat <<'EOF'
## 요약
engagement-svc Kafka 소비/발행(Avro)을 활성화. B5 후속 finding.

- **local-k8s(minikube)**: KAFKA_BOOTSTRAP_SERVERS + KAFKA_ENABLED=true 추가, #21 포함
  이미지로 런타임 검증(bootstrap.servers=[kafka:9092], 컨슈머 조인 확인).
- **EKS apps/**: engagement base env 일관성(#99 패턴), in-cluster Confluent
  schema-registry 컴포넌트(standalone Argo Application), dev overlay 활성화.
- EKS 런타임은 클러스터 부재로 이연 — `docs/runbooks/engagement-kafka-enablement.md`.

## 설계/계획
- spec: docs/superpowers/specs/2026-06-03-engagement-kafka-enablement-design.md
- plan: docs/superpowers/plans/2026-06-03-engagement-kafka-enablement.md

## 검증
- minikube 런타임: engagement-svc 1/1, Kafka 연결 로그 확인, 12/12 회귀 없음.
- EKS: kustomize build + kubeconform(CI validate) 통과.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Expected: PR URL 출력. CI `validate`(yamllint+kustomize+kubeconform) 통과 확인.

---

## Self-Review (작성자 체크)

**Spec 커버리지:**
- 표면1 local 활성화+런타임 검증 → Task 6, 7 ✓
- 표면2a base env 일관성 → Task 4 ✓
- 표면2b schema-registry 컴포넌트 → Task 1, 2 ✓
- 표면2c ArgoCD 배포 → Task 3 ✓
- 표면2d dev 활성화 → Task 5 ✓
- EKS 리스크 Runbook → Task 8 ✓
- 검증 계획(렌더/kubeconform/yamllint/런타임) → Task 2·5·7·9 ✓
- 단일 PR → Task 9 ✓

**플레이스홀더:** Runbook "검증 로그 예시"만 Task 7 산출물로 의도적 후채움(실데이터). 그 외 없음.

**타입/이름 일관성:** ConfigMap `kafka-brokers`/key `KAFKA_BROKERS`, env `KAFKA_BOOTSTRAP_SERVERS`/`SPRING_KAFKA_BOOTSTRAP_SERVERS`, Service `schema-registry:8081`, ns `synapse-dev`(EKS)/`synapse-local`(minikube), Application `synapse-schema-registry-dev` — 전 태스크 일치.
```
