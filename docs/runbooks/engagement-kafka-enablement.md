# Runbook — engagement-svc Kafka 활성화 (EKS dev)

## 개요
engagement-svc Kafka(소비/발행, Avro)를 EKS dev에서 동작시키기 위한 검증 절차.
git 매니페스트는 완비됨(base env 일관성, schema-registry 컴포넌트, dev overlay).
EKS 클러스터 프로비저닝(태스크 A) 직후 아래 순서로 검증한다.

minikube(local-k8s)에서는 이미 런타임 활성화·검증 완료(아래 "검증 로그" 참조).

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
   로그에 `bootstrap.servers = [<MSK>]`, `Discovered group coordinator`, `Successfully joined group`,
   Avro ERROR 없음.

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
- **selfHeal 주의**: `synapse-schema-registry-dev` Application은 `selfHeal: true`.
  긴급 env 변경(예: TLS 마이그레이션 시 SECURITY_PROTOCOL 추가)은 ArgoCD가 수초 내
  되돌리므로 **git 커밋으로 반영**하거나 일시적으로 selfHeal을 끄고 작업할 것.

## 검증 로그 (minikube, 2026-06-03)
engagement-svc 이미지를 #21(`spring.kafka.bootstrap-servers` 배선) 포함으로 재빌드 →
`KAFKA_ENABLED=true` + `KAFKA_BOOTSTRAP_SERVERS=kafka:9092` ConfigMap 적용 후 재배포.
실제 로그 발췌:

```
KafkaAvroDeserializerConfig values:
    schema.registry.url = [http://schema-registry:8081]
    specific.avro.reader = true
Kafka version: 4.1.1
[Consumer ... groupId=engagement-svc-group] Subscribed to topic(s): platform.auth.user-registered-v1
    bootstrap.servers = [kafka:9092]
[Consumer ... groupId=engagement-svc-group] Subscribed to topic(s): learning.card.review-completed-v1
[Consumer ... groupId=engagement-svc-group] Discovered group coordinator kafka:9092 (id: 2147483646 ...)
[Consumer ... groupId=engagement-svc-group] Successfully joined group with generation Generation{generationId=1, ...}
[Consumer ... groupId=engagement-svc-group] Finished assignment for group at generation 1:
    {... Assignment(partitions=[learning.card.review-completed-v1-0,1,2]),
     ... Assignment(partitions=[platform.auth.user-registered-v1-0,1,2])}
[Consumer ... groupId=engagement-svc-group] Resetting offset for partition platform.auth.user-registered-v1-0
    to position FetchPosition{offset=0, ... currentLeader=...[kafka:9092 (id: 1 ...)]}
```

확인된 사실:
- `bootstrap.servers = [kafka:9092]` (localhost:9092 폴백 아님) — base의 KAFKA_BOOTSTRAP_SERVERS 주입 정상.
- `schema.registry.url = [http://schema-registry:8081]` — SCHEMA_REGISTRY_URL 정상.
- 컨슈머 그룹 `engagement-svc-group` 코디네이터 발견·조인·파티션 할당·offset reset 완료.
- Kafka/Avro 연결 ERROR 없음(로그상 `ErrorHandlingDeserializer`는 Spring Kafka의 정상 래퍼 클래스명).
- 12/12 워크로드 Running 유지(회귀 없음).

> 참고: minikube에서 `kubectl apply -k local-k8s`는 전 서비스를 git 상태로 재조정하므로
> 라이브로 patch한 learning-ai OpenAI 키가 git 플레이스홀더로 되돌 수 있다. 필요 시
> `minikube-up.sh` 3.5단계 절차로 재주입한다.

---

## Kafka SSL 적용 매트릭스

> 조사 기준: 2026-06-04 (WS3-1). MSK는 TLS 전용 리스너(port 9094)이므로
> 모든 MSK 클라이언트는 dev/staging/prod 전 환경에서 SSL을 사용해야 한다(결정 D-A).
> 아래 표의 "no SSL" 셀이 후속 태스크에서 추가해야 할 갭이다.

### 인벤토리 근거

`grep -rln 'KAFKA_BROKERS\|KAFKA_BOOTSTRAP\|KAFKASTORE_BOOTSTRAP' apps/*/base apps/*/overlays` 결과:
`engagement-svc`, `knowledge-svc`, `learning-card`, `learning-ai`, `platform-svc`, `schema-registry`
의 base/deployment.yaml 6개 파일에서 매칭됨. `gateway`는 해당 없음(Kafka 미사용).

