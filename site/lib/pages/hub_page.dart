import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:synapse_runbooks/models/hub.dart';
import 'package:synapse_runbooks/widgets/markdown_viewer.dart';
import 'package:synapse_runbooks/widgets/status_badge.dart';
import 'package:synapse_runbooks/widgets/status_legend.dart';

class HubPage extends StatefulWidget {
  const HubPage({super.key});

  @override
  State<HubPage> createState() => _HubPageState();
}

class _HubPageState extends State<HubPage> {
  HubData? _hub;
  bool _loading = true;
  bool _missing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final jsonStr = await rootBundle.loadString('assets/docs/hub.json');
      final data = json.decode(jsonStr) as Map<String, dynamic>;
      setState(() {
        _hub = HubData.fromJson(data);
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _missing = true;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_missing || _hub == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('핸드오프 허브 데이터 없음 (빌드에 synapse-shared 미포함).'),
        ),
      );
    }

    final hub = _hub!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(hub.title, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 4),
          Text('최종 갱신: ${hub.lastUpdated} · 출처 HANDOFF_HUB.md',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: const Color(0xFF6B7280))),
          const SizedBox(height: 16),
          const StatusLegend(),
          const SizedBox(height: 24),
          if (hub.statusTable.isNotEmpty) ...[
            Text('환경별 서비스 상태',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _StatusGrid(hub: hub),
            const SizedBox(height: 32),
          ],
          MarkdownViewer(data: hub.bodyMarkdown),
        ],
      ),
    );
  }
}

class _StatusGrid extends StatelessWidget {
  final HubData hub;
  const _StatusGrid({required this.hub});

  @override
  Widget build(BuildContext context) {
    const headerStyle = TextStyle(
        fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF6B7280));
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 40,
        columns: [
          const DataColumn(label: Text('서비스', style: headerStyle)),
          for (final env in hub.envs)
            DataColumn(label: Text(env, style: headerStyle)),
        ],
        rows: [
          for (final row in hub.statusTable)
            DataRow(cells: [
              DataCell(Text(row.service,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
              for (final cell in row.cells)
                DataCell(StatusBadge(status: cell.status, label: cell.label)),
            ]),
        ],
      ),
    );
  }
}
