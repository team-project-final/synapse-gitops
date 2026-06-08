# 포털 핸드오프 허브 뷰 — 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `HANDOFF_HUB.md`(shared)의 환경×서비스 상태를 Flutter Runbook Site에 색상 배지 대시보드 뷰(`/hub`)로 surface — 파이프라인(parse_hub.mjs)이 표를 hub.json으로 구조화, Flutter HubPage가 렌더, 나머지는 마크다운, 부재/실패 시 graceful 폴백.

**Architecture:** `parse_hub.mjs`가 허브 마크다운의 "환경별 서비스 상태" 표만 구조화 → `build_docs.mjs`가 `assets/docs/hub.json` 추가 산출 → Flutter `HubPage`가 statusTable을 StatusBadge 그리드로, bodyMarkdown을 기존 MarkdownViewer로 렌더. 단일 진실원 = 기존 허브 마크다운(유지자 워크플로 불변). 추가만(기존 `/dashboard` 불변).

**Tech Stack:** Node ESM(`node --test`), Flutter web(Material3, go_router, flutter_markdown), 기존 `site/` 포털.

**전제 사실 (검증됨):**
- `site/scripts/build_docs.mjs`: `WORKSPACE=../../../`, `SHARED_DOCS=synapse-shared/docs`, `OUTPUT_DIR=../assets/docs`, 파일 루프에서 `relKey` 보유, `getLastModified(absPath)` 존재
- 허브 파일 relKey = `shared/docs/project-management/HANDOFF_HUB.md`
- `site/pubspec.yaml`이 `assets/docs/` 번들 → hub.json 자동 포함
- 모델 패턴 = `factory X.fromJson(Map<String, dynamic> json)`, 테스트 = `flutter_test` group/test/expect
- `site/scripts/package.json`: `type: module`, dep `gray-matter`
- 스펙: `docs/superpowers/specs/2026-06-08-portal-handoff-hub-view-design.md`
- 브랜치 `feat/portal-handoff-hub-view`(스펙 커밋 위에 계속), 작업 디렉터리 = 리포 루트

---

### Task 1: `parse_hub.mjs` 파서 (TDD)

**Files:**
- Create: `site/scripts/parse_hub.mjs`
- Create: `site/scripts/parse_hub.test.mjs`
- Modify: `site/scripts/package.json` (test 스크립트 추가)

- [ ] **Step 1: 실패 테스트 작성** — `site/scripts/parse_hub.test.mjs`

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseHubStatusTable, buildHubModel } from './parse_hub.mjs';

const SAMPLE = `# Synapse 통합 핸드오프 허브

> 최종 갱신: 2026-06-08

## 1. 프로젝트 상태 대시보드

### 환경별 서비스 상태

> 블록쿼트 노이즈 라인

| 서비스 | 로컬 compose | dev (EKS) | staging | prod |
|---|---|---|---|---|
| platform-svc | ✅ Healthy | ✅ **5/5(06-08)** | ✅ 5/5(06-08, CrashLoop 해소) | ⏳ W5 |
| gateway | ✅ Healthy | ✅ 5/5(06-08) | — | ⏳ W5 |

> 표 뒤 블록쿼트

### 인프라 상태

| 컴포넌트 | 상태 |
|---|---|
| EKS | ✅ ACTIVE |
`;

test('parseHubStatusTable: envs + rows 파싱', () => {
  const { envs, rows } = parseHubStatusTable(SAMPLE);
  assert.deepEqual(envs, ['로컬 compose', 'dev (EKS)', 'staging', 'prod']);
  assert.equal(rows.length, 2);
  assert.equal(rows[0].service, 'platform-svc');
  assert.equal(rows[0].cells.length, 4);
});

test('parseHubStatusTable: 선두 이모지 status 매핑 + 라벨 정리', () => {
  const { rows } = parseHubStatusTable(SAMPLE);
  const platformDev = rows[0].cells[1]; // dev (EKS)
  assert.equal(platformDev.env, 'dev (EKS)');
  assert.equal(platformDev.status, 'healthy');
  assert.equal(platformDev.label, '5/5(06-08)'); // ✅ 와 ** 제거
});

