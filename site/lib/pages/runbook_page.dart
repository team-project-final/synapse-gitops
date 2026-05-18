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
        Expanded(
          child: MarkdownViewer(data: runbook.body),
        ),
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
