# local-k8s-guide 정합성 감사 리포트 (2026-06-04)

> 대상: `docs/local-k8s-guide.html` 의 `SYSTEM` 데이터 모델
> 방법: 서비스 레포 6갈래 병렬 교차검증(file:line 근거) + gitops 인프라/스펙·플랜 직접 확인
> 결과: 검색엔진 표기·이벤트 흐름에서 드리프트 다수 확인 → 가이드 정정 반영(커밋 `74e66b9`)

---

## 1. 배경

`local-k8s-guide.html`은 Synapse MSA(gateway + 5 서비스 + Kafka/Postgres/Redis/검색엔진)의
인터랙티브 아키텍처·API 레퍼런스다. 디자인 시스템 정립 작업 중 "knowledge-svc가 OpenSearch가
아니라 Elasticsearch를 쓰는 것 같다 + 가이드 내용이 현재 레포 구성과 다른지 점검" 요청이 들어와
전면 정합성 감사를 수행했다.

## 2. 방법

서비스별 병렬 탐색 에이전트가 가이드의 주장(엔드포인트·토픽·스토어·env)을 실제 코드와 대조:

- knowledge-svc / platform-svc / engagement-svc / learning(card+ai) / gateway+infra / 스펙·플랜
- 추가로 누락 의심 토픽 4종의 producer·consumer·스키마·프로비저닝을 정밀 추적
- gitops `local-k8s/` kustomization·infra 매니페스트를 직접 확인하여 "배포되는 것"의 진실 확정

## 3. 핵심 발견

### 3.1 검색엔진 — 단순 오타가 아닌 이중 스택 기술부채

| 구성요소 | 코드/클라이언트 | local-k8s 배포 서버 | 근거 |
|---|---|---|---|
| knowledge-svc | **Elasticsearch 클라이언트** (`spring-boot-starter-data-elasticsearch`, `co.elastic.clients...ElasticsearchClient`, `spring.elasticsearch.uris`) | **OpenSearch 2.11** (`opensearchproject/opensearch:2.11.0`), env `OPENSEARCH_URL` | build.gradle.kts:45, ElasticsearchNoteSearchRepository.java:3-4, local-k8s/infra/opensearch.yaml:12, local-k8s/apps/knowledge-svc/kustomization.yaml:24 |
| learning-ai | **pgvector** (Postgres, HNSW) — 검색엔진 미사용 | (OPENSEARCH_URL 주입되나 **앱이 무시**) | pyproject `pgvector`, note_chunk_repository(cosine_distance), learning-ai/kustomization.yaml:24 주석 |

- 풀컨테이너 경로(synapse-gitops compose)는 **Elasticsearch 8.13**, shared/local-k8s 경로는 **OpenSearch 2.11**으로 분기 — `local-msa-setup.html`에 "알려진 기술부채"로 명시됨.
- **결정:** local-k8s 가이드는 "배포되는 것"을 문서화하므로 **노드는 OpenSearch 2.11 유지** + knowledge가 ES 클라이언트로 접속한다는 각주 + learning-ai는 pgvector로 정정.

### 3.2 이벤트 흐름 — 토픽 프로비저닝 드리프트

local-k8s `kafka-topics-job.yaml`은 **5개 토픽만 생성**하나, 서비스 코드는 **9개**를 발행/구독한다.
AWS Dev(MSK terraform)와 docker-compose는 **9개 전부 프로비저닝**. `KAFKA_AUTO_CREATE_TOPICS_ENABLE`
미설정(cp-kafka 기본 true) → 누락 4종은 **런타임 auto-create로 동작**.

근거: local-k8s/infra/kafka-topics-job.yaml:16-17, infra/aws/dev/kafka-topics/main.tf:6-17, synapse-shared/docker-compose.yml:111-121, local-k8s/infra/kafka.yaml(해당 env 부재).

### 3.3 게이트웨이 라우팅

`/api/learning/**` 는 **learning-card 단독** 라우팅. learning-ai는 게이트웨이 미노출(내부 호출만).
근거: synapse-gateway RoutesConfig.java:53-58, apps/gateway/base/configmap.yaml:15.

## 4. 확정 오류 → 정정 결과

