# 로컬 MSA 개발환경 온보딩 가이드 설계 스펙

> **작성일**: 2026-05-26
> **범위**: 팀원이 자기 PC에서 Synapse MSA를 처음 띄우는 로컬 개발환경 세팅 (AWS 배포 제외)
> **산출물**: `docs/local-msa-setup.html` (단일 자체완결 HTML)

---

## 1. 목적

신규 합류한 팀원이 자기 PC에서 Synapse MSA를 **처음부터 띄워 동작을 확인하기까지**를, "따라만 하면 되는 단일 경로"로 안내한다. 기존 `synapse-developer-guide.md`(올인원·마크다운)와 분산된 런북은 로컬·AWS·운영을 한 문서에 섞어 두어, 로컬 환경만 세팅하려는 신규 팀원에게 진입 장벽이 된다. 이 가이드는 **로컬 세팅에만 집중**하고, 클라우드 배포는 기존 문서로 링크만 한다.

---

## 2. 대상 독자 — 초보 ~ 준시니어

- **초보**: Docker/Spring/Kafka 경험이 얕은 신규 팀원. 번호 단계를 위→아래로 따라가면 막힘없이 완주해야 한다.
- **준시니어**: 같은 문서에서 "왜 이렇게 동작하는가"(의존성 체인, mavenLocal, 헬스 게이트 등)를 얻고 싶어 한다.
- 두 수준을 **하나의 문서**에서 동시에 만족시키되, 초보의 완주 경험을 해치지 않는다.

---

## 3. 문서 위치 / 형태 / 언어

- **위치**: `synapse-gitops/docs/local-msa-setup.html`
- **형태**: **단일 자체완결 HTML 1개**. CSS·JS 전부 인라인, 외부 의존성 0. 더블클릭으로 열리고, Slack 공유·오프라인 열람 가능. 빌드/서버 불필요.
- **언어**: 한국어 (팀 문서 관례 일치)
- **기존 문서와의 관계**: **독립 온보딩 가이드(신규 작성)**. 기존 `synapse-developer-guide.md`·런북은 건드리지 않고 "더 깊이 보기"로 링크만. 단, `README.md`와 `synapse-developer-guide.md`(로컬 섹션)에서 이 HTML로 향하는 링크 1줄씩 추가.

---

## 4. 레벨링 메커니즘 — 펼침형 심화 콜아웃 (패턴 A 승인)

- 본문은 **번호 단계의 선형 흐름**. 초보는 위→아래로만 읽고 따라 하면 된다.
- 각 단계에 필요 시 `<details>` 기반 **"▸ 왜? / 심화"** 콜아웃을 둔다. 준시니어가 펼쳐 원리·내부 동작·트러블슈팅을 본다. 순수 HTML이라 JS 의존 최소.
- 모드 토글(콘텐츠 2벌 관리)·난이도 배지 사이드바 방식은 채택하지 않는다.

---

## 5. 콘텐츠 구조

좌측 sticky 목차(TOC) + 본문 단일 스크롤. 모바일에서는 TOC 접힘.

| # | 섹션 | 내용 | 심화(`<details>`) 후보 |
|---|---|---|---|
| 0 | 개요 | 무엇을 만들게 되나 + 아키텍처 한 장(인프라 6 + 앱 5 + Gateway, Kafka 이벤트 흐름 요약) | 이벤트 기반 MSA가 왜 이 구성인가 |
| 1 | 사전 준비 | Docker Desktop / JDK 21(Temurin) / Git / Python 3.11 / (선택)Flutter. 확인 명령 + Windows 설치. **AWS CLI·kubectl 불필요** 명시 | JDK 21 toolchain·Temurin 이유 |
| 2 | 레포 클론 | 필요한 레포를 어디에 클론할지 | 레포별 역할 요약 |
| 3 | 공통 모듈 빌드 | `synapse-shared` → mavenLocal publish | **왜 shared를 먼저 빌드해야 서비스가 컴파일되나** |
| 4 | 인프라 실행 (필수 기반) | `cd synapse-shared && docker compose up -d` → 인프라 6개. `kafka-init`가 토픽 자동 생성 | depends_on healthy 체인(zookeeper→kafka→schema-registry) |
| 5 | 인프라 검증 | `docker compose ps` / 헬스 / kafka-topics / psql | 헬스체크 기준표 |
| 6 | ① 풀 컨테이너 경로 (초보 빠른 체험) | 앱까지 한 번에 기동, 전체 헬스 OK 확인 | 메모리 설계(8GB 제한) |
| 7 | ② 하이브리드 경로 (실제 개발) | 인프라만 컨테이너 + 앱은 `./gradlew bootRun`/IDE, learning-ai는 uvicorn. 코드 수정→재기동 루프 | IDE 환경변수·프로파일 주입, 디버그 attach |
| 8 | 동작 확인 / 스모크 테스트 | Gateway 경유 + 직접 호출 | Gateway 라우팅 동작 |
| 9 | (선택) 목업·시드 데이터 | `moking-data-guide` 연결 | — |
| 10 | 트러블슈팅 | 포트 충돌, 검색엔진 OOM, Apple Silicon 에뮬레이션, shared 미빌드, .env 누락 | 각 증상의 근본 원인 |
| 11 | 다음 단계 / 더 깊이 보기 | `synapse-developer-guide.md`·AWS 배포 런북 링크 | — |

