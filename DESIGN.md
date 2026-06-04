# Design System — Synapse 문서 / local-k8s 가이드

> 정본 대상: `docs/local-k8s-guide.html` 및 동류의 단일 파일 HTML 개발자 문서 아티팩트.
> `/design-consultation`(2026-06-04)으로 기존 다크 개발자 도구 룩을 정리·고도화하여 작성.

## Product Context
- **What this is:** Synapse 마이크로서비스(gateway + 5개 서비스 + Kafka/Postgres/Redis/OpenSearch)의 인터랙티브 아키텍처 + API 레퍼런스. SVG 시스템 맵, 클릭 상세 패널, 시나리오 플레이어, 검색형 레퍼런스(REST/Kafka 토픽/DTO 카탈로그).
- **Who it's for:** 사내 엔지니어(local-k8s / minikube 로컬 구동).
- **Space/industry:** 내부 개발자 도구 / 시스템 문서화 (peer: Backstage, Swagger/Stripe API 문서, Grafana, AsyncAPI Studio).
- **Project type:** 단일 자체 완결 오프라인 HTML 파일 (빌드·프레임워크·런타임 의존 없음).
- **기억에 남길 한 가지:** "어떤 엔드포인트·토픽이든 몇 초 만에 찾고, 시스템 전체가 어떻게 연결되는지 한눈에 보인다." 모든 결정이 이 목표(밀도 높은 빠른 스캔)를 섬긴다.

## Aesthetic Direction
- **Direction:** Industrial / Utilitarian (다크). 함수 우선, 데이터 밀집. 장식 없음, 타입과 색이 일한다.
- **Decoration level:** minimal. 배경·그라데이션·장식 일절 없음. 유일한 "장식"은 의미를 가진 색과 1px 보더.
- **Mood:** 엔지니어링 산출물처럼 읽힌다. 웹 문서가 아니라 콘솔/스키매틱에 가깝다.
- **Mode:** **다크 전용 (의도적 결정).** 오프라인 단일 파일 도구에 라이트 모드는 범위 외. 추가 시 surface를 재설계하고 의미색 채도 10~20% 감소.

## Typography
단일 패밀리 시스템(Geist) — 일관성과 파일 경량을 동시에. 구조 라벨은 모노로 신호한다(RISK 1).

- **Display / Topbar:** `Geist Mono` 600, 16px, letter-spacing -0.01em — 구조 라벨.
- **Section / 패널 제목 (h3):** `Geist Mono` 600, 18px.
- **Section 헤더 (h4):** `Geist Mono` 600, 12px, UPPERCASE, letter-spacing 0.02em, color `--muted`.
- **Body / UI:** `Geist` 400, 13px, line-height 1.5.
- **Data / Tables:** `Geist` + `font-variant-numeric: tabular-nums` (숫자 칸 정렬). 표 헤더는 `Geist Mono` 11px UPPERCASE, color `--dim`.
- **Code / 식별자:** `Geist Mono` 400. (현행 SFMono/Consolas 교체.)
- **한국어:** 한글 웹폰트는 무거워(2~5MB) 단일 파일 임베드 비현실적. 라틴·숫자·코드는 자체 호스팅 Geist, **한글은 시스템 폴백**: `Pretendard`(설치 시) → `Malgun Gothic` → `Apple SD Gothic Neo`.
- **Font stacks:**
  - `--sans: "Geist","Pretendard","Malgun Gothic","Apple SD Gothic Neo","Segoe UI",sans-serif`
  - `--mono: "Geist Mono","SFMono-Regular",Consolas,"Liberation Mono",monospace`
- **Loading (오프라인 안전) — base64 임베드 필수:** Geist / Geist Mono **woff2 라틴 서브셋을 `@font-face src:url(data:font/woff2;base64,...)`로 HTML에 직접 임베드**한다. 이유: Chrome은 `file://`을 unique origin으로 취급해 외부 `fonts/*.woff2` 상대참조조차 폰트 CORS로 차단한다 → 더블클릭으로 열면 폴백됨. data-URI는 이 제약을 받지 않아 file://에서도 로드되고 단일 자기완결 파일이 된다(+~190KB). **상대경로 외부 파일 방식·CDN(`@import`/`<link>`) 모두 금지.** 출처: jsdelivr `@fontsource/geist-sans`,`geist-mono` (라틴 서브셋). 재생성: woff2 받아 base64 인코딩 후 6개 `@font-face`의 `src`만 교체.
- **Scale (px):** 11(표헤더/푸터) · 12(h4/버튼/표) · 13(본문 기준) · 16(topbar) · 18(h3).

