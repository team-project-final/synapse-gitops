# Runbook GitHub Pages 배포 (Flutter Web) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `docs/runbooks/` 의 19개 Markdown 런북을 Flutter Web 앱으로 빌드하여 GitHub Pages에 자동 배포한다.

**Architecture:** 빌드 타임에 Dart 스크립트가 Markdown을 JSON으로 파싱 → Flutter Web 앱이 assets로 포함하여 렌더링. GitHub Actions가 main 푸시 시 자동 빌드/배포.

**Tech Stack:** Flutter Web, Dart, go_router, flutter_markdown, google_fonts, GitHub Actions, GitHub Pages

**Spec:** `docs/superpowers/specs/2026-05-18-runbook-pages-deploy-design.md`

---

## File Structure

### 신규 생성

| 파일 | 책임 |
|------|------|
| `scripts/parse-runbooks.dart` | Markdown → JSON 변환 스크립트 |
| `site/pubspec.yaml` | Flutter 프로젝트 설정 |
| `site/web/index.html` | Flutter Web 엔트리 HTML |
| `site/lib/main.dart` | 앱 엔트리포인트 |
| `site/lib/app.dart` | MaterialApp + GoRouter 설정 |
| `site/lib/models/runbook.dart` | 런북 데이터 모델 |
| `site/lib/pages/home_page.dart` | 카테고리별 런북 목록 |
| `site/lib/pages/runbook_page.dart` | 개별 런북 뷰어 |
| `site/lib/pages/onboarding_page.dart` | 순서형 워크스루 |
| `site/lib/widgets/sidebar.dart` | 네비게이션 사이드바 |
| `site/lib/widgets/markdown_viewer.dart` | Markdown 렌더링 위젯 |
| `site/lib/widgets/code_block.dart` | 코드블록 + 복사 버튼 |
| `site/test/parse_runbooks_test.dart` | 파싱 스크립트 단위 테스트 |
| `site/test/runbook_model_test.dart` | 모델 단위 테스트 |
| `.github/workflows/deploy-pages.yml` | GitHub Pages 배포 워크플로우 |

### 기존 파일 (수정 없음)

| 파일 | 역할 |
|------|------|
| `docs/runbooks/*.md` (19개) | Markdown 소스 — 그대로 유지 |
| `.github/workflows/validate-manifests.yml` | 기존 CI — 독립 동작 |

---

## Task 1: Flutter 프로젝트 초기화

**Files:**
- Create: `site/pubspec.yaml`
- Create: `site/web/index.html`
- Create: `site/lib/main.dart`
- Create: `site/analysis_options.yaml`

- [ ] **Step 1: Flutter 프로젝트 디렉토리 생성**

`site/` 디렉토리에서 Flutter Web 프로젝트를 생성한다.

```bash
cd C:/workspace/team-project-manager/team-project-final/synapse-gitops
flutter create --project-name synapse_runbooks --platforms web site
```

- [ ] **Step 2: pubspec.yaml 의존성 설정**

`site/pubspec.yaml`을 다음과 같이 수정한다:

```yaml
name: synapse_runbooks
description: Synapse GitOps Runbook Viewer
publish_to: 'none'
version: 1.0.0

environment:
  sdk: '>=3.2.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  flutter_markdown: ^0.7.6
  go_router: ^14.8.1
  google_fonts: ^6.2.1

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0

flutter:
  uses-material-design: true
  assets:
    - assets/runbooks/
```

- [ ] **Step 3: web/index.html 에서 base href 설정**

`site/web/index.html`에서 `<base href>` 를 확인한다. Flutter create가 생성한 기본값 `/`를 유지한다 (빌드 시 `--base-href`로 오버라이드).

- [ ] **Step 4: assets/runbooks 디렉토리 생성**

```bash
mkdir -p site/assets/runbooks
echo '[]' > site/assets/runbooks/index.json
```

빈 `index.json`을 넣어야 Flutter가 assets 디렉토리를 인식한다.

- [ ] **Step 5: 빌드 확인**

```bash
cd site
flutter pub get
flutter analyze
```

Expected: 에러 없이 완료

- [ ] **Step 6: Commit**

```bash
git add site/ 
git commit -m "feat(site): initialize Flutter Web project with dependencies"
```

---

## Task 2: Markdown 파싱 스크립트

**Files:**
- Create: `scripts/parse-runbooks.dart`
- Create: `site/test/parse_runbooks_test.dart`

- [ ] **Step 1: 파싱 스크립트 테스트 작성**

