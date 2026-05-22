import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:synapse_runbooks/models/doc.dart';
import 'package:synapse_runbooks/widgets/markdown_viewer.dart';
import 'package:synapse_runbooks/widgets/summary_card.dart';
import 'package:synapse_runbooks/widgets/toc_panel.dart';
import 'package:synapse_runbooks/widgets/tag_chip.dart';
import 'package:synapse_runbooks/widgets/progress_bar.dart';

class DocPage extends StatefulWidget {
  final String category;
  final String slug;

  const DocPage({super.key, required this.category, required this.slug});

  @override
  State<DocPage> createState() => _DocPageState();
}

class _DocPageState extends State<DocPage> {
  Doc? _doc;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(DocPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slug != widget.slug ||
        oldWidget.category != widget.category) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final jsonStr = await rootBundle.loadString(
        'assets/docs/${widget.category}/${widget.slug}.json',
      );
      setState(() {
        _doc = Doc.fromJson(json.decode(jsonStr) as Map<String, dynamic>);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error =
            '문서를 찾을 수 없습니다: ${widget.category}/${widget.slug}';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));

    final doc = _doc!;
    final isWide = MediaQuery.of(context).size.width >= 1100;

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          color: const Color(0xFFF5F5F4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(doc.title,
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    avatar: Text(doc.category.icon,
                        style: const TextStyle(fontSize: 14)),
                    label: Text(doc.category.displayName),
                  ),
                  if (doc.metadata.lastUpdated != null)
                    Chip(
                      avatar: const Icon(Icons.calendar_today, size: 14),
                      label: Text(doc.metadata.lastUpdated!),
                    ),
                  for (final tag in doc.tags) TagChip(tag: tag),
                ],
              ),
              if (doc.metadata.completionRate != null) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: 300,
                  child: ProgressBar(
                    percentage: doc.metadata.completionRate!,
                    label: '진행률',
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SummaryCard(summary: doc.summary),
                      MarkdownViewer(data: doc.body),
                    ],
                  ),
                ),
              ),
              if (isWide && doc.toc.isNotEmpty)
                TocPanel(
                  toc: doc.toc,
                  onTap: (anchor) {},
                ),
            ],
          ),
        ),
      ],
    );
  }
}
