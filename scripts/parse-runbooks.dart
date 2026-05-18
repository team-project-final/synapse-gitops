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
