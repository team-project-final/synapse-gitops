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
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: runbook.duration != null
                    ? Text(runbook.duration!,
                        style: Theme.of(context).textTheme.bodySmall)
                    : null,
                onTap: () {
                  context.go('/runbook/${runbook.slug}');
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
