class Novel {
  final int id;
  final String titleVi;
  final String? titleZh;
  final String? authorVi;
  final String? authorZh;
  final String? coverUrl;
  final String status;
  final int chapterCountSource;
  final int chapterCountTranslated;
  final List<String> genres;
  final String? descriptionVi;
  final int? sourceId;
  final String? sourceName;
  final String? lastChapterAt;
  final int? sourceRank;

  const Novel({
    required this.id,
    required this.titleVi,
    this.titleZh,
    this.authorVi,
    this.authorZh,
    this.coverUrl,
    required this.status,
    required this.chapterCountSource,
    required this.chapterCountTranslated,
    required this.genres,
    this.descriptionVi,
    this.sourceId,
    this.sourceName,
    this.lastChapterAt,
    this.sourceRank,
  });

  factory Novel.fromJson(Map<String, dynamic> json) {
    String? sName;
    final sources = json['sources'];
    if (sources is Map<String, dynamic>) {
      sName = sources['name'] as String?;
    } else if (sources is String) {
      sName = sources;
    }

    final rawGenres = json['genres'];
    List<String> parsedGenres = const [];
    if (rawGenres is List) {
      parsedGenres = rawGenres.map((e) => e.toString()).toList();
    }

    return Novel(
      id: json['id'] as int? ?? 0,
      titleVi: json['title_vi'] as String? ?? '',
      titleZh: json['title_zh'] as String?,
      authorVi: json['author_vi'] as String?,
      authorZh: json['author_zh'] as String?,
      coverUrl: json['cover_url'] as String?,
      status: json['status'] as String? ?? 'ongoing',
      chapterCountSource: json['chapter_count_source'] as int? ?? 0,
      chapterCountTranslated: json['chapter_count_translated'] as int? ?? 0,
      genres: parsedGenres,
      descriptionVi: json['description_vi'] as String?,
      sourceId: json['source_id'] as int?,
      sourceName: sName,
      lastChapterAt: json['last_chapter_at'] as String?,
      sourceRank: json['source_rank'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title_vi': titleVi,
    'title_zh': titleZh,
    'author_vi': authorVi,
    'author_zh': authorZh,
    'cover_url': coverUrl,
    'status': status,
    'chapter_count_source': chapterCountSource,
    'chapter_count_translated': chapterCountTranslated,
    'genres': genres,
    'description_vi': descriptionVi,
    'source_id': sourceId,
    'sources': sourceName != null ? {'name': sourceName} : null,
    'last_chapter_at': lastChapterAt,
    'source_rank': sourceRank,
  };
}
