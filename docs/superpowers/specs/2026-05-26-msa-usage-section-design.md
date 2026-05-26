# "서비스 사용·확인하기" 섹션 설계 스펙

> **작성일**: 2026-05-26
> **범위**: `local-msa-setup.html`에 설치 후 서비스를 열어보고·호출하고·이벤트를 관찰하는 사용법 섹션 추가
> **산출물**: `synapse-gitops/docs/local-msa-setup.html` (기존 단일 HTML 수정)

---

## 1. 목적

설치 경로(§3 풀 컨테이너 / §4 하이브리드)로 서비스가 뜬 뒤, 신규 팀원이 **실제로 열어보고·호출하고·이벤트가 흐르는 것을 눈으로 확인**하도록 사용법을 추가한다. "설치는 했는데 그래서 뭘 보지?"를 해소하고, MSA가 이벤트로 실제 동작함을 체감하게 한다.

## 2. 범위 (분해 결과 — A)

이 스펙은 **compose로 띄운 서비스의 사용·확인(A)** 만 다룬다. **동작하는 minikube/로컬 k8s 실행 경로(B)** 는 별도 스펙으로 분리한다 — `apps/` 매니페스트가 EKS 전용(ExternalSecret/ClusterSecretStore→AWS, ghcr 이미지)이라 로컬 overlay 신설이 필요한 별도 엔지니어링이기 때문.

- **In scope**: Swagger UI 뷰, 상태/헬스 뷰, API 호출 예제(gateway/직접), Kafka 이벤트 실시간 관찰, DB/Redis/검색 데이터 확인.
- **Out of scope**: minikube/kind 실행 경로(B), 라이브 모니터링 대시보드, 새 페이지/앱.

## 3. 배치

- **새 §5 "서비스 사용·확인하기"** 를 §4(하이브리드)와 기존 §5(목업·시드 데이터) 사이에 삽입.
- 뒤 섹션 번호 배지 한 칸씩 이동: 목업데이터 §5→**§6**, 트러블슈팅 §6→**§7**, 다음단계 §7→**§8**. 앵커 `id`(`#data`/`#trouble`/`#next`)는 유지 → 기존 내부 링크 영향 없음. TOC는 JS 자동 생성이라 항목만 추가됨.
- 새 섹션 `id`는 `usage`. 진행 체크박스(`.step`)·복사 버튼·`<details>` 심화 등 기존 패턴 재사용.

## 4. 섹션 구성

### 5.1 브라우저로 열어보는 뷰
- ⭐ **learning-ai Swagger UI**: `http://localhost:8000/docs`(경로①) / `http://localhost:8090/docs`(경로②), ReDoc `/redoc`. "Try it out"으로 API 직접 실행. **이 프로젝트의 유일한 GUI API 뷰.**
- 상태 뷰(브라우저로 열리는 JSON): 서비스 `/actuator/health`, schema-registry `:8085/subjects`(②:8086), 검색 `:9200/_cluster/health`.
- 심화: Spring 서비스엔 Swagger UI가 없는 이유(springdoc 미적용 → actuator 엔드포인트만).

### 5.2 API 호출 예제 — 두 경로
- 경로②(Gateway 경유): `curl http://localhost:8080/<route>`.
- 경로①(직접): 서비스 포트로 직접 `curl`.
- 심화: Gateway 라우팅 규칙(prefix→서비스 매핑).
- **계획 단계 검증**: 실제 라우트/경로는 `synapse-gateway`의 라우팅 설정(application.yml 등)으로 확인해 채운다. 검증된 GET 엔드포인트가 없으면 health 라우팅 예제로 대체한다.

### 5.3 Kafka 이벤트 실시간 관찰
- `docker exec -it synapse-kafka kafka-console-consumer --bootstrap-server localhost:9092 --topic <토픽> --from-beginning`
- 토픽 5개: `platform.auth.user-registered-v1`, `knowledge.note.note-created-v1`, `knowledge.note.note-updated-v1`, `learning.card.review-completed-v1`, `learning.ai.cards-generated-v1`.
- 한 터미널에서 구독 → 다른 터미널에서 액션 → 이벤트 출력 관찰. "MSA가 이벤트로 도는 것을 눈으로."

### 5.4 데이터 직접 확인
- PostgreSQL: `docker exec -it synapse-postgres psql -U <user> -d <db> -c "\dt"`
- Redis: `docker exec -it synapse-redis redis-cli -a <pw> keys '*'`
- 검색: `curl http://localhost:9200/_cat/indices?v`
- **계획 단계 검증**: postgres user/db, redis 비밀번호는 두 compose(`synapse-gitops`/`synapse-shared`) 기본값이 다를 수 있어 각 파일에서 1:1 확인해 채운다(경로별 병기).

## 5. 레벨링 / 기술

- 기존 가이드 패턴 그대로: 번호 단계 + 코드블록(복사 버튼) + `<details class="deep">` 심화. 단일 HTML, 의존성 0.
- 경로①/② 포트 차이는 명령에 주석으로 병기.

## 6. 검증

- 브라우저 QA: 새 §5 렌더, 코드블록 복사, `<details>` 동작, TOC에 새 항목 추가, 번호 배지 §6/§7/§8로 이동 확인, 콘솔 에러 0.
- 정확성: Swagger 경로·포트·Kafka 토픽명·gateway 라우트·DB 자격증명을 실제 파일(learning-ai `app/main.py`, `synapse-gateway` 설정, 두 `docker-compose.yml`)과 1:1 대조.

## 7. 범위 밖 (재확인)

- minikube/kind 로컬 k8s 실행 경로(별도 스펙 B)
- 라이브 모니터링/관측 대시보드(Grafana 등)
- 기존 §3/§4 설치 절차 변경(이 섹션은 "설치 후"만 다룸)
