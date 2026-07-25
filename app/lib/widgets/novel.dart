import 'package:flutter/material.dart';

import '../data.dart';
import '../theme.dart' show monoStyle;
import 'common.dart';

/// Ảnh bìa truyện: bo góc 14, đổ bóng mềm (chiều sâu), placeholder gradient.
class Cover extends StatelessWidget {
  final String? url;
  final double width;
  final double aspect; // cao / rộng
  final String? label; // chữ cái đầu cho placeholder khi thiếu bìa
  final bool flat; // true = tắt bóng đổ (thumbnail nhỏ sát nhau bóng nhìn rối)
  const Cover(
      {super.key, this.url, this.width = 108, this.aspect = 1.4, this.label, this.flat = false});

  @override
  Widget build(BuildContext context) {
    final h = width * aspect;
    final radius = BorderRadius.circular(8);
    final cs = Theme.of(context).colorScheme;
    final initial = (label ?? '').trim();
    // placeholder phẳng (tech-minimal): nền nhấn nhạt + chữ cái màu nhấn — không gradient
    Widget fallback = Container(
      width: width,
      height: h,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: radius,
        color: cs.primaryContainer.withValues(alpha: 0.55),
      ),
      child: initial.isEmpty
          ? Icon(Icons.auto_stories_outlined,
              color: cs.primary.withValues(alpha: 0.8), size: width * 0.32)
          : Text(initial.characters.first.toUpperCase(),
              style: TextStyle(
                  color: cs.primary,
                  fontSize: width * 0.42,
                  fontWeight: FontWeight.w800)),
    );
    return Semantics(
      image: true,
      label: initial.isEmpty ? 'Bìa truyện' : 'Bìa truyện $label',
      child: Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        // tech-minimal: viền 1px mờ + bóng rất nhẹ thay bóng nặng
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
        boxShadow: flat
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: (url == null || url!.isEmpty)
            ? fallback
            : Image.network(
                url!,
                width: width,
                height: h,
                fit: BoxFit.cover,
                // decode ở độ phân giải màn hình thật (gấp devicePixelRatio) cho nét,
                // + filterQuality medium để scale mượt thay vì rỗ/mờ.
                cacheWidth:
                    (width * MediaQuery.of(context).devicePixelRatio).round(),
                filterQuality: FilterQuality.medium,
                isAntiAlias: true,
                errorBuilder: (_, _, _) => fallback,
                loadingBuilder: (c, child, prog) => prog == null
                    ? child
                    : SizedBox(width: width, height: h, child: fallback),
              ),
      ),
    ));
  }
}

/// Một dòng truyện liền mạch (bìa + tiêu đề + tác giả + số chương/trạng thái).
/// Dùng cho danh sách tìm kiếm / lọc — không bọc Card để hiện nhiều truyện hơn.
class NovelListRow extends StatelessWidget {
  final Map<String, dynamic> n;
  final VoidCallback onTap;
  final Widget? trailing;
  const NovelListRow({super.key, required this.n, required this.onTap, this.trailing});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final title = n['title_vi'] ?? n['title_zh'] ?? '';
    final genres = (n['genres'] as List?)?.whereType<String>().toList() ?? const [];
    final cs = Theme.of(context).colorScheme;
    const coverW = 76.0; // bìa nhỉnh hơn khối chữ bên phải một chút cho cân mắt
    const coverH = coverW * 1.36; // ảnh to hơn + text căn theo chiều cao ảnh
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Hero cùng tag với trang thông tin → bìa bay mượt khi mở truyện
          Hero(
            tag: 'cover-${n['id']}',
            child: Cover(url: n['cover_url'], width: coverW, aspect: 1.36, label: title),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: SizedBox(
              height: coverH,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // trên: tiêu đề (ngang đỉnh ảnh) + tác giả
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.titleMedium),
                    const SizedBox(height: 3),
                    // tác giả chữ thường, cùng tông nhạt với dòng thể loại
                    Text(n['author_vi'] ?? n['author_zh'] ?? '',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: t.labelMedium?.copyWith(letterSpacing: 0)),
                  ]),
                  if (genres.isNotEmpty) GenreChips(genres, max: 3),
                  // đáy: ngang chân ảnh — số chương + nguồn crawl (nếu có)
                  Row(children: [
                    IconStat(Icons.menu_book_rounded, '${n['chapter_count_source'] ?? 0}'),
                    if (sourceName(n).isNotEmpty) ...[
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(sourceName(n),
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                      ),
                    ],
                  ]),
                ],
              ),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ]),
      ),
    );
  }
}

/// Thể loại kiểu NEO: "Huyền Huyễn · Đô Thị" — chữ nhạt, ngăn bằng chấm giữa.
/// Dùng chung ở danh sách + chi tiết cho nhất quán. [max] null = hiện hết (tự wrap).
class GenreChips extends StatelessWidget {
  final List<String> genres;
  final int? max;
  const GenreChips(this.genres, {super.key, this.max});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final show = max == null ? genres : genres.take(max!).toList();
    return Text(
      show.join(' · '),
      maxLines: max == null ? null : 1,
      overflow: TextOverflow.ellipsis,
      style: t.labelMedium?.copyWith(
          color: cs.onSurfaceVariant, fontWeight: FontWeight.w500, letterSpacing: 0),
    );
  }
}

/// "icon + số" gọn — thay cụm chữ "X chương" cho đỡ rườm.
class IconStat extends StatelessWidget {
  final IconData icon;
  final String value;
  const IconStat(this.icon, this.value, {super.key});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: cs.onSurfaceVariant),
      const SizedBox(width: 4),
      Text(value, style: monoStyle(context)), // số liệu dùng mono — chất "tech"
    ]);
  }
}

/// Badge tên nguồn crawl đè trên bìa (nền tối mờ, chữ trắng) — mirror _ChapterBadge.
class SourceBadge extends StatelessWidget {
  final String name;
  const SourceBadge(this.name, {super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(name,
          style: const TextStyle(
              color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w600)),
    );
  }
}

/// Ô poster dùng chung (lưới Khám phá, màn Xem tất cả…): bìa chiếm trọn ô,
/// gradient chân + tên/số chương đè lên — ngôn ngữ cover-first 2026-07-16.
class PosterTile extends StatelessWidget {
  final Rec n;
  final double width;
  final VoidCallback onTap;
  const PosterTile({super.key, required this.n, required this.width, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final title = n['title_vi'] ?? n['title_zh'] ?? '';
    return TapScale(
      onTap: onTap,
      child: Stack(children: [
        Cover(url: n['cover_url'], width: width, label: title),
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.55, 1],
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.78),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 9, right: 9, bottom: 8,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$title',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: t.labelLarge?.copyWith(
                    color: Colors.white, fontWeight: FontWeight.w700, height: 1.2)),
            const SizedBox(height: 2),
            Text('${n['chapter_count_source'] ?? 0} chương',
                style: t.labelSmall
                    ?.copyWith(color: Colors.white.withValues(alpha: 0.8))),
          ]),
        ),
        if (sourceName(n).isNotEmpty)
          Positioned(top: 8, left: 8, child: SourceBadge(sourceName(n))),
      ]),
    );
  }
}