`site/test/parse_runbooks_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// parse-runbooks.dart 의 핵심 로직을 테스트한다.
/// 실제 스크립트는 standalone Dart 스크립트이므로,
/// 파싱 함수를 직접 테스트하기 위해 여기서 로직을 검증한다.

void main() {
  group('Markdown metadata parsing', () {
    test('extracts blockquote metadata from runbook header', () {
      const input = '''# Runbook: AWS 계정 초기 설정 (Step 1 상세)

> **대상**: AWS 콘솔/CLI 사용 경험이 적은 작업자
> **소요 시간**: 약 25분
> **결과**: aws sts get-caller-identity가 synapse-admin IAM 사용자로 응답
> **상위 문서**: w1-argocd-bootstrap-runbook.md

본 문서는 내용입니다.''';

      final titleMatch = RegExp(r'^# Runbook:\s*(.+)$', multiLine: true).firstMatch(input);
      expect(titleMatch, isNotNull);
      expect(titleMatch!.group(1)!.trim(), 'AWS 계정 초기 설정 (Step 1 상세)');

      final metaPattern = RegExp(r'>\s*\*\*(.+?)\*\*\s*:\s*(.+)', multiLine: true);
      final matches = metaPattern.allMatches(input).toList();
      expect(matches.length, 4);
      expect(matches[0].group(1), '대상');
      expect(matches[0].group(2)!.trim(), 'AWS 콘솔/CLI 사용 경험이 적은 작업자');
    });

    test('extracts title from non-Runbook heading', () {
      const input = '''# 새 PC / 환경 온보딩 (작업 이어받기)

> **목적**: 다른 PC에서 작업 이어받기
> **소요 시간**: 약 1~2시간''';

      // "# Runbook: " 패턴이 없으면 "# " 뒤 전체를 제목으로
      var titleMatch = RegExp(r'^# Runbook:\s*(.+)$', multiLine: true).firstMatch(input);
      titleMatch ??= RegExp(r'^# (.+)$', multiLine: true).firstMatch(input);
      expect(titleMatch!.group(1)!.trim(), '새 PC / 환경 온보딩 (작업 이어받기)');
    });
  });

  group('Category classification', () {
    test('step files get steps category with correct order', () {
      final stepPattern = RegExp(r'^step(\d+)-');
      final match = stepPattern.firstMatch('step3-terraform-apply.md');
      expect(match, isNotNull);
      expect(int.parse(match!.group(1)!), 3);
    });

    test('weekly files get weekly category with correct order', () {
      final weeklyPattern = RegExp(r'^w(\d+)-');
      final match = weeklyPattern.firstMatch('w2-dev-deploy-runbook.md');
      expect(match, isNotNull);
      expect(int.parse(match!.group(1)!), 2);
    });

    test('onboarding files are classified correctly', () {
      const onboardingFiles = ['dev-machine-setup.md', 'kind-local-bootstrap.md'];
      expect(onboardingFiles.contains('dev-machine-setup.md'), isTrue);
      expect(onboardingFiles.contains('kind-local-bootstrap.md'), isTrue);
      // step/weekly 패턴에 매치되지 않으면 onboarding
      final stepPattern = RegExp(r'^step(\d+)-');
      final weeklyPattern = RegExp(r'^w(\d+)-');
      expect(stepPattern.hasMatch('dev-machine-setup.md'), isFalse);
      expect(weeklyPattern.hasMatch('dev-machine-setup.md'), isFalse);
    });
  });
}
```

- [ ] **Step 2: 테스트 실행하여 통과 확인**

```bash
cd site
flutter test test/parse_runbooks_test.dart
```

Expected: All tests passed (파싱 로직은 순수 Dart regex이므로 즉시 통과)

- [ ] **Step 3: parse-runbooks.dart 스크립트 작성**

`scripts/parse-runbooks.dart`:

