# local-k8s 온보딩 가이드 — 단일 HTML 인터랙티브 시각화 설계

- **작성일**: 2026-06-03
- **상태**: 설계 승인됨 (구현 계획 대기)
- **산출물**: `synapse-gitops/docs/local-k8s-guide.html` (자체완결 단일 HTML)

## 1. 목적 & 대상

synapse `local-k8s`(minikube) 스택의 **전체 서비스간 연결, Kafka 구독/소비, 연결 주소,
요청/응답 API**를 팀원들에게 보여주는 온보딩/가이드/시뮬레이션 페이지.

- **대상(계층적)**: 기본은 신규/기존 개발자 모두가 고수준 흐름을 보고, 드릴다운하면
  신규 백엔드 개발자를 위한 기술 상세(주소·토픽·엔드포인트·DTO)까지 드러난다.
- **성격**: 애니메이션(이벤트 흐름 재생) + 탐색(클릭 드릴다운) 결합.

## 2. 목표 & 성공 기준

신규 개발자가 **10분 내**에:
1. 서비스 경계(누가 무엇을 소유)를 파악한다.
2. 이벤트 1건을 애니메이션으로 end-to-end 추적한다(예: 사용자 가입 → Kafka → 소비자).
3. 임의의 엔드포인트/토픽/주소를 종합 레퍼런스에서 검색해 찾는다.

**제약 충족**: 오프라인·무설치(파일 더블클릭), 인터넷/CDN 불필요.

## 3. 비목표 (YAGNI)

- 실시간 데이터·실제 API 호출 (정적/목 데이터로 구동)
- 백엔드·서버·빌드 툴링
- 모바일 우선 레이아웃 (데스크톱 우선)
- 외부 라이브러리/CDN 의존

## 4. 기술 아키텍처

- **자체완결 단일 `.html`**: 인라인 `<style>` + `<script>` + `SYSTEM` 데이터 객체. 빌드 없음.
- **순수 바닐라**: HTML/CSS/JS + SVG. 외부 의존성 0.
- **데이터↔렌더 분리**: 시스템 전체를 기술하는 단일 `SYSTEM` 객체에서 맵·애니메이션·
  레퍼런스·드릴다운 패널이 모두 렌더링된다. 아키텍처 변경 시 `SYSTEM`만 수정.
- **렌더 함수**: `renderMap()` · `renderReference()` · `openPanel(id)` ·
  `playScenario(name)` · `setLayer(type)`. 상태는 단순 전역(선택 노드·활성 레이어·재생 상태).
- 맵은 SVG(노드=`<g>`, 엣지=`<path>`), 애니메이션은 SVG `<animateMotion>` 또는
  `requestAnimationFrame`으로 경로 좌표를 따라 입자 이동.

### 4.1 SYSTEM 데이터 모델 (개요)

```js
const SYSTEM = {
  services: { <id>: { label, addr, port, tier, color, role,
                      rest:[<endpointRef>], produces:[<topic>], consumes:[<topic>],
                      stores:[<infraId+db>], calls:[<serviceId>] } },
  infra:    { <id>: { label, addr, port, kind } },     // kafka, schema-registry, postgres, redis, opensearch, zookeeper
  rest:     [ { from, to, basePath, endpoints:[{method,path,reqDto,resDto,desc}] } ],
  events:   [ { topic, producer, consumers:[], schemaFields:[], partitions } ],
  connections:[ { name, addr, envVars:[], protocol, consumers:[] } ],
  dtos:     { <name>: { fields:[{name,type,desc}], sample:{...} } },
  scenarios:[ { name, steps:[{ node|edge, kind, narration }] } ],
}
```

## 5. 시스템 데이터 (수집된 정본 — 구현 시 전수 보강)

> 아래는 매니페스트(`local-k8s/apps/*`, `infra/kafka-topics-job.yaml`)와 앱 소스에서
> 수집한 정본 골격. **종합 레퍼런스** 요구에 따라 구현 시 6개 서비스 컨트롤러 + Avro 스키마를
> 전수 스캔해 엔드포인트/DTO/토픽 필드를 채운다.

### 5.1 서비스 (6) + gateway
- `gateway` (Spring Cloud Gateway, `gateway:8080`): `/api/platform/**`→platform,
  `/api/engagement/**`→engagement, `/api/knowledge/**`→knowledge, `/api/learning/**`→learning,
  RedisRateLimiter 적용.
- `platform-svc` (`:8080`, DB `synapse_platform`): auth/user/billing/notification 등.
- `engagement-svc` (`:8080`, DB `synapse_engagement`): Kafka 소비자(Avro) 활성.
- `knowledge-svc` (`:8080`, DB `synapse_knowledge`, OpenSearch 사용).
- `learning-ai` (Python, DB `synapse_learning_ai`, OpenSearch): knowledge-svc·learning-card REST 호출.
- `learning-card` (`:8080`, DB `synapse_learning`).