test('parseHubStatusTable: planned/na 매핑', () => {
  const { rows } = parseHubStatusTable(SAMPLE);
  assert.equal(rows[0].cells[3].status, 'planned'); // ⏳ W5
  assert.equal(rows[1].cells[2].status, 'na');      // — (gateway staging)
});

test('parseHubStatusTable: 인프라 표는 잡지 않음(첫 표만)', () => {
  const { rows } = parseHubStatusTable(SAMPLE);
  assert.ok(rows.every(r => r.service !== 'EKS'));
});

test('parseHubStatusTable: 섹션 없으면 빈 결과', () => {
  const { envs, rows } = parseHubStatusTable('# 제목\n\n표 없음');
  assert.deepEqual(envs, []);
  assert.deepEqual(rows, []);
});

test('buildHubModel: title/lastUpdated/bodyMarkdown 포함', () => {
  const m = buildHubModel(SAMPLE, '2026-06-08');
  assert.equal(m.title, 'Synapse 통합 핸드오프 허브');
  assert.equal(m.lastUpdated, '2026-06-08');
  assert.equal(m.statusTable.length, 2);
  assert.ok(m.bodyMarkdown.includes('환경별 서비스 상태'));
});
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd site/scripts && node --test parse_hub.test.mjs`
Expected: FAIL — `Cannot find module './parse_hub.mjs'`

- [ ] **Step 3: 파서 구현** — `site/scripts/parse_hub.mjs`

```js
// HANDOFF_HUB.md "환경별 서비스 상태" 표만 구조화 파싱. 실패 시 빈 결과 반환(폴백).

const STATUS_MAP = {
  '✅': 'healthy',
  '🔄': 'pending',
  '⚠️': 'degraded',
  '🔴': 'down',
  '⏳': 'planned',
  '—': 'na',
};

function splitRow(line) {
  return line.trim().replace(/^\|/, '').replace(/\|$/, '').split('|').map((s) => s.trim());
}

function parseCell(raw) {
  const text = (raw ?? '').trim();
  if (text === '' || text === '—' || text === '-') return { status: 'na', label: '' };
  for (const [emoji, status] of Object.entries(STATUS_MAP)) {
    if (text.startsWith(emoji)) {
      const label = text.slice(emoji.length).replace(/\*\*/g, '').trim();
      return { status, label };
    }
  }
  return { status: 'na', label: text.replace(/\*\*/g, '').trim() };
}