각 서비스 분류:
- **engagement-svc**: Spring Kafka, 소비+발행. topics: `platform.auth.user-registered-v1`, `learning.card.review-completed-v1`
- **knowledge-svc**: Spring Kafka, 발행. topics: `knowledge.note.note-created-v1`, `knowledge.note.note-updated-v1` (PR #32)
- **learning-card**: Spring Kafka, 발행+소비. topic: `learning.card.review-completed-v1`
- **learning-ai**: Python(pydantic, env_prefix=`LEARNING_AI_`), 소비. topic: `learning.ai.cards-generated-v1`
- **platform-svc**: Spring Kafka, 발행. topic: `platform.auth.user-registered-v1`
- **schema-registry**: Confluent Schema Registry — MSK kafkastore 클라이언트 (dev overlay만 존재, staging/prod overlay 없음)

### 매트릭스

| 서비스 | security-protocol 환경변수 키 | dev | staging | prod |
|---|---|---|---|---|
| engagement-svc | `SPRING_KAFKA_SECURITY_PROTOCOL` | SSL set | **no SSL** | **no SSL** |
| knowledge-svc | `SPRING_KAFKA_SECURITY_PROTOCOL` | **no SSL** | **no SSL** | **no SSL** |
| learning-card | `SPRING_KAFKA_SECURITY_PROTOCOL` | **no SSL** | **no SSL** | **no SSL** |
| learning-ai | **needs-verification** (앱 레포 확인 필요) | **no SSL** | **no SSL** | **no SSL** |
| platform-svc | `SPRING_KAFKA_SECURITY_PROTOCOL` | **no SSL** | **no SSL** | **no SSL** |
| schema-registry | `SCHEMA_REGISTRY_KAFKASTORE_SECURITY_PROTOCOL` | SSL set | n/a (overlay 없음) | n/a (overlay 없음) |

비고:
- `engagement-svc/dev`의 SSL 설정은 `apps/engagement-svc/overlays/dev/kustomization.yaml` ConfigMap patch에 존재.
- `schema-registry/dev`의 SSL 설정은 `apps/schema-registry/overlays/dev/kustomization.yaml` Deployment patch에 존재.
- `schema-registry`는 staging/prod overlay 디렉토리 자체가 없으므로 staging/prod 배포 대상이 아님(n/a).
- `learning-ai`의 security-protocol 환경변수 키는 gitops 매니페스트만으로 확정 불가.
  base/deployment.yaml 주석에 `LEARNING_AI_KAFKA_BOOTSTRAP_SERVERS`(env_prefix=`LEARNING_AI_`) 패턴이 명시되어 있어
  security-protocol 키도 `LEARNING_AI_KAFKA_SECURITY_PROTOCOL` 또는 `LEARNING_AI_SECURITY_PROTOCOL`일 가능성이 있으나,
  앱 레포(`synapse-learning-ai`) 확인 필요.

### 갭 목록

**dev 갭** (dev 오버레이는 있으나 SSL 미설정):
- `knowledge-svc/dev` — `SPRING_KAFKA_SECURITY_PROTOCOL=SSL` 추가 필요
- `learning-card/dev` — `SPRING_KAFKA_SECURITY_PROTOCOL=SSL` 추가 필요
- `learning-ai/dev` — security-protocol 환경변수 추가 필요 (키 이름 앱 레포 확인 후)
- `platform-svc/dev` — `SPRING_KAFKA_SECURITY_PROTOCOL=SSL` 추가 필요

**staging/prod 갭** (후속 태스크에서 처리):
- `engagement-svc/staging` — `SPRING_KAFKA_SECURITY_PROTOCOL=SSL` 추가 필요
- `engagement-svc/prod` — `SPRING_KAFKA_SECURITY_PROTOCOL=SSL` 추가 필요
- `knowledge-svc/staging` — `SPRING_KAFKA_SECURITY_PROTOCOL=SSL` 추가 필요
- `knowledge-svc/prod` — `SPRING_KAFKA_SECURITY_PROTOCOL=SSL` 추가 필요
- `learning-card/staging` — `SPRING_KAFKA_SECURITY_PROTOCOL=SSL` 추가 필요
- `learning-card/prod` — `SPRING_KAFKA_SECURITY_PROTOCOL=SSL` 추가 필요
- `learning-ai/staging` — security-protocol 환경변수 추가 필요 (키 이름 앱 레포 확인 후)
- `learning-ai/prod` — security-protocol 환경변수 추가 필요 (키 이름 앱 레포 확인 후)
- `platform-svc/staging` — `SPRING_KAFKA_SECURITY_PROTOCOL=SSL` 추가 필요
- `platform-svc/prod` — `SPRING_KAFKA_SECURITY_PROTOCOL=SSL` 추가 필요
