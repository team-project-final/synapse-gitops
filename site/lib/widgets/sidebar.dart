import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:synapse_runbooks/models/doc.dart';
import 'package:synapse_runbooks/models/runbook.dart';

class Sidebar extends StatefulWidget {
  const Sidebar({super.key});

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  List<DocIndex> _docs = [];
  List<RunbookIndex> _runbooks = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final docsJson =
          await rootBundle.loadString('assets/docs/index.json');
      final docsList = json.decode(docsJson) as List;
      _docs = docsList
          .map((e) => DocIndex.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {}

    try {
      final runbooksJson =
          await rootBundle.loadString('assets/runbooks/index.json');
      final runbooksList = json.decode(runbooksJson) as List;
      _runbooks = runbooksList
          .map((e) =>
              RunbookIndex.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {}

    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final grouped = <DocCategory, List<DocIndex>>{};
    for (final d in _docs) {
      grouped.putIfAbsent(d.category, () => []).add(d);
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        ListTile(
          leading: const Icon(Icons.home),
          title: const Text('홈'),
          onTap: () => context.go('/'),
        ),
        ListTile(
          leading: const Icon(Icons.search),
          title: const Text('검색'),
          onTap: () => context.go('/search'),
        ),
        ListTile(
          leading: const Icon(Icons.dashboard),
          title: const Text('현황'),
          onTap: () => context.go('/dashboard'),
        ),
        const Divider(),
        for (final cat in DocCategory.values)
          if (grouped.containsKey(cat))
            ExpansionTile(
              leading:
                  Text(cat.icon, style: const TextStyle(fontSize: 16)),
              title: Text('${cat.displayName} (${grouped[cat]!.length})'),
              children: [
                for (final doc in grouped[cat]!)
                  ListTile(
                    title: Text(doc.title,
                        style: Theme.of(context).textTheme.bodySmall),
                    dense: true,
                    contentPadding: const EdgeInsets.only(left: 56),
                    onTap: () => context.go(
                        '/docs/${doc.category.id}/${doc.slug}'),
                  ),
              ],
            ),
        if (_runbooks.isNotEmpty) ...[
          const Divider(),
          ExpansionTile(
            leading: const Icon(Icons.menu_book, size: 16),
            title: Text('런북 (${_runbooks.length})'),
            children: [
              for (final r in _runbooks)
                ListTile(
                  title: Text(r.title,
                      style: Theme.of(context).textTheme.bodySmall),
                  dense: true,
                  contentPadding: const EdgeInsets.only(left: 56),
                  onTap: () => context.go('/runbook/${r.slug}'),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