export function parseHubStatusTable(markdown) {
  const lines = markdown.split('\n');
  const start = lines.findIndex((l) => /^#{2,4}\s+환경별 서비스 상태/.test(l));
  if (start === -1) return { envs: [], rows: [] };

  let header = -1;
  for (let j = start + 1; j < lines.length; j++) {
    if (lines[j].trim().startsWith('|')) { header = j; break; }
    if (/^#{1,4}\s/.test(lines[j])) break; // 다음 헤딩 전 표 없음
  }
  if (header === -1) return { envs: [], rows: [] };

  const headerCells = splitRow(lines[header]);
  if (headerCells.length < 2) return { envs: [], rows: [] };
  const envs = headerCells.slice(1);

  const rows = [];
  for (let j = header + 2; j < lines.length; j++) { // header+1 = 구분선
    const line = lines[j];
    if (!line.trim().startsWith('|')) break; // 표 종료
    const cells = splitRow(line);
    const service = (cells[0] ?? '').replace(/\*\*/g, '').trim();
    if (!service) continue;
    const cellData = envs.map((env, k) => {
      const { status, label } = parseCell(cells[k + 1]);
      return { env, status, label };
    });
    rows.push({ service, cells: cellData });
  }
  return { envs, rows };
}

export function buildHubModel(markdown, lastModified) {
  const titleLine = markdown.split('\n').find((l) => l.startsWith('# '));
  const { envs, rows } = parseHubStatusTable(markdown);
  return {
    title: titleLine ? titleLine.replace(/^#\s+/, '').trim() : 'Handoff Hub',
    lastUpdated: lastModified ?? '',
    envs,
    statusTable: rows,
    bodyMarkdown: markdown,
  };
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd site/scripts && node --test parse_hub.test.mjs`
Expected: PASS — 6 tests passed

- [ ] **Step 5: package.json test 스크립트 추가**

`site/scripts/package.json`의 `scripts`에 추가:
```json
    "test": "node --test"
```
(기존 `build`/`build:no-ai` 유지, `test` 한 줄 추가)

- [ ] **Step 6: 커밋**

```bash
git add site/scripts/parse_hub.mjs site/scripts/parse_hub.test.mjs site/scripts/package.json
git commit -m "feat(portal): HANDOFF_HUB 상태 표 파서 parse_hub.mjs + 단위 테스트"
```

---

### Task 2: `build_docs.mjs` 허브 감지 + hub.json 산출

**Files:**
- Modify: `site/scripts/build_docs.mjs`

- [ ] **Step 1: import 추가** — `build_docs.mjs` 상단 import 블록(라인 4 `import matter` 다음)에 추가

```js
import { buildHubModel } from './parse_hub.mjs';
```

- [ ] **Step 2: 허브 감지 → hub.json 기록**

`build_docs.mjs`의 `main()` 파일 루프 안, `indexEntries.push({...})` 직후(루프 끝 부분)에 추가:

```js
    if (relKey === 'shared/docs/project-management/HANDOFF_HUB.md') {
      const hubModel = buildHubModel(body, getLastModified(absPath));
      fs.writeFileSync(
        path.join(OUTPUT_DIR, 'hub.json'),
        JSON.stringify(hubModel, null, 2),
      );
      console.log(`Wrote hub.json (statusTable rows: ${hubModel.statusTable.length})`);
    }
```

(허브는 기존 'management' doc 수집 경로도 그대로 유지 — 이 블록은 추가 산출물만.)

- [ ] **Step 3: 로컬 빌드 검증**

Run: `cd site/scripts && NO_AI=1 node build_docs.mjs`
Expected: 출력에 `Wrote hub.json (statusTable rows: 6)` (또는 현재 허브 서비스 수) 포함

- [ ] **Step 4: hub.json 내용 확인**

Run: `node -e "const h=require('./site/assets/docs/hub.json'); console.log(h.title, '| rows:', h.statusTable.length, '| envs:', h.envs.join(','))"`
Expected: `Synapse 통합 핸드오프 허브 | rows: 6 | envs: 로컬 compose,dev (EKS),staging,prod` (행 수는 허브 현재 상태에 따름, 0 아님)

- [ ] **Step 5: 커밋** (hub.json은 빌드 산출물 — gitignore 여부 확인 후 코드만 커밋)

```bash
git add site/scripts/build_docs.mjs
git commit -m "feat(portal): build_docs가 HANDOFF_HUB 감지 시 hub.json 산출"
```

---

### Task 3: `hub.dart` 모델 (TDD)

**Files:**
- Create: `site/lib/models/hub.dart`
- Create: `site/test/hub_model_test.dart`

- [ ] **Step 1: 실패 테스트 작성** — `site/test/hub_model_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:synapse_runbooks/models/hub.dart';

void main() {
  group('HubData model', () {
    test('fromJson 파싱', () {
      final json = {
        'title': 'Synapse 통합 핸드오프 허브',
        'lastUpdated': '2026-06-08',
        'envs': ['로컬 compose', 'dev (EKS)', 'staging', 'prod'],
        'statusTable': [
          {
            'service': 'platform-svc',
            'cells': [
              {'env': '로컬 compose', 'status': 'healthy', 'label': 'Healthy'},
              {'env': 'prod', 'status': 'planned', 'label': 'W5'},
            ],
          },
        ],
        'bodyMarkdown': '# 제목\n\n본문',
      };

      final hub = HubData.fromJson(json);

      expect(hub.title, 'Synapse 통합 핸드오프 허브');
      expect(hub.lastUpdated, '2026-06-08');
      expect(hub.envs.length, 4);
      expect(hub.statusTable.length, 1);
      expect(hub.statusTable[0].service, 'platform-svc');
      expect(hub.statusTable[0].cells[0].status, 'healthy');
      expect(hub.statusTable[0].cells[1].label, 'W5');
      expect(hub.bodyMarkdown, contains('본문'));
    });

    test('빈 statusTable 처리', () {
      final hub = HubData.fromJson({
        'title': 'T',
        'lastUpdated': '',
        'envs': [],
        'statusTable': [],
        'bodyMarkdown': 'x',
      });
      expect(hub.statusTable, isEmpty);
      expect(hub.envs, isEmpty);
    });

    test('누락 필드 graceful 기본값', () {
      final hub = HubData.fromJson({'bodyMarkdown': 'only body'});
      expect(hub.title, 'Handoff Hub');
      expect(hub.statusTable, isEmpty);
      expect(hub.bodyMarkdown, 'only body');
    });
  });
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd site && flutter test test/hub_model_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:synapse_runbooks/models/hub.dart'`

- [ ] **Step 3: 모델 구현** — `site/lib/models/hub.dart`

```dart
class HubCell {
  final String env;
  final String status;
  final String label;

  const HubCell({required this.env, required this.status, required this.label});

  factory HubCell.fromJson(Map<String, dynamic> json) => HubCell(
        env: json['env'] as String? ?? '',
        status: json['status'] as String? ?? 'na',
        label: json['label'] as String? ?? '',
      );
}

class HubRow {
  final String service;
  final List<HubCell> cells;

  const HubRow({required this.service, required this.cells});

  factory HubRow.fromJson(Map<String, dynamic> json) => HubRow(
        service: json['service'] as String? ?? '',
        cells: ((json['cells'] as List?) ?? const [])
            .map((e) => HubCell.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class HubData {
  final String title;
  final String lastUpdated;
  final List<String> envs;
  final List<HubRow> statusTable;
  final String bodyMarkdown;

  const HubData({
    required this.title,
    required this.lastUpdated,
    required this.envs,
    required this.statusTable,
    required this.bodyMarkdown,
  });

  factory HubData.fromJson(Map<String, dynamic> json) => HubData(
        title: json['title'] as String? ?? 'Handoff Hub',
        lastUpdated: json['lastUpdated'] as String? ?? '',
        envs: List<String>.from((json['envs'] as List?) ?? const []),
        statusTable: ((json['statusTable'] as List?) ?? const [])
            .map((e) => HubRow.fromJson(e as Map<String, dynamic>))
            .toList(),
        bodyMarkdown: json['bodyMarkdown'] as String? ?? '',
      );
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd site && flutter test test/hub_model_test.dart`
Expected: PASS — All tests passed

- [ ] **Step 5: 커밋**

```bash
git add site/lib/models/hub.dart site/test/hub_model_test.dart
git commit -m "feat(portal): HubData 모델 + fromJson 테스트"
```

---

### Task 4: 상태 배지 + 범례 위젯

**Files:**
- Create: `site/lib/widgets/status_badge.dart`
- Create: `site/lib/widgets/status_legend.dart`

- [ ] **Step 1: `status_badge.dart` 작성**

```dart
import 'package:flutter/material.dart';

const Map<String, Color> kStatusColors = {
  'healthy': Color(0xFF16A34A),
  'pending': Color(0xFF2563EB),
  'degraded': Color(0xFFD97706),
  'down': Color(0xFFDC2626),
  'planned': Color(0xFF9CA3AF),
  'na': Color(0xFFD1D5DB),
};

const Map<String, String> kStatusText = {
  'healthy': 'Healthy',
  'pending': '검증 대기',
  'degraded': 'Degraded',
  'down': 'Down',
  'planned': 'Planned',
  'na': '—',
};

class StatusBadge extends StatelessWidget {
  final String status;
  final String label;

  const StatusBadge({super.key, required this.status, required this.label});

  @override
  Widget build(BuildContext context) {
    if (status == 'na') {
      return const Text('—', style: TextStyle(color: Color(0xFF9CA3AF)));
    }
    final color = kStatusColors[status] ?? const Color(0xFF9CA3AF);
    final text = label.isEmpty ? (kStatusText[status] ?? status) : label;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}
```

- [ ] **Step 2: `status_legend.dart` 작성**

```dart
import 'package:flutter/material.dart';
import 'package:synapse_runbooks/widgets/status_badge.dart';

class StatusLegend extends StatelessWidget {
  const StatusLegend({super.key});

  @override
  Widget build(BuildContext context) {
    const order = ['healthy', 'pending', 'degraded', 'down', 'planned'];
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        for (final s in order)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: kStatusColors[s],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 4),
              Text(kStatusText[s] ?? s,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
            ],
          ),
      ],
    );
  }
}
```

- [ ] **Step 3: 분석 통과 확인**

Run: `cd site && flutter analyze lib/widgets/status_badge.dart lib/widgets/status_legend.dart`
Expected: No issues found

- [ ] **Step 4: 커밋**

```bash
git add site/lib/widgets/status_badge.dart site/lib/widgets/status_legend.dart
git commit -m "feat(portal): 상태 배지 + 범례 위젯 (상태색 매핑)"
```

---

### Task 5: `hub_page.dart` 뷰

**Files:**
- Create: `site/lib/pages/hub_page.dart`

- [ ] **Step 1: HubPage 작성**

```dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:synapse_runbooks/models/hub.dart';
import 'package:synapse_runbooks/widgets/markdown_viewer.dart';
import 'package:synapse_runbooks/widgets/status_badge.dart';
import 'package:synapse_runbooks/widgets/status_legend.dart';

class HubPage extends StatefulWidget {
  const HubPage({super.key});

  @override
  State<HubPage> createState() => _HubPageState();
}

class _HubPageState extends State<HubPage> {
  HubData? _hub;
  bool _loading = true;
  bool _missing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final jsonStr = await rootBundle.loadString('assets/docs/hub.json');
      final data = json.decode(jsonStr) as Map<String, dynamic>;
      setState(() {
        _hub = HubData.fromJson(data);
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _missing = true;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_missing || _hub == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('핸드오프 허브 데이터 없음 (빌드에 synapse-shared 미포함).'),
        ),
      );
    }

    final hub = _hub!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(hub.title, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 4),
          Text('최종 갱신: ${hub.lastUpdated} · 출처 HANDOFF_HUB.md',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: const Color(0xFF6B7280))),
          const SizedBox(height: 16),
          const StatusLegend(),
          const SizedBox(height: 24),
          if (hub.statusTable.isNotEmpty) ...[
            Text('환경별 서비스 상태',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _StatusGrid(hub: hub),
            const SizedBox(height: 32),
          ],
          MarkdownViewer(data: hub.bodyMarkdown),
        ],
      ),
    );
  }
}

class _StatusGrid extends StatelessWidget {
  final HubData hub;
  const _StatusGrid({required this.hub});

  @override
  Widget build(BuildContext context) {
    const headerStyle =
        TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF6B7280));
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 40,
        columns: [
          const DataColumn(label: Text('서비스', style: headerStyle)),
          for (final env in hub.envs)
            DataColumn(label: Text(env, style: headerStyle)),
        ],
        rows: [
          for (final row in hub.statusTable)
            DataRow(cells: [
              DataCell(Text(row.service,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
              for (final cell in row.cells)
                DataCell(StatusBadge(status: cell.status, label: cell.label)),
            ]),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: 분석 통과 확인**

Run: `cd site && flutter analyze lib/pages/hub_page.dart`
Expected: No issues found

- [ ] **Step 3: 커밋**

```bash
git add site/lib/pages/hub_page.dart
git commit -m "feat(portal): HubPage — 상태 그리드 + 마크다운 + graceful 폴백"
```

---

### Task 6: 라우트 + 네비 배선

**Files:**
- Modify: `site/lib/app.dart`
- Modify: `site/lib/widgets/sidebar.dart`

- [ ] **Step 1: `app.dart` import 추가**

`import 'package:synapse_runbooks/pages/dashboard_page.dart';` 다음 줄에 추가:
```dart
import 'package:synapse_runbooks/pages/hub_page.dart';
```

- [ ] **Step 2: `/hub` 라우트 추가**

`app.dart`의 `/dashboard` GoRoute 블록 다음에 추가:
```dart
        GoRoute(
          path: '/hub',
          builder: (context, state) => const HubPage(),
        ),
```

- [ ] **Step 3: AppBar 액션 추가**

`app.dart`의 AppBar `actions:` 리스트에서 dashboard IconButton 다음에 추가:
```dart
          IconButton(
            icon: const Icon(Icons.hub),
            tooltip: '핸드오프 허브',
            onPressed: () => context.go('/hub'),
          ),
```

- [ ] **Step 4: 사이드바 nav 항목 추가**

`sidebar.dart`에서 '현황'(`/dashboard`) ListTile 다음에 추가:
```dart
        ListTile(
          leading: const Icon(Icons.hub),
          title: const Text('핸드오프 허브'),
          onTap: () => context.go('/hub'),
        ),
```
(기존 '현황' ListTile의 leading 아이콘 유무 패턴에 맞춰 `leading` 포함/생략 정합 — 인접 ListTile과 동일 스타일로.)

- [ ] **Step 5: 분석 통과 확인**

Run: `cd site && flutter analyze lib/app.dart lib/widgets/sidebar.dart`
Expected: No issues found

- [ ] **Step 6: 커밋**

```bash
git add site/lib/app.dart site/lib/widgets/sidebar.dart
git commit -m "feat(portal): /hub 라우트 + AppBar/사이드바 네비 배선"
```

---

### Task 7: 전체 빌드 검증 + PR

**Files:** 없음 (검증·PR만)

- [ ] **Step 1: 전체 테스트**

```bash
cd site/scripts && node --test
cd ../ && flutter test
```
Expected: node 6 tests passed · flutter All tests passed

- [ ] **Step 2: 전체 analyze**

Run: `cd site && flutter analyze`
Expected: No issues found (기존 경고 외 신규 0)

- [ ] **Step 3: 빌드 산출물 재확인**

```bash
cd site/scripts && NO_AI=1 node build_docs.mjs
node -e "const h=require('../assets/docs/hub.json'); console.log('rows', h.statusTable.length, 'envs', h.envs.length)"
```
Expected: `rows` > 0, `envs` 4 (또는 허브 헤더 환경 수)

- [ ] **Step 4: push + PR**

```bash
git push -u origin feat/portal-handoff-hub-view
gh pr create --base main --head feat/portal-handoff-hub-view \
  --title "feat(portal): 핸드오프 허브 뷰 — HANDOFF_HUB 상태 대시보드 (/hub)" \
  --body "..."
```

PR 본문 포함: 스펙 링크, parse_hub.mjs(하이브리드 파싱)·hub.json·HubPage 요약, 단일 진실원=허브 마크다운, graceful 폴백, 트리거 갭(기존 한계) 명시, 기존 /dashboard 불변.

- [ ] **Step 5: CI 통과 확인 후 머지**

Run: `gh pr checks --watch`
Expected: validate/parse/deploy-pages 통과

---

## 자기 검토 메모

- 스펙 §4 컴포넌트 → Task 1(parse_hub)·Task 2(build_docs)·Task 3(hub.dart)·Task 4(badge/legend)·Task 5(hub_page)·Task 6(nav) 매핑 완료. §5 테스트 → Task 1·3 + Task 7 통합. §5 빌드 통합 → Task 2·7.
- 타입 일관: `parseHubStatusTable`→`{envs, rows}`, `buildHubModel`→`{title,lastUpdated,envs,statusTable,bodyMarkdown}`, Dart `HubData/HubRow/HubCell` 필드명(service/cells/env/status/label) mjs 출력과 1:1.
- 상태 enum 6종(healthy/pending/degraded/down/planned/na) mjs STATUS_MAP·Dart kStatusColors 일치.
- graceful 폴백: hub.json 부재(HubPage `_missing`) + statusTable 빈 배열(그리드 생략) 양쪽 처리.
- hub.json gitignore 여부 Task 2 Step 5에서 확인 후 코드만 커밋(빌드 산출물 비커밋 원칙).
