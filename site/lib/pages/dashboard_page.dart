import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:synapse_runbooks/models/doc.dart';
import 'package:synapse_runbooks/widgets/progress_bar.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  List<DocIndex> _docs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final jsonStr = await rootBundle.loadString('assets/docs/index.json');
    final list = json.decode(jsonStr) as List;
    setState(() {
      _docs = list
          .map((e) => DocIndex.fromJson(e as Map<String, dynamic>))
          .toList();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final withProgress =
        _docs.where((d) => d.metadata.completionRate != null).toList();
    final categoryCounts = <DocCategory, int>{};
    for (final d in _docs) {
      categoryCounts[d.category] =
          (categoryCounts[d.category] ?? 0) + 1;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('프로젝트 현황',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 24),
          Text('문서 현황',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final cat in DocCategory.values)
                if (categoryCounts.containsKey(cat))
                  _StatCard(
                    icon: cat.icon,
                    label: cat.displayName,
                    value: '${categoryCounts[cat]}개',
                    onTap: () => context.go('/search'),
                  ),
              _StatCard(
                icon: '\u{1F4DA}',
                label: '전체',
                value: '${_docs.length}개',
                onTap: () => context.go('/search'),
              ),
            ],
          ),
          const SizedBox(height: 32),
          if (withProgress.isNotEmpty) ...[
            Text('진행 상태',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            for (final doc in withProgress) ...[
              InkWell(
                onTap: () => context
                    .go('/docs/${doc.category.id}/${doc.slug}'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: ProgressBar(
                    percentage: doc.metadata.completionRate!,
                    label: doc.title,
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _StatCard(
      {required this.icon,
      required this.label,
      required this.value,
      this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 140,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F4),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(icon, style: const TextStyle(fontSize: 24)),
            const SizedBox(height: 8),
            Text(value,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
