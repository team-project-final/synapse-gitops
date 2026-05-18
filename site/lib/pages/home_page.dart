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
            '인프라 구축부터 운영까지, 단계별 실행 가이드',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 24),
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
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = screenWidth < 600 ? screenWidth - 48 : 320.0;
    return SizedBox(
      width: cardWidth,
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
