class Chapter {
  final int chapterIndex;
  final String titleVi;
  final String? titleZh;
  final String? contentVi;
  final String? translationStatus;
  final String? translatedAt;

  const Chapter({
    required this.chapterIndex,
    required this.titleVi,
    this.titleZh,
    this.contentVi,
    this.translationStatus,
    this.translatedAt,
  });

  factory Chapter.fromJson(Map<String, dynamic> json) {
    return Chapter(
      chapterIndex: json['chapter_index'] as int? ?? 0,
      titleVi: json['title_vi'] as String? ?? '',
      titleZh: json['title_zh'] as String?,
      contentVi: json['content_vi'] as String?,
      translationStatus: json['translation_status'] as String?,
      translatedAt: json['translated_at'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'chapter_index': chapterIndex,
    'title_vi': titleVi,
    'title_zh': titleZh,
    'content_vi': contentVi,
    'translation_status': translationStatus,
    'translated_at': translatedAt,
  };
}