### 5.2 인프라 & 연결 주소
- `kafka:9092` (PLAINTEXT, local), `schema-registry:8081` (Avro), `zookeeper`
- `postgres:5432` (서비스별 DB), `redis:6379`, `opensearch:9200`
- 주입 env: `KAFKA_BOOTSTRAP_SERVERS`, `SCHEMA_REGISTRY_URL`, `SPRING_DATASOURCE_URL`,
  `SPRING_DATA_REDIS_HOST/PORT`, `OPENSEARCH_URL` 등. (`enableServiceLinks:false`로 서비스링크 충돌 차단)

### 5.3 Kafka 토픽 (5, partitions=3)
- `platform.auth.user-registered-v1` — producer: platform · consumer: engagement
- `knowledge.note.note-created-v1` — producer: knowledge · consumer: learning-ai
- `knowledge.note.note-updated-v1` — producer: knowledge · consumer: learning-ai
- `learning.card.review-completed-v1` — producer: learning-card · consumer: engagement
- `learning.ai.cards-generated-v1` — producer: learning-ai · consumer: learning-card

### 5.4 서비스간 REST (Kafka 외)
- learning-ai → knowledge-svc (`LEARNING_AI_NOTE_SERVICE_URL=http://knowledge-svc`)
- learning-ai → learning-card (`LEARNING_AI_LEARNING_CARD_SERVICE_URL=http://learning-card`)
- (gateway → 모든 서비스, 5.1 라우트)

### 5.5 대표 이벤트 시나리오 (애니메이션)
1. **사용자 가입**: client→gateway `/api/platform`→platform → `platform.auth.user-registered-v1` 발행 → engagement 소비
2. **노트→카드 생성**: knowledge → `knowledge.note.note-created-v1` → learning-ai 소비 →(REST 노트 조회)→ `learning.ai.cards-generated-v1` → learning-card 소비
3. **복습 완료**: learning-card → `learning.card.review-completed-v1` → engagement 소비

## 6. UI 컴포넌트

### 6.1 인터랙티브 아키텍처 맵 (중앙)
- 고정 3단 티어 레이아웃: 상단 gateway / 중단 서비스 6 / 하단 인프라.
- 엣지 색 구분: REST(실선)·Kafka pub/sub(점선, kafka 경유)·데이터스토어(가는 선).
- 레이어 토글 `[REST][Kafka][Store]`로 엣지 종류 on/off.
- hover: 노드+직접 연결 강조, 나머지 dim, 한 줄 요약 툴팁.
- 클릭: 사이드 드릴다운 패널 + 관련 엣지 하이라이트.

### 6.2 드릴다운 패널 (사이드)
노드/엣지 클릭 시: 주소/포트 · 소유 REST 엔드포인트 · Kafka pub/sub 토픽 ·
DTO · 데이터스토어(DB명). 엣지면 해당 연결 상세(REST path/method 또는 토픽/스키마).

### 6.3 이벤트 흐름 애니메이션 플레이어 (하단)
시나리오 선택 → 입자가 경로를 엣지별로 이동, 각 단계마다 엣지 점등 + 단계 설명.
Kafka 단계는 발행자→kafka→소비자 홉 시각화. 컨트롤: 재생/일시정지·단계 이동·속도.

### 6.4 종합 레퍼런스 (검색)
- 검색/필터 바(서비스별·종류별·자유텍스트).
- 엔드포인트 표(서비스|method|path|요청 DTO|응답 DTO|설명, 행 펼치면 샘플 JSON).
- Kafka 토픽 표(토픽|producer|consumers|Avro 필드|partitions).
- 연결 디렉터리(host:port|주입 env|프로토콜).
- DTO/스키마 카탈로그(Avro 이벤트 + 주요 REST DTO).
- 맵 노드 클릭 → 레퍼런스 해당 서비스 필터(상호 연동).

## 7. 비주얼 테마
- 다크 테마, 레이어별 액센트 색(REST·Kafka·Store) + 서비스별 색 칩.
- 한국어 UI, 주소/코드/JSON monospace, 설명 sans. 데스크톱 우선.

## 8. 파일 위치 & 유지보수
- `synapse-gitops/docs/local-k8s-guide.html` (정본 `docs/local-msa-setup.html` 옆).
- 스냅샷 성격 → 푸터에 "local-k8s 기준 / 생성일" 표기, 변경 시 `SYSTEM` 갱신 안내.

## 9. 구현 시 유의
- **콘텐츠 전수 수집**이 구현의 큰 비중: 6개 서비스 컨트롤러(엔드포인트·DTO) + Avro
  스키마(이벤트 필드)를 스캔해 `SYSTEM` 채우기. 정확성이 온보딩 가치의 핵심.
- 단일 파일이 커질 수 있음(종합 레퍼런스) — 가독성 위해 `SYSTEM` 데이터와 렌더 로직을
  파일 내 섹션으로 명확히 구획.

## 10. 리스크 / 오픈 이슈
- 종합 레퍼런스 전수 수집의 정확성/완전성(특히 learning-ai Python 서비스의 라우트).
- 단일 SVG 맵의 엣지 교차 가독성 — 레이어 토글로 완화하되 배치 좌표 수작업 조정 필요.
- 파일 크기(인라인 데이터+JSON 샘플)가 커질 때 초기 로드/스크롤 성능.