```dart
import 'dart:convert';
import 'dart:io';

/// docs/runbooks/*.md 를 파싱하여 site/assets/runbooks/ 에 JSON으로 출력한다.
///
/// 사용법: dart run scripts/parse-runbooks.dart
///
/// 출력:
///   site/assets/runbooks/index.json — 전체 런북 목록 (body 제외)
///   site/assets/runbooks/{slug}.json — 개별 런북 (body 포함)

void main() {
  final runbooksDir = Directory('docs/runbooks');
  final outputDir = Directory('site/assets/runbooks');

  if (!runbooksDir.existsSync()) {
    stderr.writeln('ERROR: docs/runbooks/ 디렉토리가 없습니다.');
    exit(1);
  }

  outputDir.createSync(recursive: true);

  final mdFiles = runbooksDir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.md'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final runbooks = <Map<String, dynamic>>[];

  for (final file in mdFiles) {
    final content = file.readAsStringSync();
    final fileName = file.uri.pathSegments.last;
    final slug = fileName.replaceAll('.md', '');

    // 제목 추출
    final titleMatch =
        RegExp(r'^# Runbook:\s*(.+)$', multiLine: true).firstMatch(content) ??
        RegExp(r'^# (.+)$', multiLine: true).firstMatch(content);
    final title = titleMatch?.group(1)?.trim() ?? slug;

    // 메타데이터 추출 (> **Key**: Value)
    final metaPattern = RegExp(r'>\s*\*\*(.+?)\*\*\s*:\s*(.+)', multiLine: true);
    final metaMatches = metaPattern.allMatches(content);
    final metadata = <String, String>{};
    for (final match in metaMatches) {
      final key = match.group(1)!.trim();
      final value = match.group(2)!.trim();
      metadata[key] = value;
    }

    // 카테고리 분류
    String category;
    int order;
    final stepMatch = RegExp(r'^step(\d+)-').firstMatch(fileName);
    final weeklyMatch = RegExp(r'^w(\d+)-').firstMatch(fileName);

    if (stepMatch != null) {
      category = 'steps';
      order = int.parse(stepMatch.group(1)!);
    } else if (weeklyMatch != null) {
      category = 'weekly';
      order = int.parse(weeklyMatch.group(1)!);
    } else {
      category = 'onboarding';
      // dev-machine-setup을 먼저, kind-local-bootstrap을 두 번째로
      order = fileName == 'dev-machine-setup.md' ? 0 : 1;
    }

    // 본문 추출 (첫 번째 --- 이후)
    final bodyStart = content.indexOf('\n---');
    final body = bodyStart != -1 ? content.substring(bodyStart + 4).trim() : content;

    final runbook = {
      'slug': slug,
      'title': title,
      'metadata': metadata,
      'category': category,
      'order': order,
      'body': body,
    };

    runbooks.add(runbook);

    // 개별 JSON 파일 출력
    final individualFile = File('${outputDir.path}/$slug.json');
    individualFile.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(runbook),
    );
    stdout.writeln('  ✓ $slug.json');
  }

  // 카테고리 → order 순 정렬
  final categoryOrder = {'onboarding': 0, 'steps': 1, 'weekly': 2};
  runbooks.sort((a, b) {
    final catCmp = (categoryOrder[a['category']] ?? 99)
        .compareTo(categoryOrder[b['category']] ?? 99);
    if (catCmp != 0) return catCmp;
    return (a['order'] as int).compareTo(b['order'] as int);
  });

  // index.json (body 제외)
  final index = runbooks.map((r) {
    return {
      'slug': r['slug'],
      'title': r['title'],
      'metadata': r['metadata'],
      'category': r['category'],
      'order': r['order'],
    };
  }).toList();

  File('${outputDir.path}/index.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(index),
  );

  stdout.writeln('\n✓ ${runbooks.length} runbooks parsed → ${outputDir.path}/');
}
```

- [ ] **Step 4: 스크립트 실행 테스트**

```bash
cd C:/workspace/team-project-manager/team-project-final/synapse-gitops
dart run scripts/parse-runbooks.dart
```

Expected:
```
  ✓ dev-machine-setup.json
  ✓ kind-local-bootstrap.json
  ✓ step1-aws-account-setup.json
  ... (19개)

✓ 19 runbooks parsed → site/assets/runbooks/
```

- [ ] **Step 5: 생성된 JSON 검증**

```bash
cat site/assets/runbooks/index.json | head -20
cat site/assets/runbooks/step1-aws-account-setup.json | head -15
```

Expected: 제목, 메타데이터, 카테고리가 올바르게 추출됨

- [ ] **Step 6: .gitignore에 생성된 JSON 추가**

`site/.gitignore`에 추가 (빌드 산출물이므로 커밋하지 않음):

```
assets/runbooks/*.json
```

- [ ] **Step 7: Commit**

```bash
git add scripts/parse-runbooks.dart site/test/parse_runbooks_test.dart site/.gitignore
git commit -m "feat: add Markdown-to-JSON runbook parser script with tests"
```

---

## Task 3: 런북 데이터 모델

**Files:**
- Create: `site/lib/models/runbook.dart`
- Create: `site/test/runbook_model_test.dart`

- [ ] **Step 1: 모델 테스트 작성**

