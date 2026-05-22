import 'dart:convert';
import 'package:flutter/services.dart';

class SearchResult {
  final String slug;
  final String category;
  final double score;

  const SearchResult({
    required this.slug,
    required this.category,
    required this.score,
  });
}

class SearchEngine {
  Map<String, List<Map<String, String>>> _index = {};
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    try {
      final jsonStr =
          await rootBundle.loadString('assets/docs/search-index.json');
      final decoded = json.decode(jsonStr) as Map<String, dynamic>;
      _index = decoded.map((key, value) => MapEntry(
            key,
            (value as List)
                .map((e) => Map<String, String>.from(e as Map))
                .toList(),
          ));
      _loaded = true;
    } catch (e) {
      _index = {};
      _loaded = true;
    }
  }

  List<SearchResult> search(String query, {String? categoryFilter}) {
    if (!_loaded || query.trim().isEmpty) return [];

    final tokens = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.length >= 2)
        .toList();
    if (tokens.isEmpty) return [];

    final scores = <String, _ScoreEntry>{};

    for (final token in tokens) {
      for (final key in _index.keys) {
        if (!key.contains(token)) continue;
        final isExact = key == token;
        for (final entry in _index[key]!) {
          final slug = entry['s']!;
          final category = entry['c']!;
          if (categoryFilter != null && category != categoryFilter) continue;

          scores.putIfAbsent(
              slug,
              () => _ScoreEntry(
                    slug: slug,
                    category: category,
                    score: 0,
                  ));
          scores[slug]!.score += isExact ? 10 : 3;
        }
      }
    }

    final results = scores.values
        .map((e) => SearchResult(
            slug: e.slug, category: e.category, score: e.score))
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    return results.take(20).toList();
  }
}

class _ScoreEntry {
  final String slug;
  final String category;
  double score;

  _ScoreEntry(
      {required this.slug, required this.category, required this.score});
}
