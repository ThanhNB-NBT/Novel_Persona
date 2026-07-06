import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../data.dart';
import '../../widgets.dart';
import 'filter.dart';
import 'section.dart';

String _title(Rec n) => n['title_vi'] ?? n['title_zh'] ?? 'Không tên';
String _author(Rec n) => n['author_vi'] ?? n['author_zh'] ?? '';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sections = ref.watch(homeSectionsProvider);
    return Scaffold(
      body: SafeArea(
        child: sections.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Text(
              'Không tải được truyện.\n$e',
              textAlign: TextAlign.center,
            ),
          ),
          data: (s) => RefreshIndicator(
            onRefresh: () async => ref.invalidate(homeSectionsProvider),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                const _Brand(),
                if (s.recommended.isNotEmpty)
                  _HeroCarousel(s.recommended.take(6).toList()),
                if (s.latest.isNotEmpty)
                  _Rail('Mới cập nhật', s.latest, SectionKind.latest),
                if (s.recommended.length > 1)
                  _Rail('Đề cử', s.recommended.skip(1).toList(), SectionKind.recommended),
                if (s.featured.isNotEmpty)
                  _Rail('Nổi bật', s.featured, SectionKind.featured),
                if (s.completed.isNotEmpty)
                  _Rail('Đã hoàn thành', s.completed, SectionKind.completed),
                if (s.latest.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(
                      child: Text(
                        'Chưa có truyện nào. Thêm truyện từ worker để bắt đầu.',
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Logo GT thư pháp tự đổi màu: mực đậm khi sáng, trắng khi tối.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final logo = isDark ? 'assets/icon/gt_white.png' : 'assets/icon/gt_ink.png';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 8, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Image.asset(logo, height: 40, filterQuality: FilterQuality.medium),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Gác truyện',
              style: GoogleFonts.hurricane(
                fontSize: 40,
                color: cs.onSurface,
              ),
            ),
          ),
          // nút icon trần, nhỏ — không viền tròn
          IconButton(
            tooltip: 'Tìm kiếm',
            iconSize: 22,
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.search_rounded, color: cs.onSurface),
            onPressed: () => context.push('/search'),
          ),
          IconButton(
            tooltip: 'Lọc truyện',
            iconSize: 22,
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.tune_rounded, color: cs.onSurface),
            onPressed: () async {
              final f = await showFilterSheet(context, const SearchFilter());
              if (f != null && context.mounted) {
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => FilterResultsScreen(filter: f)));
              }
            },
          ),
        ],
      ),
    );
  }
}