`site/test/runbook_model_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:synapse_runbooks/models/runbook.dart';

void main() {
  group('Runbook model', () {
    test('fromJson parses correctly', () {
      final json = {
        'slug': 'step1-aws-account-setup',
        'title': 'AWS 계정 초기 설정 (Step 1 상세)',
        'metadata': {
          '대상': 'AWS 콘솔/CLI 사용 경험이 적은 작업자',
          '소요 시간': '약 25분',
          '결과': 'aws sts get-caller-identity가 응답',
        },
        'category': 'steps',
        'order': 1,
        'body': '## 내용\n\n본문입니다.',
      };

      final runbook = Runbook.fromJson(json);

      expect(runbook.slug, 'step1-aws-account-setup');
      expect(runbook.title, 'AWS 계정 초기 설정 (Step 1 상세)');
      expect(runbook.category, RunbookCategory.steps);
      expect(runbook.order, 1);
      expect(runbook.target, 'AWS 콘솔/CLI 사용 경험이 적은 작업자');
      expect(runbook.duration, '약 25분');
      expect(runbook.body, '## 내용\n\n본문입니다.');
    });

    test('fromJson handles missing metadata gracefully', () {
      final json = {
        'slug': 'test',
        'title': 'Test',
        'metadata': <String, dynamic>{},
        'category': 'onboarding',
        'order': 0,
        'body': 'body',
      };

      final runbook = Runbook.fromJson(json);
      expect(runbook.target, isNull);
      expect(runbook.duration, isNull);
    });

    test('RunbookIndex fromJson parses without body', () {
      final json = {
        'slug': 'step1-aws-account-setup',
        'title': 'AWS 계정 초기 설정',
        'metadata': {'대상': '작업자', '소요 시간': '25분'},
        'category': 'steps',
        'order': 1,
      };

      final index = RunbookIndex.fromJson(json);
      expect(index.slug, 'step1-aws-account-setup');
      expect(index.title, 'AWS 계정 초기 설정');
      expect(index.category, RunbookCategory.steps);
    });
  });
}
```

- [ ] **Step 2: 테스트 실행 — 실패 확인**

```bash
cd site
flutter test test/runbook_model_test.dart
```

Expected: FAIL — `package:synapse_runbooks/models/runbook.dart` 없음

- [ ] **Step 3: 모델 구현**

`site/lib/models/runbook.dart`:

```dart
enum RunbookCategory {
  onboarding,
  steps,
  weekly;

  static RunbookCategory fromString(String value) {
    return RunbookCategory.values.firstWhere(
      (e) => e.name == value,
      orElse: () => RunbookCategory.onboarding,
    );
  }

  String get displayName {
    switch (this) {
      case RunbookCategory.onboarding:
        return '온보딩';
      case RunbookCategory.steps:
        return 'Step 가이드';
      case RunbookCategory.weekly:
        return '주간 런북';
    }
  }
}

/// index.json 항목 (body 없음)
class RunbookIndex {
  final String slug;
  final String title;
  final Map<String, String> metadata;
  final RunbookCategory category;
  final int order;

  const RunbookIndex({
    required this.slug,
    required this.title,
    required this.metadata,
    required this.category,
    required this.order,
  });

  factory RunbookIndex.fromJson(Map<String, dynamic> json) {
    return RunbookIndex(
      slug: json['slug'] as String,
      title: json['title'] as String,
      metadata: Map<String, String>.from(json['metadata'] as Map),
      category: RunbookCategory.fromString(json['category'] as String),
      order: json['order'] as int,
    );
  }

  String? get target => metadata['대상'] ?? metadata['목적'];
  String? get duration => metadata['소요 시간'];
}

/// 개별 런북 (body 포함)
class Runbook extends RunbookIndex {
  final String body;

  const Runbook({
    required super.slug,
    required super.title,
    required super.metadata,
    required super.category,
    required super.order,
    required this.body,
  });

  factory Runbook.fromJson(Map<String, dynamic> json) {
    return Runbook(
      slug: json['slug'] as String,
      title: json['title'] as String,
      metadata: Map<String, String>.from(json['metadata'] as Map),
      category: RunbookCategory.fromString(json['category'] as String),
      order: json['order'] as int,
      body: json['body'] as String,
    );
  }

  String? get result => metadata['결과'];
  String? get prerequisites => metadata['사전 조건'] ?? metadata['전제'];
  String? get parentDoc => metadata['상위 문서'];
}
```

- [ ] **Step 4: 테스트 실행 — 통과 확인**

```bash
cd site
flutter test test/runbook_model_test.dart
```

Expected: All tests passed

- [ ] **Step 5: Commit**

```bash
git add site/lib/models/runbook.dart site/test/runbook_model_test.dart
git commit -m "feat(site): add Runbook data model with JSON parsing"
```

---

## Task 4: 앱 셸 (Router + Sidebar 레이아웃)

**Files:**
- Create: `site/lib/app.dart`
- Create: `site/lib/widgets/sidebar.dart`
- Modify: `site/lib/main.dart`

- [ ] **Step 1: main.dart 수정**

`site/lib/main.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:synapse_runbooks/app.dart';

void main() {
  runApp(const SynapseRunbooksApp());
}
```

- [ ] **Step 2: app.dart — GoRouter 설정**

