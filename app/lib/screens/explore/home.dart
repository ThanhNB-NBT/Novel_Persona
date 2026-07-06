import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../ambient.dart';
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
          loading: () => const AppLoading(),
          error: (e, _) => Center(
            child: Text(
              'Không tải được truyện.\n$e',
              textAlign: TextAlign.center,
            ),
          ),
          data: (s) => RefreshIndicator(
            onRefresh: () async => ref.invalidate(homeSectionsProvider),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 110), // chừa chỗ dock nổi
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
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 8, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // logo xoá nền, tự nhuộm theo theme (BrandLogo) — hợp cả sáng lẫn tối
          const BrandLogo(height: 44),
          const SizedBox(width: 12),
          // header kiểu NEO: nhãn nhỏ tracking rộng + tiêu đề display
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('KHÁM PHÁ',
                  style: t.labelSmall?.copyWith(color: cs.primary, letterSpacing: 3)),
              const SizedBox(height: 2),
              Text('Gác truyện', style: t.headlineMedium),
            ]),
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
            itemBuilder: (_, i) => _HeroCard(widget.items[i % n]),
          ),
        ),
        if (n > 1) ...[
          const SizedBox(height: 10),
          // Chấm "liquid": bám theo vị trí cuộn thật (page lẻ) — chấm gần trang
          // hiện hành phình ra liên tục như giọt nước, không nhảy bậc.
          AnimatedBuilder(
            animation: _ctrl,
            builder: (_, _) {
              final raw = _ctrl.hasClients && _ctrl.position.haveDimensions
                  ? _ctrl.page ?? _ctrl.initialPage.toDouble()
                  : _ctrl.initialPage.toDouble();
              final p = raw % n; // vị trí thật 0..n (số lẻ khi đang kéo)
              return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var i = 0; i < n; i++)
                  Builder(builder: (_) {
                    // khoảng cách vòng tròn (cuộn vô hạn: cuối nối về đầu)
                    final d = (i - p).abs();
                    final near = (1 - (d > n / 2 ? n - d : d)).clamp(0.0, 1.0);
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: 6 + 12 * near,
                      height: 6,
                      decoration: BoxDecoration(
                        color: Color.lerp(cs.outlineVariant, cs.primary, near),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    );
                  }),
              ]);
            },
          ),
        ],
      ]),
    );
  }
}

/// 1 thẻ hero trong carousel — kiểu NEO "khí quyển": viền/quầng sáng/nút nhuộm
/// màu TRÍCH TỪ BÌA của từng truyện, bìa mờ phủ màu nền (không phủ đen).
class _HeroCard extends ConsumerWidget {
  final Rec n;
  const _HeroCard(this.n);
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cover = n['cover_url'] as String?;
    // khí quyển theo bìa: mỗi truyện một màu riêng (như NEO)
    final amb = ref.watch(ambientProvider(cover)).value ?? Ambient.fallback;
    final accent = amb.accent(dark);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: TapScale(
        onTap: () => context.push('/novel/${n['id']}'),
        // RepaintBoundary: thẻ (blur + bóng) không vẽ lại theo từng frame trượt trang
        child: RepaintBoundary(
            child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: accent.withValues(alpha: 0.4)),
            boxShadow: [
              BoxShadow(color: accent.withValues(alpha: dark ? 0.16 : 0.14), blurRadius: 18),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(children: [
              Positioned.fill(
                child: (cover == null || cover.isEmpty)
                    ? Container(color: cs.primaryContainer)
                    : ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                        // nền sẽ bị mờ hoá — decode nhỏ (400px) + lọc low cho nhẹ GPU,
                        // decode nguyên ảnh làm khựng lúc lướt slide
                        child: Image.network(cover, fit: BoxFit.cover,
                            cacheWidth: 400,
                            filterQuality: FilterQuality.low,
                            errorBuilder: (_, _, _) =>
                                Container(color: cs.primaryContainer)),
                      ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        bg.withValues(alpha: 0.88),
                        bg.withValues(alpha: 0.5),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Hero(tag: 'cover-${n['id']}', child: Cover(url: cover, width: 102, label: _title(n))),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      TagChip(n['status'] == 'completed' ? 'Hoàn thành' : 'Đang ra',
                          color: accent),
                      const SizedBox(height: 8),
                      Text(_title(n), maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: t.titleLarge?.copyWith(height: 1.2)),
                      const SizedBox(height: 4),
                      Text(_author(n), maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: t.labelMedium),
                      const Spacer(),
                      Material(
                        color: accent,
                        borderRadius: BorderRadius.circular(20),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => context.push('/novel/${n['id']}/read/1'),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                            child: Text('Đọc ngay',
                                style: t.labelLarge?.copyWith(
                                    // chữ trên màu bìa: trắng/đen theo độ sáng màu
                                    color: accent.computeLuminance() > 0.45
                                        ? const Color(0xFF1D2129)
                                        : Colors.white,
                                    fontSize: 13)),
                          ),
                        ),
                      ),
                    ]),
                  ),
                ]),
              ),
            ]),
          ),
        )),
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
    return SizedBox(
      width: 132,
      child: TapScale(
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
          ],
        ),
      ),
    );
  }
}
