enum DocCategory {
  infra,
  guides,
  management,
  prd,
  rules,
  fixRequests;

  static DocCategory fromString(String value) {
    switch (value) {
      case 'infra':
        return DocCategory.infra;
      case 'guides':
        return DocCategory.guides;
      case 'management':
        return DocCategory.management;
      case 'prd':
        return DocCategory.prd;
      case 'rules':
        return DocCategory.rules;
      case 'fix-requests':
        return DocCategory.fixRequests;
      default:
        return DocCategory.infra;
    }
  }

  String get id {
    switch (this) {
      case DocCategory.fixRequests:
        return 'fix-requests';
      default:
        return name;
    }
  }

  String get displayName {
    switch (this) {
      case DocCategory.infra:
        return '인프라';
      case DocCategory.guides:
        return '가이드';
      case DocCategory.management:
        return '프로젝트 관리';
      case DocCategory.prd:
        return 'PRD/설계';
      case DocCategory.rules:
        return '규칙';
      case DocCategory.fixRequests:
        return '수정 요청';
    }
  }

  String get icon {
    switch (this) {
      case DocCategory.infra:
        return '\u{1F3D7}';
      case DocCategory.guides:
        return '\u{1F4CB}';
      case DocCategory.management:
        return '\u{1F4CA}';
      case DocCategory.prd:
        return '\u{1F4DD}';
      case DocCategory.rules:
        return '\u{1F4CF}';
      case DocCategory.fixRequests:
        return '\u{1F527}';
    }
  }
}

class TocEntry {
  final int level;
  final String text;
  final String anchor;

  const TocEntry(
      {required this.level, required this.text, required this.anchor});

  factory TocEntry.fromJson(Map<String, dynamic> json) {
    return TocEntry(
      level: json['level'] as int,
      text: json['text'] as String,
      anchor: json['anchor'] as String,
    );
  }
}

class DocMetadata {
  final String? lastUpdated;
  final String status;
  final int? completionRate;

  const DocMetadata(
      {this.lastUpdated, this.status = 'active', this.completionRate});

  factory DocMetadata.fromJson(Map<String, dynamic> json) {
    return DocMetadata(
      lastUpdated: json['lastUpdated'] as String?,
      status: json['status'] as String? ?? 'active',
      completionRate: json['completionRate'] as int?,
    );
  }
}

class DocIndex {
  final String slug;
  final String title;
  final DocCategory category;
  final String source;
  final List<String> tags;
  final String summary;
  final DocMetadata metadata;

  const DocIndex({
    required this.slug,
    required this.title,
    required this.category,
    required this.source,
    required this.tags,
    required this.summary,
    required this.metadata,
  });

  factory DocIndex.fromJson(Map<String, dynamic> json) {
    return DocIndex(
      slug: json['slug'] as String,
      title: json['title'] as String,
      category: DocCategory.fromString(json['category'] as String),
      source: json['source'] as String,
      tags: List<String>.from(json['tags'] as List),
      summary: json['summary'] as String? ?? '',
      metadata:
          DocMetadata.fromJson(json['metadata'] as Map<String, dynamic>),
    );
  }
}

class Doc extends DocIndex {
  final List<TocEntry> toc;
  final String body;

  const Doc({
    required super.slug,
    required super.title,
    required super.category,
    required super.source,
    required super.tags,
    required super.summary,
    required super.metadata,
    required this.toc,
    required this.body,
  });

  factory Doc.fromJson(Map<String, dynamic> json) {
    return Doc(
      slug: json['slug'] as String,
      title: json['title'] as String,
      category: DocCategory.fromString(json['category'] as String),
      source: json['source'] as String,
      tags: List<String>.from(json['tags'] as List),
      summary: json['summary'] as String? ?? '',
      metadata:
          DocMetadata.fromJson(json['metadata'] as Map<String, dynamic>),
      toc: (json['toc'] as List)
          .map((e) => TocEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      body: json['body'] as String,
    );
  }
}
