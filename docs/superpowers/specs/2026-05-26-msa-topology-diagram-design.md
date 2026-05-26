# 인터랙티브 MSA 구성도 설계 스펙

> **작성일**: 2026-05-26
> **범위**: `local-msa-setup.html` 가이드의 §0 ASCII 다이어그램을 인터랙티브 SVG 구성도로 교체
> **산출물**: `synapse-gitops/docs/local-msa-setup.html` (기존 단일 HTML 수정)

---

## 1. 목적

로컬 MSA 세팅 가이드(`local-msa-setup.html`) §0의 정적 ASCII 다이어그램을, **노드를 클릭하면 해당 컴포넌트의 포트·헬스·의존성·확인 명령이 뜨는 인터랙티브 SVG 구성도**로 업그레이드한다. 신규 팀원이 "이 컴포넌트는 무엇이고, 어떤 포트에서 돌며, 무엇에 의존하고, 어떻게 살아있는지 확인하는가"를 한 화면에서 파악하게 한다.

---

## 2. 대상 / 형태

- 대상 독자: 가이드와 동일(초보~준시니어)
- 형태: **인터랙티브 + 정적 데이터**. 라이브 헬스 연동 없음(노드 상태 데이터는 코드에 박힌 정적 JS 객체).
- **의존성 0 유지**: 인라인 `<svg>` + 인라인 `<script>` + 기존 테마 CSS 변수 재사용. 외부 라이브러리·빌드 없음.

---

## 3. 배치

- §0 "전체 구성도"의 `<pre class="ascii">` 블록을 **완전히 제거**하고 인터랙티브 SVG 블록으로 교체한다.
- 시각적 ASCII는 남기지 않되, **접근성**을 위해 SVG에 `role="img"` + `<title>`/`<desc>` 및 시각적으로 숨긴(screen-reader-only) 토폴로지 텍스트 요약을 제공한다.
- §0의 나머지 텍스트(이벤트 설명 문단, 두 경로 비교표, 경고 박스)는 유지한다.

---

## 4. 레이아웃 — 계층형 흐름 + 상세 패널 (A안 승인)

- 위→아래 흐름: **Client → Gateway → 서비스 5개 → 메시징/데이터**.
- 시각 그룹: 앱(서비스 5) / 메시징(Kafka·Schema Registry) / 데이터(PostgreSQL·Redis·검색엔진).
- 데스크톱: 다이어그램 우측에 상세 패널. 모바일(<880px): 패널이 다이어그램 **아래**로 이동(기존 반응형 분기점 재사용).

---

## 5. 노드 & 엣지 (단일 논리 토폴로지)

**노드(12)** — 그룹별:
- 진입: **Client**, **Gateway**(경로②에만 존재 — 상세에 명시)
- 앱: **platform-svc**, **engagement-svc**, **knowledge-svc**, **learning-card**, **learning-ai**
- 메시징: **Kafka(+Zookeeper)**, **Schema Registry**
- 데이터: **PostgreSQL**, **Redis**, **검색엔진**

**엣지**: Gateway→앱 5개 · 앱→(Kafka·PostgreSQL·Redis) · knowledge-svc/learning-ai→검색엔진 · Schema Registry→Kafka · learning-ai→Kafka.

---

## 6. 노드 상세 패널 데이터 (정적 JS 객체)

각 노드 클릭/포커스 시 표시. 값은 직전 세션에서 두 `docker-compose.yml`로 검증한 것과 동일(추측 금지).

| 필드 | 내용 |
|---|---|
| 이름 · 역할 | 한 줄 설명 |
| 기술 | 예: Spring Boot / JDK 21, FastAPI / Python 3.12 |
| 포트 | 경로①(풀컨테이너) / 경로②(하이브리드) **모두** 표기 |
| 헬스 · 확인 명령 | `curl .../actuator/health` 또는 `/health`, 또는 `docker compose ps` / `docker exec ... kafka-topics --list` 등 |
| 의존성 | 연결된 노드 목록 |

**확정 노드 데이터(요지):**
- Gateway: Spring/JDK21 · ① 없음 / ② :8080 · `curl localhost:8080/actuator/health` · deps redis, 앱 5
- platform-svc: 인증/결제/알림 · ①8080 / ②stub 8081(bootRun 기본 8080) · `/actuator/health` · deps postgres·redis·kafka
- engagement-svc: 참여/활동 · ①8082 · `/actuator/health` · deps postgres·redis·kafka·learning-card
- knowledge-svc: 노트/검색 · ①8083 · `/actuator/health` · deps postgres·redis·kafka·검색엔진
- learning-card: 학습 카드 · ①8084 · `/actuator/health` · deps postgres·redis·kafka
- learning-ai: AI 카드 생성 · FastAPI/Py3.12 · ①8000 / ②8090 · `curl localhost:8000/health`(①)·`:8090`(②) · deps kafka(+db·redis·검색)
- Kafka(+Zookeeper): 이벤트 메시징 · :9092 · `docker exec -it synapse-kafka kafka-topics --list --bootstrap-server localhost:9092` · kafka-init가 토픽 5개 자동 생성
- Schema Registry: Avro 스키마 · ①8085 / ②8086 · `curl localhost:8085/subjects`(①)·`:8086`(②) · deps kafka
- PostgreSQL: DB · :5432 · ① pgvector-pg16 / ② postgres:16-alpine · `docker compose ps`
- Redis: 세션/캐시 · :6379 · `redis-cli ping`
- 검색엔진: :9200 · ① Elasticsearch 8.13 / ② OpenSearch 2.11 · `curl localhost:9200/_cluster/health`

---

## 7. 상호작용 / 접근성

- 노드 클릭/Enter/Space → 우측(또는 하단) 패널 갱신 + 선택 노드 하이라이트 + 연결 엣지 강조.
- 노드는 `tabindex="0"` + `role="button"` + `aria-label`. 상세 패널은 `aria-live="polite"`.
- 첫 진입 시 안내문("노드를 클릭하면 상세가 보입니다") 표시, 선택 시 교체.

---

## 8. 검증

- 브라우저 QA: 12개 노드 클릭 시 패널 정확 갱신, 엣지 강조, 모바일에서 패널 하단 이동, 키보드(Tab→Enter) 동작, 콘솔 에러 0.
- 정확성: 모든 포트·명령을 `synapse-gitops/docker-compose.yml`·`synapse-shared/docker-compose.yml`과 1:1 재대조.

---

## 9. 범위 밖

- 라이브 헬스/상태 연동(kubectl·Prometheus·헬스 폴링)
- 새 페이지/앱, AWS·EKS 토폴로지
- 외부 다이어그램 라이브러리 도입
- 그래프/컨스텔레이션·그룹존 등 A안 외 레이아웃