`site/lib/app.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:synapse_runbooks/pages/home_page.dart';
import 'package:synapse_runbooks/pages/runbook_page.dart';
import 'package:synapse_runbooks/pages/onboarding_page.dart';
import 'package:synapse_runbooks/widgets/sidebar.dart';

final _router = GoRouter(
  routes: [
    ShellRoute(
      builder: (context, state, child) {
        return AppShell(child: child);
      },
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const HomePage(),
        ),
        GoRoute(
          path: '/runbook/:slug',
          builder: (context, state) {
            final slug = state.pathParameters['slug']!;
            return RunbookPage(slug: slug);
          },
        ),
        GoRoute(
          path: '/onboarding',
          builder: (context, state) => const OnboardingPage(),
        ),
      ],
    ),
  ],
);

class SynapseRunbooksApp extends StatelessWidget {
  const SynapseRunbooksApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Synapse GitOps Runbooks',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF1A73E8),
        useMaterial3: true,
        textTheme: GoogleFonts.notoSansKrTextTheme(),
      ),
      routerConfig: _router,
    );
  }
}

class AppShell extends StatelessWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 800;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Synapse GitOps Runbooks'),
      ),
      drawer: isWide ? null : const Drawer(child: Sidebar()),
      body: Row(
        children: [
          if (isWide)
            const SizedBox(
              width: 280,
              child: Sidebar(),
            ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
```

- [ ] **Step 3: sidebar.dart — 네비게이션 사이드바**

`site/lib/widgets/sidebar.dart`:

```dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:synapse_runbooks/models/runbook.dart';

class Sidebar extends StatefulWidget {
  const Sidebar({super.key});

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  List<RunbookIndex> _runbooks = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadIndex();
  }

  Future<void> _loadIndex() async {
    final jsonStr = await rootBundle.loadString('assets/runbooks/index.json');
    final list = json.decode(jsonStr) as List;
    setState(() {
      _runbooks = list
          .map((e) => RunbookIndex.fromJson(e as Map<String, dynamic>))
          .toList();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final grouped = <RunbookCategory, List<RunbookIndex>>{};
    for (final r in _runbooks) {
      grouped.putIfAbsent(r.category, () => []).add(r);
    }

    // 카테고리 순서: onboarding → steps → weekly
    final categories = [
      RunbookCategory.onboarding,
      RunbookCategory.steps,
      RunbookCategory.weekly,
    ];

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TextButton.icon(
            onPressed: () => context.go('/onboarding'),
            icon: const Icon(Icons.school),
            label: const Text('온보딩 워크스루'),
          ),
        ),
        const Divider(),
        for (final category in categories)
          if (grouped.containsKey(category)) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                category.displayName,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            for (final runbook in grouped[category]!)
              ListTile(
                dense: true,
                title: Text(
                  runbook.title,
                  style: Theme.of(context).textTheme.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: runbook.duration != null
                    ? Text(runbook.duration!,
                        style: Theme.of(context).textTheme.bodySmall)
                    : null,
                onTap: () {
                  context.go('/runbook/${runbook.slug}');
                  // 모바일: drawer 닫기
                  if (Scaffold.of(context).isDrawerOpen) {
                    Navigator.of(context).pop();
                  }
                },
              ),
          ],
      ],
    );
  }
}
```

- [ ] **Step 4: 임시 페이지 스텁 생성**

빌드가 되려면 3개 페이지 파일이 필요하다. 스텁으로 생성:

`site/lib/pages/home_page.dart`:
```dart
import 'package:flutter/material.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('Home — TODO'));
  }
}
```

`site/lib/pages/runbook_page.dart`:
```dart
import 'package:flutter/material.dart';

class RunbookPage extends StatelessWidget {
  final String slug;
  const RunbookPage({super.key, required this.slug});

  @override
  Widget build(BuildContext context) {
    return Center(child: Text('Runbook: $slug — TODO'));
  }
}
```

`site/lib/pages/onboarding_page.dart`:
```dart
import 'package:flutter/material.dart';

class OnboardingPage extends StatelessWidget {
  const OnboardingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('Onboarding — TODO'));
  }
}
```

- [ ] **Step 5: 파싱 스크립트 실행 후 로컬 빌드 확인**

```bash
cd C:/workspace/team-project-manager/team-project-final/synapse-gitops
dart run scripts/parse-runbooks.dart
cd site
flutter run -d chrome
```

Expected: 브라우저에 사이드바 + 빈 콘텐츠 영역이 표시됨. 사이드바에 19개 런북이 카테고리별로 나열됨.

- [ ] **Step 6: Commit**

```bash
git add site/lib/
git commit -m "feat(site): add app shell with GoRouter and sidebar navigation"
```

---

## Task 5: Markdown 렌더링 위젯

**Files:**
- Create: `site/lib/widgets/markdown_viewer.dart`
- Create: `site/lib/widgets/code_block.dart`

- [ ] **Step 1: code_block.dart — 코드블록 + 복사 버튼**

