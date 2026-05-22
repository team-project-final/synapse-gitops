import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:synapse_runbooks/models/doc.dart';
import 'package:synapse_runbooks/models/search_index.dart';
import 'package:synapse_runbooks/widgets/search_bar_widget.dart';
import 'package:synapse_runbooks/widgets/tag_chip.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  final _engine = SearchEngine();
  List<DocIndex> _allDocs = [];
  List<SearchResult> _results = [];
  String? _selectedCategory;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _engine.load();
    final jsonStr = await rootBundle.loadString('assets/docs/index.json');
    final list = json.decode(jsonStr) as List;
    setState(() {
      _allDocs = list
          .map((e) => DocIndex.fromJson(e as Map<String, dynamic>))
          .toList();
      _loading = false;
    });
  }

  void _onSearch(String query) {
    setState(() {
      _results =
          _engine.search(query, categoryFilter: _selectedCategory);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SearchBarWidget(
            controller: _controller,
            onChanged: _onSearch,
            hintText: '키워드로 문서 검색...',
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('전체'),
                selected: _selectedCategory == null,
                onSelected: (_) {
                  setState(() => _selectedCategory = null);
                  _onSearch(_controller.text);
                },
              ),
              for (final cat in DocCategory.values)
                ChoiceChip(
                  label: Text(cat.displayName),
                  selected: _selectedCategory == cat.id,
                  onSelected: (_) {
                    setState(() => _selectedCategory =
                        _selectedCategory == cat.id ? null : cat.id);
                    _onSearch(_controller.text);
                  },
                ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: _controller.text.isEmpty
                ? Center(
                    child: Text(
                      '검색어를 입력하세요 (${_allDocs.length}개 문서)',
                      style: Theme.of(context)
                          .textTheme
                          .bodyLarge
                          ?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),
                  )
                : _results.isEmpty
                    ? const Center(child: Text('검색 결과가 없습니다'))
                    : ListView.builder(
                        itemCount: _results.length,
                        itemBuilder: (context, index) {
                          final r = _results[index];
                          final doc = _allDocs
                              .where((d) => d.slug == r.slug)
                              .firstOrNull;
                          final title = doc?.title ?? r.slug;
                          final cat = DocCategory.fromString(r.category);
                          return ListTile(
                            leading: Text(cat.icon,
                                style: const TextStyle(fontSize: 20)),
                            title: Text(title),
                            subtitle: doc != null &&
                                    doc.summary.isNotEmpty
                                ? Text(doc.summary,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis)
                                : Text(cat.displayName),
                            trailing: doc != null
                                ? Wrap(
                                    spacing: 4,
                                    children: [
                                      for (final t in doc.tags)
                                        TagChip(tag: t)
                                    ],
                                  )
                                : null,
                            onTap: () => context
                                .go('/docs/${r.category}/${r.slug}'),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
