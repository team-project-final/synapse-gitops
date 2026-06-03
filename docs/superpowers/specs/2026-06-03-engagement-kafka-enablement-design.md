# engagement-svc Kafka 활성화 — 설계 (2026-06-03)

## 배경

핸드오프 후속 finding B5. engagement-svc는 Kafka 이벤트(level-up, badge-earned,
user-registered, review-completed)를 Avro로 소비/발행하도록 코드가 작성돼 있으나
배포 매니페스트에서 **기본 비활성**(`synapse.kafka.enabled=${KAFKA_ENABLED:false}`)
상태였다.

선행 작업으로 앱 레포 PR #21이 `application.yml`에
`spring.kafka.bootstrap-servers=${KAFKA_BOOTSTRAP_SERVERS:localhost:9092}`
플레이스홀더를 추가했다. 이제 매니페스트 측에서 Kafka를 켤 수 있다.

조사로 드러난 추가 갭(핸드오프엔 "overlay에 KAFKA_ENABLED=true"만 적혀 있었음):

1. **env 이름 불일치**: engagement base(`apps/engagement-svc/base/deployment.yaml`)는
   `KAFKA_BROKERS`만 주입하는데 앱은 `KAFKA_BOOTSTRAP_SERVERS`를 읽는다. #99가
   platform/knowledge/learning-card/learning-ai base엔 `KAFKA_BOOTSTRAP_SERVERS`를
   추가했지만 (당시 #21 미머지라) engagement만 누락됐다. → localhost:9092 폴백.
2. **SCHEMA_REGISTRY_URL 부재**: Avro 직렬화기(KafkaAvroSerializer)는 schema registry가
   필요한데 EKS `apps/` 트리 전체에 `SCHEMA_REGISTRY_URL`이 하나도 없다.
   (#98의 schema-registry는 local-k8s/minikube 트리에만 존재.)
3. **EKS에 in-cluster 인프라 없음**: `apps/`는 6개 서비스만 있고 kafka=MSK, postgres=RDS,
   redis=ElastiCache 전부 terraform 관리 AWS 매니지드. schema-registry를 EKS에 올리려면
   ArgoCD가 관리하는 새 컴포넌트가 필요하다.

## 목표 / 비목표

**목표**
- minikube(local-k8s)에서 engagement Kafka를 완전 활성화하고 **런타임 검증**
  (kafka:9092 + schema-registry:8081 연결, 토픽 소비/발행 로그 확인).
- EKS dev에서 engagement Kafka가 동작할 수 있도록 git 매니페스트를 완비
  (base env 일관성, schema-registry 컴포넌트, dev overlay 활성화). 클러스터 부재로
  **렌더 검증만** 수행, 런타임 검증은 EKS 프로비저닝(태스크 A)으로 이연.

**비목표**
- staging/prod에서의 Kafka 활성화 (dev만 대상).
- 앱 소스(직렬화기) 변경 — Confluent SR 유지로 변경 불필요.
- gateway/engagement Dockerfile 비-root화 (B2 별도 finding).

## 결정 사항

- **EKS 범위**: dev까지 활성화 (사용자 결정).
- **SR 구현**: in-cluster Confluent `cp-schema-registry:7.7.0` (minikube↔EKS 패리티,
  앱 직렬화기 변경 없음). AWS Glue SR 안은 5개 앱 레포 직렬화기 교체 + local 패리티
  깨짐으로 기각.
- **검증 깊이**: minikube 런타임 검증 + 이미지 재빌드. EKS는 kustomize 렌더 검증.

## 변경 설계

### 표면 1 — local-k8s (minikube), 런타임 검증

`local-k8s/apps/engagement-svc/kustomization.yaml`의 ConfigMap 패치에 추가:
- `KAFKA_BOOTSTRAP_SERVERS: kafka:9092`
- `KAFKA_ENABLED: "true"`
- 라인 29~32의 "의도적으로 추가하지 않음 / 후속 finding" NOTE를 활성화 사실로 갱신.

검증:
1. engagement 이미지를 현재 소스(#21 포함)로 재빌드 → `synapse-engagement-svc:local` 태그.
2. minikube에 재배포(`kubectl rollout restart` 또는 이미지 로드 후 재적용).
3. 파드 로그에서 (a) `bootstrap.servers = [kafka:9092]`, (b) schema-registry 연결,
   (c) 컨슈머 그룹 `engagement-svc-group` 조인 / 토픽 구독 확인.
4. 기존 12/12 워크로드 Running 유지 회귀 확인.

### 표면 2 — EKS apps/ (git-only, 렌더 검증)

**2a. base env 일관성** — `apps/engagement-svc/base/deployment.yaml`
#99 패턴대로 kafka-brokers ConfigMap에서 `KAFKA_BOOTSTRAP_SERVERS`와
`SPRING_KAFKA_BOOTSTRAP_SERVERS`를 추가 주입. `KAFKA_ENABLED`는 base에 두지 않음
(기본 false 유지 → staging/prod는 비활성 그대로).

**2b. schema-registry 컴포넌트** — 신규 `apps/schema-registry/`
- `base/deployment.yaml` + `base/service.yaml` + `base/kustomization.yaml`:
  local-k8s SR을 모델로 cp-schema-registry:7.7.0, heap 384m/limit 768Mi, 프로브 동일.
  `SCHEMA_REGISTRY_KAFKASTORE_BOOTSTRAP_SERVERS`는 kafka-brokers ConfigMap의
  `KAFKA_BROKERS` 값을 `PLAINTEXT://$(KAFKA_BROKERS)` 형태로 참조(terraform MSK 주소).
- `overlays/dev/kustomization.yaml`: `namespace: synapse-dev`.
- securityContext: 다른 워크로드와 동일 안전 부분집합(allowPrivilegeEscalation:false,
  drop ALL, seccomp RuntimeDefault). cp 이미지 UID 미확정이라 runAsNonRoot 미적용.

**2c. ArgoCD 배포** — `argocd/schema-registry.yaml` (standalone Application)
매트릭스 ApplicationSet에 넣지 않음(image-updater ECR semver 주석이 Confluent
dockerhub 이미지엔 부적합). project `synapse`, source `apps/schema-registry/overlays/dev`,
destination `synapse-dev`, automated sync.

**2d. dev 활성화** — `apps/engagement-svc/overlays/dev/kustomization.yaml`
ConfigMap 패치에 추가:
- `KAFKA_ENABLED: "true"`
- `SCHEMA_REGISTRY_URL: http://schema-registry:8081`

### EKS 검증 불가 리스크 (Runbook 명시)

`docs/runbooks/`에 engagement-kafka 활성화 검증 절차 문서화:
- **MSK auth 모드**: local SR은 `PLAINTEXT://kafka:9092`. MSK 리스너가 TLS/IAM/SASL이면
  SR env(`SCHEMA_REGISTRY_KAFKASTORE_SECURITY_PROTOCOL` 등)와 앱 producer 보안 설정
  추가 필요. 앱들도 동일 kafka-brokers 값을 쓰므로 현재 VPC 내 PLAINTEXT 가정 →
  프로비저닝 시 1순위 검증.
- **네트워크 경로**: SR 파드 → MSK 9092 도달성(보안그룹/NetworkPolicy egress).
  prod netpol 패턴 참조하되 dev는 netpol 미적용이라 SG만 관건.
- **kafka-brokers ConfigMap**: terraform `k8s-kafka-config`가 synapse-dev ns에 생성하는지
  (없으면 SR·engagement 파드 모두 configMapKeyRef 실패로 기동 불가).

## 검증 계획

| 항목 | 방법 | 시점 |
|------|------|------|
| local engagement Kafka 동작 | minikube 런타임 로그 | 이번 작업 |
| local 회귀 (12/12 Running) | `kubectl get pods` | 이번 작업 |
| EKS 렌더 정합성 | `kustomize build apps/engagement-svc/overlays/dev` + `apps/schema-registry/overlays/dev` | 이번 작업 |
| yamllint CI | gitops `validate` 워크플로 | PR |
| EKS 런타임 | Runbook 절차 | 태스크 A (EKS 프로비저닝) |

## 영향 범위 / PR

- **gitops** (1 PR): local-k8s engagement, apps/engagement-svc base+dev overlay,
  apps/schema-registry 신규, argocd/schema-registry.yaml, runbook.
- 앱 레포 변경 없음 (#21로 충분).
- staging/prod 매니페스트 변경 없음.