`site/lib/widgets/code_block.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CodeBlockWidget extends StatelessWidget {
  final String code;
  final String? language;

  const CodeBlockWidget({
    super.key,
    required this.code,
    this.language,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 헤더: 언어 라벨 + 복사 버튼
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: const BoxDecoration(
              color: Color(0xFF2D2D2D),
              borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  language ?? '',
                  style: const TextStyle(
                    color: Color(0xFF888888),
                    fontSize: 12,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 16, color: Color(0xFF888888)),
                  tooltip: '복사',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('복사되었습니다'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          // 코드 본문
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              code,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                color: Color(0xFFD4D4D4),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: markdown_viewer.dart — Markdown 렌더링**

`site/lib/widgets/markdown_viewer.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:synapse_runbooks/widgets/code_block.dart';

class MarkdownViewer extends StatelessWidget {
  final String data;

  const MarkdownViewer({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Markdown(
      data: data,
      selectable: true,
      padding: const EdgeInsets.all(24),
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        h1: Theme.of(context).textTheme.headlineLarge,
        h2: Theme.of(context).textTheme.headlineMedium?.copyWith(
              decoration: TextDecoration.underline,
              decorationColor: Theme.of(context).colorScheme.outlineVariant,
            ),
        h3: Theme.of(context).textTheme.titleLarge,
        blockquotePadding: const EdgeInsets.all(12),
        blockquoteDecoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          border: Border(
            left: BorderSide(
              color: Theme.of(context).colorScheme.primary,
              width: 4,
            ),
          ),
        ),
        tableBorder: TableBorder.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        tableHead: const TextStyle(fontWeight: FontWeight.bold),
        tableCellsPadding: const EdgeInsets.all(8),
      ),
      builders: {
        'code': _CodeBlockBuilder(),
      },
    );
  }
}

class _CodeBlockBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(element, preferredStyle) {
    if (element.textContent.isEmpty) return null;

    // 인라인 코드는 기본 렌더링 사용
    final language = element.attributes['class']?.replaceFirst('language-', '');

    // 여러 줄이면 코드블록으로 처리
    if (element.textContent.contains('\n') || language != null) {
      return CodeBlockWidget(
        code: element.textContent.trimRight(),
        language: language,
      );
    }

    return null; // 인라인 코드는 기본 처리
  }
}
```

- [ ] **Step 3: 로컬 확인**

```bash
cd site
flutter run -d chrome
```

Expected: 앱 빌드 성공 (위젯은 아직 페이지에 연결되지 않았으므로 표시되지 않음)

- [ ] **Step 4: Commit**

```bash
git add site/lib/widgets/
git commit -m "feat(site): add Markdown viewer and code block widgets"
```

---

## Task 6: HomePage — 카테고리별 런북 목록

**Files:**
- Modify: `site/lib/pages/home_page.dart`

- [ ] **Step 1: HomePage 구현**

`site/lib/pages/home_page.dart` 전체를 다음으로 교체:

```dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:synapse_runbooks/models/runbook.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<RunbookIndex> _runbooks = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadIndex();
  }

  Future<void> _loadIndex() async {
    final jsonStr = await rootBundle.loadString('assets/runbooks/index.json');
    final list = json.decode(jsonStr) as List;
    setState(() {
      _runbooks = list
          .map((e) => RunbookIndex.fromJson(e as Map<String, dynamic>))
          .toList();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final grouped = <RunbookCategory, List<RunbookIndex>>{};
    for (final r in _runbooks) {
      grouped.putIfAbsent(r.category, () => []).add(r);
    }

    final categories = [
      RunbookCategory.onboarding,
      RunbookCategory.steps,
      RunbookCategory.weekly,
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Synapse GitOps Runbooks',
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 8),
          Text(
            '인프라 구축부터 운영까지, 단계별 실행 가이드',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 32),
          for (final category in categories)
            if (grouped.containsKey(category)) ...[
              Text(
                category.displayName,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final runbook in grouped[category]!)
                    _RunbookCard(runbook: runbook),
                ],
              ),
              const SizedBox(height: 32),
            ],
        ],
      ),
    );
  }
}

class _RunbookCard extends StatelessWidget {
  final RunbookIndex runbook;

