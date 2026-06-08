class HubCell {
  final String env;
  final String status;
  final String label;

  const HubCell({required this.env, required this.status, required this.label});

  factory HubCell.fromJson(Map<String, dynamic> json) => HubCell(
        env: json['env'] as String? ?? '',
        status: json['status'] as String? ?? 'na',
        label: json['label'] as String? ?? '',
      );
}

class HubRow {
  final String service;
  final List<HubCell> cells;

  const HubRow({required this.service, required this.cells});

  factory HubRow.fromJson(Map<String, dynamic> json) => HubRow(
        service: json['service'] as String? ?? '',
        cells: ((json['cells'] as List?) ?? const [])
            .map((e) => HubCell.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class HubData {
  final String title;
  final String lastUpdated;
  final List<String> envs;
  final List<HubRow> statusTable;
  final String bodyMarkdown;

  const HubData({
    required this.title,
    required this.lastUpdated,
    required this.envs,
    required this.statusTable,
    required this.bodyMarkdown,
  });

  factory HubData.fromJson(Map<String, dynamic> json) => HubData(
        title: json['title'] as String? ?? 'Handoff Hub',
        lastUpdated: json['lastUpdated'] as String? ?? '',
        envs: List<String>.from((json['envs'] as List?) ?? const []),
        statusTable: ((json['statusTable'] as List?) ?? const [])
            .map((e) => HubRow.fromJson(e as Map<String, dynamic>))
            .toList(),
        bodyMarkdown: json['bodyMarkdown'] as String? ?? '',
      );
}