## Color
**핵심: 여기서 색은 미감이 아니라 기능이다. 각 색의 의미를 잠그고, 임의 재도색을 금지한다.**

### Surfaces (어두운 → 밝은)
- `--bg: #0e1116` — 페이지 바닥
- `--panel: #161b22` — 패널 / 카드
- `--surface-2: #21262d` — hover / 선택 / 버튼
- `--line: #30363d` — 보더 / 구분선

### Text tiers (강한 → 약한)
- `--fg: #e6edf3` — 본문
- `--muted: #8b949e` — 보조 / h4
- `--dim: #6e7681` — 최약(표 헤더, deprecated, 푸터)

### Semantic / functional (의미 잠금 — 변경 금지)
| 토큰 | hex | 의미 |
|---|---|---|
| `--rest` | `#58a6ff` 파랑 | REST 엣지 / GET·POST 메서드 |
| `--kafka` | `#d29922` 앰버 | Kafka 엣지 / PUT·PATCH 메서드 |
| `--store` | `#3fb950` 초록 | 데이터스토어 엣지 |
| `--accent` | `#bc8cff` 퍼플 | 브랜드 / 라우트 / 활성 / 포커스 링 |
| `--danger` | `#f85149` 빨강 | DELETE 메서드 / error |

### HTTP 메서드 색상 코딩 (의미색 재사용)
GET → 초록(store) · POST → 파랑(rest) · PUT/PATCH → 앰버(kafka) · DELETE → 빨강(danger) · ROUTE → 퍼플(accent).

### 서비스 노드 식별색 (`SYSTEM` 데이터의 `color`)
서비스별 식별자 용도: platform `#58a6ff`, engagement `#3fb950`, knowledge `#f778ba`, learning-ai `#e3b341`, learning-card `#ff7b72`.
**RISK 3 (선택):** 기능색(파랑/앰버/초록)이 시각적으로 지배하도록 서비스 노드색 채도를 살짝 낮춘다. 미적용 시 노드 무지개가 의미색과 경쟁할 수 있음.

## Spacing
- **Base unit:** 4px
- **Density:** compact (데이터 도구)
- **Scale:** `--xs:4 · --sm:6 · --md:8 · --lg:12 · --xl:16` (+ 2xl:24 · 3xl:32 필요 시)
- 흩어진 인라인 매직넘버(4/6/8/10/12)를 위 변수로 수렴한다.

## Layout
- **Approach:** grid-disciplined (현행 유지).
- **Grid:** `main` = `1fr 340px` / areas `"map panel" "flow panel" "ref ref"`, gap `--lg`.
- **Panel:** 340px 고정, `max-height:80vh`, 스크롤.
- **Max content width:** 없음 (풀블리드 — 도구).
- **Border radius:** `--r-sm:6 · --r-md:8 · --r-lg:10 · pill:9999`.

## Motion
- **Approach:** minimal-functional. 이해를 돕는 전환만.
- **시나리오 dot:** requestAnimationFrame, 단계 이동 ~900ms × speed(0.5x/1x/2x).
- **Highlight / hover:** opacity 전환, `transition 150ms ease` (버튼 border/color 포함).
- **Easing / Duration:** enter ease-out · exit ease-in · move ease-in-out / micro 100ms · short 180ms · medium 300ms.

## Decisions Log
| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-06-04 | 디자인 시스템 최초 정리 (codify & elevate) | `/design-consultation` — 기존 다크 개발자 도구 룩을 문서화하고 약점 보완 |
| 2026-06-04 | 타이포 system-ui → Geist + Geist Mono | "타이포 포기" 기본값 탈출 |
| 2026-06-04 | 폰트 base64 data-URI 임베드 (외부 파일·CDN 금지) | file://은 unique origin이라 외부 woff2 차단 → data-URI만 file:// 더블클릭에서 로드, 단일 자기완결 |
| 2026-06-04 | 구조 라벨(topbar/h3/h4/표헤더/푸터) 모노화 (RISK 1) | 엔지니어링 산출물 톤, 도구 정체성 |
| 2026-06-04 | 색 의미 잠금 + 텍스트 3티어(fg/muted/dim) | 색은 기능이므로 임의 재도색 방지, 정보 위계 명확화 |
| 2026-06-04 | 다크 전용 결정 | 오프라인 단일 파일 도구에 라이트 모드는 범위 외 |