---

## 6. 시각 / 기술 구현

- 단일 HTML, 의존성 0. 인라인 `<style>` + 최소 인라인 `<script>`.
- **JS 기능**: ① TOC 스크롤 하이라이트(현재 섹션), ② 코드 블록 복사 버튼, ③ `<details>` 펼침(네이티브), ④ 단계별 ✅ 체크박스 진행도(`localStorage` 저장 → 온보딩 완주감), ⑤ OS 탭 토글(Windows / macOS·Linux)은 명령이 갈리는 곳만.
- **테마**: 깔끔한 라이트 본문 + 다크 코드 블록. 좌측 sticky TOC.
- 접근성: 의미적 heading 구조(`h1`→`h2`→`h3`), 키보드로 `<details>`·복사 버튼 동작.

---

## 7. 원본 자료 매핑 (중복 작성 방지)

| 가이드 섹션 | 근거 파일 |
|---|---|
| 아키텍처·이벤트 흐름 | `docs/synapse-developer-guide.md` §1, §2 |
| 인프라 구성·헬스·메모리·트러블슈팅 | `docs/docker-compose-workflow-guide.md` |
| 정식 로컬 인프라(compose) | `synapse-shared/docker-compose.yml` + `synapse-shared/scripts/` |
| 사전 도구·레포 역할 | `docs/synapse-developer-guide.md` §3, §4 |
| 목업·시드 데이터 | `moking-data-guide/` |

---

## 8. 계획 단계에서 확정할 미해결 항목

⚠️ **"풀 컨테이너" 경로의 정식 compose 결정 (필수)**

`synapse-shared/docker-compose.yml`(소스 빌드, postgres:16-alpine, kafka 7.7.0, **OpenSearch 2.11**, schema-registry **8086**)과 `synapse-gitops/docker-compose.yml`(ghcr 이미지 pull, pgvector pg16, kafka 7.6.1, **Elasticsearch 8.13**, schema-registry 다른 포트)이 **이미지 출처·검색엔진·포트에서 갈린다.** 기존 두 문서도 포트/엔진 표기가 불일치한다(8081 vs 8086, ES vs OpenSearch).

- 온보딩에는 사전 빌드된 이미지가 없어도 되는 쪽(= `synapse-shared` 소스 빌드 경로)이 유리할 가능성이 높다.
- 계획(writing-plans) 단계에서 **두 compose 파일을 정밀 검증**해, 포트·검색엔진·앱 기동 방식(shared compose가 jar를 어떻게 빌드/주입하는지 포함)을 확인하고 **단 하나의 정답 경로로 고정**한다. 가이드 내 모든 포트·명령은 이 확정값과 일치해야 한다.

---

## 9. 검증

- **렌더 검증**: 브라우저로 실제 열어 레이아웃·TOC 하이라이트·복사 버튼·`<details>`·체크박스(localStorage) 동작 확인.
- **정확성 검증**: 가이드의 모든 명령·포트·경로를 §8에서 확정한 실제 메커니즘과 1:1 대조. 특히 §6(풀 컨테이너)·§7(하이브리드).

---

## 10. 범위 밖 (Out of Scope)

- AWS/EKS·Terraform·ArgoCD·SSM Bastion·시크릿 동기화 등 클라우드 배포 (기존 문서가 담당, 링크만)
- kind 로컬 k8s 경로
- 기존 `synapse-developer-guide.md`·런북 내용 수정/통합 (링크 추가만)
- CI/CD, 모니터링 대시보드
