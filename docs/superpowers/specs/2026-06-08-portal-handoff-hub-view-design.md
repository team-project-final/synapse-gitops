# 포털 핸드오프 허브 뷰 — 설계 (하위프로젝트 B)

- 작성일: 2026-06-08 (W5 Day1)
- 대상 리포: `synapse-gitops` (`site/` Flutter 포털 + `site/scripts/` 빌드 파이프라인)
- 출처: B2 "포털 핸드오프 허브 뷰"(W3 정리·마감에서 W4 이월, "파이프라인 확장 필요"). 상위 설계 `2026-05-22-unified-handoff-hub-spoke-design.md`
- 선행: W3/W4 감사(`2026-06-08-w3-w4-incomplete-audit-design.md`)에서 B2를 하위프로젝트로 분리

## 1. 목적과 범위

`HANDOFF_HUB.md`(synapse-shared)의 **환경×서비스 상태**를 Flutter Runbook Site에 **전용 시각 대시보드 뷰**로 surface 한다. 현재 허브는 'management' 카테고리 raw 마크다운으로만 포털에 들어가 있어, 크로스레포 상태를 한눈에 보기 어렵다(이 가시성 부재가 W3/W4 감사에서 #92 상태 불일치로 드러난 문제와 동일하다).

### 범위

- `site/scripts/parse_hub.mjs` — `HANDOFF_HUB.md`의 "환경별 서비스 상태" 표를 구조화 파싱
- `site/scripts/build_docs.mjs` — 허브 감지 시 `assets/docs/hub.json` 추가 산출(허브는 'management' doc으로도 계속 수집)
- Flutter `/hub` 라우트 + `HubPage`(상태 배지 그리드 + 나머지 마크다운) + 네비 항목

### 비범위 (명시 제외)

- 표 외 섹션(마일스톤·스포크·의존맵)의 구조화 파싱 — 마크다운으로 렌더(하이브리드)
- `HANDOFF_HUB.md` 형식/내용 변경 — 단일 진실원으로 그대로 사용, 유지자 워크플로 불변
- `deploy-pages.yml` 트리거 확장(shared push 반영) — 기존 한계로 기록만(§5)
- 포털 전체 다크 테마 재설계 — 기존 라이트/Material3 미감 유지

### 성공 기준

`node build_docs.mjs`가 `assets/docs/hub.json`(파싱된 statusTable + bodyMarkdown) 생성 + `/hub`가 서비스×환경 색상 배지 그리드와 나머지 마크다운을 렌더 + 허브 부재/파싱 실패 시 graceful 폴백 + parser/model 테스트 통과.

## 2. 결정 사항 (브레인스토밍 합의)

| 결정 | 선택 | 근거 |
|------|------|------|
| 뷰 깊이 | **하이브리드** — 핵심 표 1개만 파싱, 나머지 마크다운 | 시각 대시보드 가치 + 표 파싱 리스크 최소화 |
| 미감 기준 | **기존 포털 일관**(라이트/Material3/Noto Sans KR) | DESIGN.md는 "단일 파일 HTML 아티팩트" 범위 한정 → 포털은 별개 surface. 기존 위젯 재사용 |
| 단일 진실원 | 기존 `HANDOFF_HUB.md` 마크다운 | 유지자 워크플로 불변, 중복 데이터 관리(yaml 등) 회피 |
| 뷰 배치 | **신규 `/hub` 라우트**(기존 `/dashboard` 불변) | 기존 dashboard=문서 중심, hub=프로젝트 상태 중심. 추가만(additive) |
| 파싱 실패 대응 | statusTable `[]` → 마크다운만 렌더 | 형식 변경에 깨지지 않음 |

## 3. 아키텍처 · 데이터 흐름

```
HANDOFF_HUB.md (shared, 단일 진실원)
   │  build_docs.mjs (빌드 시 shared sibling 체크아웃 — 기존 deploy-pages.yml)
   ▼
parse_hub.mjs ── "환경별 서비스 상태" 표만 구조화
   ▼
assets/docs/hub.json  { title, lastUpdated, envs[], statusTable[], bodyMarkdown }
   │  (파싱 실패 → statusTable: [])
   ▼
Flutter HubPage (/hub)
   · statusTable → 서비스×환경 StatusBadge 그리드
   · bodyMarkdown → 기존 MarkdownViewer
```

### 상태 enum (허브 §1 범례와 1:1)

| 이모지 | status | 색(Material 톤) |
|---|---|---|
| ✅ | healthy | green `0xFF16A34A` |
| 🔄 | pending | blue `0xFF2563EB` |
| ⚠️ | degraded | amber `0xFFD97706` |
| 🔴 | down | red `0xFFDC2626` |
| ⏳ | planned | grey `0xFF9CA3AF` |
| — | na | "—" 텍스트(연회색), 배지 없음 |

셀 텍스트(예 `5/5(06-08)`)는 선두 이모지 제거 후 배지 라벨로 보존.

## 4. 컴포넌트

### 4.1 `site/scripts/parse_hub.mjs` (신규)

```js
const STATUS_MAP = { '✅':'healthy', '🔄':'pending', '⚠️':'degraded', '🔴':'down', '⏳':'planned', '—':'na' };

export function parseHubStatusTable(markdown) {
  // "### 환경별 서비스 상태" 섹션 → 그 아래 첫 마크다운 표를 파싱.
  // 헤더 행에서 envs 추출(첫 컬럼 "서비스" 제외).
  // 각 데이터 행 → { service, cells: [{ env, status, label }] } (컬럼 인덱스 기반).
  // status = 셀 선두 이모지 매핑(없으면 'na'), label = 이모지/마크다운볼드 제거 후 트림.
  // 섹션/표 없으면 [] 반환.
}

export function buildHubModel(markdown, lastModified) {
  const { envs, rows } = (() => { const t = parseHubStatusTable(markdown); return { envs: <헤더에서>, rows: t }; })();
  return {
    title: <첫 '# ' 라인>,
    lastUpdated: lastModified,
    envs,                  // [] 가능
    statusTable: rows,     // [] 가능
    bodyMarkdown: markdown,
  };
}
```

- 단일 책임(허브 파싱)으로 분리 → `build_docs.mjs` 비대화 방지.

### 4.2 `site/scripts/build_docs.mjs` (수정, 최소 침습)

- 파일 루프에서 `relKey === 'shared/docs/project-management/HANDOFF_HUB.md'` 감지 시:
  - `import { buildHubModel } from './parse_hub.mjs'`
  - `fs.writeFileSync(path.join(OUTPUT_DIR, 'hub.json'), JSON.stringify(buildHubModel(body, getLastModified(absPath)), null, 2))`
- 허브는 기존 'management' doc 수집 경로도 **그대로 유지**(검색/직접열람). hub.json은 추가 산출물.
- 허브 파일 부재 시 hub.json 미생성(Flutter graceful 처리).

### 4.3 Flutter (신규/수정)

| 파일 | 책임 |
|---|---|
| `lib/models/hub.dart` (신규) | `HubData`/`HubStatusRow`/`HubStatusCell` + `factory fromJson` (doc.dart 패턴) |
| `lib/widgets/status_badge.dart` (신규) | 셀 1개 = 둥근 칩(배경=상태색 12% opacity, 텍스트=상태색, 라벨=셀 텍스트). na는 "—" 텍스트 |
| `lib/widgets/status_legend.dart` (신규) | 상태 범례(작은 칩 줄) |
| `lib/pages/hub_page.dart` (신규) | hub.json 로드 → 헤더(title+lastUpdated) + 범례 + 상태 그리드 + `MarkdownViewer(data: bodyMarkdown)`. SingleChildScrollView, 기존 DashboardPage 패턴 |
| `lib/app.dart` (수정) | `/hub` GoRoute + AppBar `Icons.hub` 액션 |
| `lib/widgets/sidebar.dart` (수정) | '현황' 아래 `ListTile('핸드오프 허브' → /hub)` |

**HubPage graceful 처리**
- `hub.json` 로드 실패/부재 → "핸드오프 허브 데이터 없음(빌드에 shared 미포함)" 안내 + 정상 종료
- `statusTable` 비어 있음 → 그리드 생략, bodyMarkdown만 렌더
- 좁은 화면(<800px) → 그리드 가로 스크롤(`SingleChildScrollView(scrollDirection: horizontal)`)

## 5. 테스트 · 빌드 통합 · 엣지케이스

### 테스트

- `site/scripts/parse_hub.test.mjs` (node `--test`):
  - 정상 표 → 기대 statusTable(서비스명·status·라벨) 일치
  - 이모지 6종 매핑 정확(✅/🔄/⚠️/🔴/⏳/—)
  - 표 없는 마크다운 → `[]`
  - 헤더만·행 없음 → `[]`
  - 셀 내 복수 토큰(`✅ **5/5(06-08)**`) → status=healthy, label=`5/5(06-08)`
- `site/test/hub_model_test.dart` (Flutter test, `runbook_model_test.dart` 패턴):
  - `HubData.fromJson` 라운드트립 + status→color 매핑 + 빈 statusTable 처리

### 빌드 통합

- `hub.json`은 기존 `OUTPUT_DIR(../assets/docs/)`에 기록 → `deploy-pages.yml`이 이미 `assets/docs/` 번들 → **워크플로 변경 불필요**.
- shared는 deploy-pages.yml이 이미 sibling 체크아웃 → 허브 접근 가능.
- 로컬 검증: `cd site/scripts && NO_AI=1 node build_docs.mjs` → `../assets/docs/hub.json` 생성 확인.

### 엣지케이스 / 알려진 한계

- **트리거 갭(기존 한계, 범위 밖)**: `deploy-pages.yml`은 gitops push에만 트리거 → shared HANDOFF_HUB 갱신은 다음 gitops push 때 반영. 기록만(트리거 확장은 별도 작업).
- 표 형식 내성: 파서는 **컬럼 인덱스 + 헤더 추출** 기반 → 환경 컬럼 추가/순서 변경에도 헤더 기준 동작. "환경별 서비스 상태" 섹션 제목 변경 시 폴백.
- 복수 이모지 셀은 **선두 이모지**만 status.

## 6. 산출물 요약

- **신규:** `site/scripts/parse_hub.mjs`·`parse_hub.test.mjs`, `site/lib/models/hub.dart`, `site/lib/pages/hub_page.dart`, `site/lib/widgets/status_badge.dart`·`status_legend.dart`, `site/test/hub_model_test.dart`
- **수정:** `site/scripts/build_docs.mjs`(허브 감지+hub.json), `site/lib/app.dart`(/hub 라우트+nav), `site/lib/widgets/sidebar.dart`(nav 항목)
- **데이터:** `site/assets/docs/hub.json`(빌드 산출)