  const _RunbookCard({required this.runbook});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 300,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.go('/runbook/${runbook.slug}'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  runbook.title,
                  style: Theme.of(context).textTheme.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                if (runbook.target != null)
                  _MetadataChip(
                    icon: Icons.person_outline,
                    label: runbook.target!,
                  ),
                if (runbook.duration != null) ...[
                  const SizedBox(height: 4),
                  _MetadataChip(
                    icon: Icons.schedule,
                    label: runbook.duration!,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MetadataChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetadataChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: 로컬 확인**

```bash
cd site
flutter run -d chrome
```

Expected: 홈 페이지에 3개 카테고리 섹션, 각각 카드로 런북 목록 표시. 카드에 제목 + 대상 + 소요 시간.

- [ ] **Step 3: Commit**

```bash
git add site/lib/pages/home_page.dart
git commit -m "feat(site): implement HomePage with categorized runbook cards"
```

---

## Task 7: RunbookPage — 개별 런북 뷰어

**Files:**
- Modify: `site/lib/pages/runbook_page.dart`

- [ ] **Step 1: RunbookPage 구현**

`site/lib/pages/runbook_page.dart` 전체를 다음으로 교체:

```dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:synapse_runbooks/models/runbook.dart';
import 'package:synapse_runbooks/widgets/markdown_viewer.dart';

class RunbookPage extends StatefulWidget {
  final String slug;

  const RunbookPage({super.key, required this.slug});

  @override
  State<RunbookPage> createState() => _RunbookPageState();
}

class _RunbookPageState extends State<RunbookPage> {
  Runbook? _runbook;
  List<RunbookIndex>? _allRunbooks;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(RunbookPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slug != widget.slug) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final runbookJson =
          await rootBundle.loadString('assets/runbooks/${widget.slug}.json');
      final indexJson =
          await rootBundle.loadString('assets/runbooks/index.json');

      setState(() {
        _runbook =
            Runbook.fromJson(json.decode(runbookJson) as Map<String, dynamic>);
        _allRunbooks = (json.decode(indexJson) as List)
            .map((e) => RunbookIndex.fromJson(e as Map<String, dynamic>))
            .toList();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '런북을 찾을 수 없습니다: ${widget.slug}';
        _loading = false;
      });
    }
  }

  (RunbookIndex? prev, RunbookIndex? next) _getNeighbors() {
    if (_allRunbooks == null || _runbook == null) return (null, null);

    // 같은 카테고리 내에서 이전/다음
    final sameCategory = _allRunbooks!
        .where((r) => r.category == _runbook!.category)
        .toList();
    final idx = sameCategory.indexWhere((r) => r.slug == _runbook!.slug);

    final prev = idx > 0 ? sameCategory[idx - 1] : null;
    final next =
        idx < sameCategory.length - 1 ? sameCategory[idx + 1] : null;
    return (prev, next);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(child: Text(_error!));
    }

    final runbook = _runbook!;
    final (prev, next) = _getNeighbors();

    return Column(
      children: [
        // 메타데이터 헤더
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(runbook.title,
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (runbook.target != null)
                    Chip(
                      avatar: const Icon(Icons.person_outline, size: 16),
                      label: Text(runbook.target!),
                    ),
                  if (runbook.duration != null)
                    Chip(
                      avatar: const Icon(Icons.schedule, size: 16),
                      label: Text(runbook.duration!),
                    ),
                  if (runbook.prerequisites != null)
                    Chip(
                      avatar: const Icon(Icons.checklist, size: 16),
                      label: Text(runbook.prerequisites!),
                    ),
                ],
              ),
            ],
          ),
        ),
        // Markdown 본문
        Expanded(
          child: MarkdownViewer(data: runbook.body),
        ),
        // 이전/다음 네비게이션
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (prev != null)
                TextButton.icon(
                  onPressed: () => context.go('/runbook/${prev.slug}'),
                  icon: const Icon(Icons.chevron_left),
                  label: Text(prev.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                )
              else
                const SizedBox.shrink(),
              if (next != null)
                TextButton.icon(
                  onPressed: () => context.go('/runbook/${next.slug}'),
                  icon: const Icon(Icons.chevron_right),
                  label: Text(next.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                )
              else
                const SizedBox.shrink(),
            ],
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: 로컬 확인**

```bash
cd site
flutter run -d chrome
```

Expected: 사이드바에서 런북 클릭 → 메타데이터 칩 + Markdown 본문 렌더링 + 코드블록 복사 버튼 + 이전/다음 네비게이션

- [ ] **Step 3: Commit**

```bash
git add site/lib/pages/runbook_page.dart
git commit -m "feat(site): implement RunbookPage with metadata chips and navigation"
```

---

## Task 8: OnboardingPage — 순서형 워크스루

**Files:**
- Modify: `site/lib/pages/onboarding_page.dart`

- [ ] **Step 1: OnboardingPage 구현**

`site/lib/pages/onboarding_page.dart` 전체를 다음으로 교체:

```dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:synapse_runbooks/models/runbook.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  List<RunbookIndex> _steps = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSteps();
  }

  Future<void> _loadSteps() async {
    final jsonStr = await rootBundle.loadString('assets/runbooks/index.json');
    final list = json.decode(jsonStr) as List;
    final all = list
        .map((e) => RunbookIndex.fromJson(e as Map<String, dynamic>))
        .toList();

    // 온보딩 순서: onboarding 카테고리 → steps 카테고리
    final onboarding =
        all.where((r) => r.category == RunbookCategory.onboarding).toList();
    final steps =
        all.where((r) => r.category == RunbookCategory.steps).toList();

    setState(() {
      _steps = [...onboarding, ...steps];
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '온보딩 워크스루',
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 8),
          Text(
            '새 팀원을 위한 환경 구축 가이드. 위에서 아래로 순서대로 진행하세요.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 24),
          Stepper(
            currentStep: 0,
            controlsBuilder: (context, details) => const SizedBox.shrink(),
            steps: [
              for (var i = 0; i < _steps.length; i++)
                Step(
                  title: InkWell(
                    onTap: () => context.go('/runbook/${_steps[i].slug}'),
                    child: Text(_steps[i].title),
                  ),
                  subtitle: _steps[i].duration != null
                      ? Text(_steps[i].duration!)
                      : null,
                  content: Align(
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_steps[i].target != null)
                          Text('대상: ${_steps[i].target!}'),
                        const SizedBox(height: 8),
                        FilledButton.tonalIcon(
                          onPressed: () =>
                              context.go('/runbook/${_steps[i].slug}'),
                          icon: const Icon(Icons.arrow_forward),
                          label: const Text('런북 열기'),
                        ),
                      ],
                    ),
                  ),
                  isActive: true,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: 로컬 확인**

```bash
cd site
flutter run -d chrome
```

Expected: `/onboarding` 경로에서 Stepper UI 표시. dev-machine-setup → kind-local-bootstrap → Step 1~12 순서. 각 단계 클릭 시 해당 런북으로 이동.

- [ ] **Step 3: Commit**

```bash
git add site/lib/pages/onboarding_page.dart
git commit -m "feat(site): implement OnboardingPage with stepper walkthrough"
```

---

## Task 9: GitHub Actions 배포 워크플로우

**Files:**
- Create: `.github/workflows/deploy-pages.yml`

- [ ] **Step 1: 워크플로우 파일 작성**

`.github/workflows/deploy-pages.yml`:

```yaml
name: Deploy Runbook Site to GitHub Pages

on:
  push:
    branches: [main]
    paths:
      - 'docs/runbooks/**'
      - 'site/**'
      - 'scripts/parse-runbooks.dart'
      - '.github/workflows/deploy-pages.yml'

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: 'pages'
  cancel-in-progress: true

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Dart SDK
        uses: dart-lang/setup-dart@v1
        with:
          sdk: stable

      - name: Parse runbooks (Markdown → JSON)
        run: dart run scripts/parse-runbooks.dart

      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          channel: stable

      - name: Install dependencies
        working-directory: site
        run: flutter pub get

      - name: Build Flutter Web
        working-directory: site
        run: flutter build web --release --base-href /synapse-gitops/

      - name: Setup Pages
        uses: actions/configure-pages@v5

      - name: Upload artifact
        uses: actions/upload-pages-artifact@v3
        with:
          path: site/build/web

      - name: Deploy to GitHub Pages
        id: deployment
        uses: actions/deploy-pages@v4
```

- [ ] **Step 2: YAML 문법 검증**

```bash
cd C:/workspace/team-project-manager/team-project-final/synapse-gitops
python -c "import yaml; yaml.safe_load(open('.github/workflows/deploy-pages.yml'))" 2>/dev/null || echo "yamllint check"
```

Expected: 에러 없음

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/deploy-pages.yml
git commit -m "ci: add GitHub Pages deploy workflow for Flutter runbook site"
```

---

## Task 10: 통합 확인 및 최종 정리

**Files:**
- 전체 프로젝트

- [ ] **Step 1: 전체 빌드 파이프라인 로컬 재현**

```bash
cd C:/workspace/team-project-manager/team-project-final/synapse-gitops

# 1. 파싱
dart run scripts/parse-runbooks.dart

# 2. 빌드
cd site
flutter pub get
flutter analyze
flutter build web --release --base-href /synapse-gitops/
```

Expected: `site/build/web/` 에 정적 파일 생성, 에러 없음

- [ ] **Step 2: 빌드 산출물 로컬 서빙 확인**

```bash
cd site/build/web
python -m http.server 8080
```

브라우저에서 `http://localhost:8080/synapse-gitops/` 접속.

Expected:
- 홈: 3개 카테고리 카드 표시
- 사이드바: 19개 런북 나열
- 런북 페이지: Markdown 렌더링 + 코드블록 복사
- 온보딩: Stepper 워크스루

- [ ] **Step 3: .gitignore 확인**

`site/.gitignore`에 빌드 산출물이 포함되어 있는지 확인:

```
build/
assets/runbooks/*.json
```

- [ ] **Step 4: 최종 Commit**

```bash
git add -A
git commit -m "chore(site): finalize build pipeline and cleanup"
```

---

## GitHub Pages 활성화 (수동)

마지막으로 GitHub 레포 Settings에서:

1. **Settings → Pages → Build and deployment → Source**: "GitHub Actions" 선택
2. 워크플로우가 main에 머지되면 자동 배포 시작
3. 배포 완료 후 `https://team-project-final.github.io/synapse-gitops/` 접속 확인
