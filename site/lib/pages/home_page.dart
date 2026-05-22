import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:synapse_runbooks/models/doc.dart';
import 'package:synapse_runbooks/widgets/progress_bar.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
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

    final categoryCounts = <DocCategory, int>{};
    for (final d in _docs) {
      categoryCounts[d.category] =
          (categoryCounts[d.category] ?? 0) + 1;
    }

    final withProgress =
        _docs.where((d) => d.metadata.completionRate != null).toList();
    final recent = List<DocIndex>.from(_docs)
      ..sort((a, b) => (b.metadata.lastUpdated ?? '')
          .compareTo(a.metadata.lastUpdated ?? ''));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Synapse Docs',
              style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 8),
          Text(
            '인프라 구축부터 운영까지, 프로젝트 전체 문서를 한 곳에서',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color:
                      Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 24),
          if (withProgress.isNotEmpty) ...[
            Card(
              color: const Color(0xFFF5F5F4),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('프로젝트 현황',
                        style:
                            Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    for (final doc in withProgress.take(5))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: ProgressBar(
                            percentage: doc.metadata.completionRate!,
                            label: doc.title),
                      ),
                    if (withProgress.length > 5)
                      TextButton(
                        onPressed: () => context.go('/dashboard'),
                        child: const Text('전체 보기'),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
          Text('카테고리',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final cat in DocCategory.values)
                if (categoryCounts.containsKey(cat))
                  _CategoryCard(
                    category: cat,
                    count: categoryCounts[cat]!,
                    onTap: () => context.go('/search'),
                  ),
            ],
          ),
          const SizedBox(height: 32),
          Text('최근 업데이트',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          for (final doc in recent.take(10))
            ListTile(
              leading: Text(doc.category.icon,
                  style: const TextStyle(fontSize: 18)),
              title: Text(doc.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: doc.summary.isNotEmpty
                  ? Text(doc.summary,
                      maxLines: 1, overflow: TextOverflow.ellipsis)
                  : null,
              trailing: doc.metadata.lastUpdated != null
                  ? Text(doc.metadata.lastUpdated!,
                      style: Theme.of(context).textTheme.bodySmall)
                  : null,
              onTap: () => context
                  .go('/docs/${doc.category.id}/${doc.slug}'),
            ),
        ],
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final DocCategory category;
  final int count;
  final VoidCallback onTap;

  const _CategoryCard(
      {required this.category, required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 160,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F4),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(category.icon, style: const TextStyle(fontSize: 28)),
            const SizedBox(height: 8),
            Text(category.displayName,
                style: Theme.of(context).textTheme.titleSmall),
            Text('$count개 문서',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