/// Carousel truyện đề cử ở đầu Khám phá — tự trượt mỗi 4.5s, có chấm chỉ trang.
class _HeroCarousel extends StatefulWidget {
  final List<Rec> items;
  const _HeroCarousel(this.items);
  @override
  State<_HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<_HeroCarousel> {
  // Cuộn vô hạn: xuất phát ở giữa dải ảo lớn (bội số của số truyện để chấm khớp trang
  // đầu), index thật = i % số truyện → trượt tới cuối là truyện đầu hiện ngay bên cạnh.
  late final PageController _ctrl;
  late final bool _loop = widget.items.length > 1;
  Timer? _timer;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = PageController(
        viewportFraction: 0.9,
        initialPage: _loop ? widget.items.length * 10000 : 0);
    if (_loop) {
      _timer = Timer.periodic(const Duration(milliseconds: 4500), (_) {
        if (_ctrl.hasClients) {
          _ctrl.nextPage(
              duration: const Duration(milliseconds: 450), curve: Curves.easeInOut);
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final n = widget.items.length;
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Column(children: [
        SizedBox(
          height: 184,
          child: PageView.builder(
            controller: _ctrl,
            itemCount: _loop ? null : n, // null = vô hạn 2 chiều
            onPageChanged: (i) => setState(() => _page = i % n),
            itemBuilder: (_, i) => _HeroCard(widget.items[i % n]),
          ),
        ),
        if (widget.items.length > 1) ...[
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < widget.items.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _page ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: i == _page ? cs.primary : cs.outlineVariant,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
          ]),
        ],
      ]),
    );
  }
}

/// 1 thẻ hero trong carousel: nền bìa mờ + bìa nét + nút Đọc (giàu hình).
class _HeroCard extends StatelessWidget {
  final Rec n;
  const _HeroCard(this.n);
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cover = n['cover_url'] as String?;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Material(
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/novel/${n['id']}'),
          child: Stack(children: [
            // nền: bìa mờ + phủ tối cho chữ trắng
            Positioned.fill(
              child: (cover == null || cover.isEmpty)
                  ? Container(color: cs.primary.withValues(alpha: 0.4))
                  : ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                      child: Image.network(cover, fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              Container(color: cs.primary.withValues(alpha: 0.4))),
                    ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Colors.black.withValues(alpha: 0.6),
                      Colors.black.withValues(alpha: 0.25),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Hero(tag: 'cover-${n['id']}', child: Cover(url: cover, width: 104, label: _title(n))),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    TagChip(n['status'] == 'completed' ? 'Hoàn thành' : 'Đang ra',
                        color: Colors.white),
                    const SizedBox(height: 8),
                    Text(_title(n), maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: Colors.white, height: 1.2)),
                    const SizedBox(height: 4),
                    Text(_author(n),
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.85))),
                    const SizedBox(height: 14),
                    _ReadPill(onTap: () => context.push('/novel/${n['id']}/read/1')),
                  ]),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Nút "Đọc" gọn trên hero: viền trắng, chữ trắng, nền trong suốt — hợp ảnh nền.
class _ReadPill extends StatelessWidget {
  final VoidCallback onTap;
  const _ReadPill({required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.16),
      shape: StadiumBorder(side: BorderSide(color: Colors.white.withValues(alpha: 0.9))),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 26, vertical: 9),
          child: Text('Đọc',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
        ),
      ),
    );
  }
}

/// Một hàng truyện cuộn ngang. "Xem tất cả" → màn cuộn tải dần theo mục.
class _Rail extends StatelessWidget {
  final String title;
  final List<Rec> items;
  final SectionKind kind;
  const _Rail(this.title, this.items, this.kind);
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title,
            onMore: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => SectionScreen(kind: kind)))),
        SizedBox(
          height: 262,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (_, i) => _RailCard(items[i]),
          ),
        ),
      ],
    );
  }
}

/// Badge số chương đặt ở chân ảnh bìa (nền tối mờ, chữ trắng) — vị trí cố định.
class _ChapterBadge extends StatelessWidget {
  final int count;
  const _ChapterBadge(this.count);
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.menu_book_rounded, size: 11, color: Colors.white),
        const SizedBox(width: 3),
        Text('$count',
            style: const TextStyle(
                color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _RailCard extends StatelessWidget {
  final Rec n;
  const _RailCard(this.n);
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final genres = (n['genres'] as List?)?.whereType<String>().toList() ?? const [];
    return SizedBox(
      width: 132,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/novel/${n['id']}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Không bọc Hero: cùng 1 truyện xuất hiện ở nhiều rail = cùng Map ref =
            // cùng tag → Flutter assert "multiple heroes same tag". Hero chỉ ở _HeroCard.
            // Badge số chương nằm ở CHÂN ảnh (luôn cùng vị trí, không lệ thuộc độ dài tên).
            Stack(children: [
              Cover(url: n['cover_url'], width: 132, label: _title(n)),
              Positioned(
                left: 6, bottom: 6,
                child: _ChapterBadge(n['chapter_count_source'] ?? 0),
              ),
            ]),
            const SizedBox(height: 8),
            // Cao cố định 2 dòng → tiêu đề các thẻ thẳng hàng, hết lộn xộn.
            SizedBox(
              height: 34,
              child: Text(
                _title(n),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: t.titleMedium?.copyWith(fontSize: 14.5, height: 1.15),
              ),
            ),
            if (genres.isNotEmpty) ...[
              const SizedBox(height: 3),
              GenreChips(genres, max: 1),
            ],
          ],
        ),
      ),
    );
  }
}