| # | 항목 | 가이드(전) | 실제/정정(후) | 근거 |
|---|---|---|---|---|
| 1 | learning-ai 검색 store | opensearch | **pgvector**(Postgres) | note_chunk_repository, kustomization 주석 |
| 2 | gateway→learning-ai 라우트 | learning-card+learning-ai | **learning-card 단독**(각주) | RoutesConfig.java:53-58 |
| 3 | knowledge `calls` | [] | **["learning-ai"]** (시맨틱 위임) | LearningAiSearchClient.java:29 |
| 4 | 시나리오2 내레이션 | "knowledge producer P0 미구현" | **삭제**(실제 발행함) | NoteEventPublisher.java:35,49 |
| 5 | learning-ai consumes | note-created + note-updated | **note-created만** | learning-ai consumer.py |
| 6 | knowledge 검색 표기 | (없음) | 역할에 "ES 클라이언트→OpenSearch" + 연결표 각주 | (3.1) |
| 7 | engagement redis | store에 포함 | **제거**(RedisConfig 빈 스텁, 미사용) | RedisConfig.java:7-8 |
| 8 | platform Stripe | (없음) | 역할 각주 추가 | BillingService.java:43 |

## 5. 누락 토픽 4종 (추가 + ⚠local-init 마커 표기)

| 토픽 | producer | consumer | 스키마 | 프로비저닝 |
|---|---|---|---|---|
| `platform.notification.notification-send-v1` | learning-ai 등 | platform | Avro | local-k8s 미생성 / AWS·compose ✓ |
| `engagement.gamification.level-up-v1` | engagement | (없음) | Avro | local-k8s 미생성 / AWS·compose ✓ |
| `engagement.gamification.badge-earned-v1` | engagement | (없음) | Avro | local-k8s 미생성 / AWS·compose ✓ |
| `knowledge.note.note-search-sync-v1` | knowledge | knowledge(self) | **JSON/CloudEvents** | **어떤 env에도 없음** — auto-create만 |

근거: GamificationKafkaProducer.java:34-62, NotificationKafkaConsumer.java:17-23, learning-ai notification_producer.py:44, NoteSearchKafkaProducer/Consumer.java, synapse-shared avro 스키마.

## 6. 오탐 (가이드가 실제로 정확 — 미수정)

- 서비스별 DB 이름(`synapse_platform/knowledge/engagement/learning/learning_ai`): local-k8s kustomization이 주입 → **정확**. (에이전트가 본 `synapse`는 서비스 standalone 기본값.)
- Kafka 파티션 3: local-k8s topic-init `--partitions 3` → 정확.
- 전 서비스 **REST 엔드포인트 전부 일치**.
- 인프라 노드·포트·env 이름, Kafka PLAINTEXT.
- learning-card(DB `synapse_learning`·토픽·무소비), `cards-generated-v1` deprecated(발행자 없음·HTTP 대체 D-001), card_client.py.

## 7. 적용 결과

- 가이드 `SYSTEM` 데이터 정정 반영. 토픽 5→**9개**, 시나리오 3→**7개**(하이브리드 검색/노트 검색 인덱싱/구독 결제/게이미피케이션 추가).
- 레퍼런스 표에 `⚠local-init`(미생성) / `JSON` 마커, 연결표에 검색엔진 각주 렌더 추가.
- `node --check` 구문 검증 통과, 브라우저 SELFTEST `topics=9` 통과.
- 커밋 `74e66b9` (branch `feat/prod-prereqs-netpol-metrics`).

## 8. 후속 권고

1. **인프라 갭(P1):** `local-k8s/infra/kafka-topics-job.yaml`에 누락 4종 토픽 추가 — 현재 auto-create
   의존은 파티션 수(기본 1)가 AWS/compose(3)와 달라질 수 있고, auto-create 비활성 환경에서 깨질 위험.
2. **ES/OpenSearch 정리:** `docs/superpowers/plans/2026-06-04-knowledge-search-elasticsearch-migration.md`
   플랜과 연계 — 클라이언트(ES)와 서버(OpenSearch) 분기를 한쪽으로 수렴하면 본 각주는 제거 가능.
3. **스펙/플랜 갱신:** `2026-06-03-local-k8s-guide-design.md`·`.../plan.md`는 본 감사 이전 작성분 — 토픽 9종·learning-ai pgvector를 반영.
