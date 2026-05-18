enum RunbookCategory {
  onboarding,
  steps,
  weekly;

  static RunbookCategory fromString(String value) {
    return RunbookCategory.values.firstWhere(
      (e) => e.name == value,
      orElse: () => RunbookCategory.onboarding,
    );
  }

  String get displayName {
    switch (this) {
      case RunbookCategory.onboarding:
        return '온보딩';
      case RunbookCategory.steps:
        return 'Step 가이드';
      case RunbookCategory.weekly:
        return '주간 런북';
    }
  }
}

/// index.json 항목 (body 없음)
class RunbookIndex {
  final String slug;
  final String title;
  final Map<String, String> metadata;
  final RunbookCategory category;
  final int order;

  const RunbookIndex({
    required this.slug,
    required this.title,
    required this.metadata,
    required this.category,
    required this.order,
  });

  factory RunbookIndex.fromJson(Map<String, dynamic> json) {
    return RunbookIndex(
      slug: json['slug'] as String,
      title: json['title'] as String,
      metadata: Map<String, String>.from(json['metadata'] as Map),
      category: RunbookCategory.fromString(json['category'] as String),
      order: json['order'] as int,
    );
  }

  String? get target => metadata['대상'] ?? metadata['목적'];
  String? get duration => metadata['소요 시간'];
}

/// 개별 런북 (body 포함)
class Runbook extends RunbookIndex {
  final String body;

  const Runbook({
    required super.slug,
    required super.title,
    required super.metadata,
    required super.category,
    required super.order,
    required this.body,
  });

  factory Runbook.fromJson(Map<String, dynamic> json) {
    return Runbook(
      slug: json['slug'] as String,
      title: json['title'] as String,
      metadata: Map<String, String>.from(json['metadata'] as Map),
      category: RunbookCategory.fromString(json['category'] as String),
      order: json['order'] as int,
      body: json['body'] as String,
    );
  }

  String? get result => metadata['결과'];
  String? get prerequisites => metadata['사전 조건'] ?? metadata['전제'];
  String? get parentDoc => metadata['상위 문서'];
}
