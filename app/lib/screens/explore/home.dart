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
          loading: () => const SkeletonHome(),
          error: (e, _) => AppError(e, onRetry: () => ref.invalidate(homeSectionsProvider)),
          data: (s) => RefreshIndicator(
            onRefresh: () async => ref.invalidate(homeSectionsProvider),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 110), // chừa chỗ dock nổi
              children: [
                const _Brand(),
                if (s.recommended.isNotEmpty)
                  _HeroCarousel(s.recommended.take(6).toList()),
                // Mỗi mục một kiểu bày riêng để trang không lặp một dạng rail:
                // spotlight → rail dọc → bảng xếp hạng → poster lớn.
                if (s.latest.isNotEmpty)
                  _Spotlight('Mới cập nhật', s.latest.take(8).toList(), SectionKind.latest),
                if (s.recommended.length > 1)
                  _Rail('Đề cử', s.recommended.skip(1).toList(), SectionKind.recommended),
                if (s.featured.isNotEmpty)
                  _Ranking('Nổi bật', s.featured.take(6).toList(), SectionKind.featured),
                if (s.completed.isNotEmpty)
                  _PosterRail('Đã hoàn thành', s.completed, SectionKind.completed),
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
          height: 196,
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
                padding: const EdgeInsets.all(11),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // bìa cao kín thẻ (196 - 2×11 padding ≈ 174 = 124×1.4) — đáy
                  // ngang hàng nút Đọc ngay, không còn hụt
                  Hero(tag: 'cover-${n['id']}', child: Cover(url: cover, width: 124, label: _title(n))),
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
                      // FilledButton theo theme (một kiểu nút toàn app), chỉ
                      // nhuộm màu theo bìa; chữ trắng/đen theo độ sáng màu nền
                      FilledButton(
                        onPressed: () => context.push('/novel/${n['id']}/read/1'),
                        style: FilledButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: accent.computeLuminance() > 0.45
                              ? const Color(0xFF1D2129)
                              : Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                          textStyle: t.labelLarge?.copyWith(fontSize: 13),
                        ),
                        child: const Text('Đọc ngay'),
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

/// Spotlight "Mới cập nhật": dải bìa nhỏ ở trên, bấm bìa nào thì thẻ chi tiết
/// bên dưới đổi sang truyện đó (tên + thể loại + nút Đọc + bìa lớn).
class _Spotlight extends StatefulWidget {
  final String title;
  final List<Rec> items;
  final SectionKind kind;
  const _Spotlight(this.title, this.items, this.kind);
  @override
  State<_Spotlight> createState() => _SpotlightState();
}

class _SpotlightState extends State<_Spotlight> {
  int _sel = 0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final sel = _sel.clamp(0, widget.items.length - 1);
    final n = widget.items[sel];
    final genres =
        ((n['genres'] as List?) ?? const []).take(4).join(' + ');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionHeader(widget.title,
          onMore: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => SectionScreen(kind: widget.kind)))),
      // dải bìa nhỏ — to, phẳng (không bóng), sát nhau; bìa đang chọn viền màu nhấn.
      // padding trong 1 + separator 4: viền chọn vẫn có chỗ thở mà dải không hở rãnh to.
      SizedBox(
        height: 102,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: widget.items.length,
          separatorBuilder: (_, _) => const SizedBox(width: 4),
          itemBuilder: (_, i) => GestureDetector(
            onTap: () => setState(() => _sel = i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(1),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: i == sel ? cs.primary : Colors.transparent,
                    width: 2),
              ),
              child: Cover(
                  url: widget.items[i]['cover_url'],
                  width: 68,
                  flat: true,
                  label: _title(widget.items[i])),
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),
      Padding(
        // phải 12 (không phải 20): bìa lớn nằm thẳng mép với dải bìa phía trên —
        // dải trên có viền chọn 2px + bìa cuối thường sát mép nên 20 nhìn bị thụt vào
        padding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
        child: TapScale(
          onTap: () => context.push('/novel/${n['id']}'),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            child: Row(
              key: ValueKey(n['id']),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_title(n),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: t.titleLarge?.copyWith(height: 1.25)),
                        if (genres.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text('【$genres】',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: t.labelMedium?.copyWith(color: cs.primary)),
                        ],
                        const SizedBox(height: 6),
                        Text(
                            '${n['chapter_count_source'] ?? 0} chương • '
                            '${n['status'] == 'completed' ? 'Hoàn thành' : 'Đang ra'}',
                            style: t.labelMedium),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: () =>
                              context.push('/novel/${n['id']}/read/1'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 18, vertical: 8),
                            textStyle: t.labelLarge?.copyWith(fontSize: 13),
                          ),
                          child: const Text('Đọc ngay'),
                        ),
                      ]),
                ),
                const SizedBox(width: 14),
                Cover(url: n['cover_url'], width: 128, label: _title(n)),
              ],
            ),
          ),
        ),
      ),
    ]);
  }
}

/// Bảng xếp hạng "Nổi bật": số thứ tự to, top 3 nhuộm màu nhấn.
class _Ranking extends StatelessWidget {
  final String title;
  final List<Rec> items;
  final SectionKind kind;
  const _Ranking(this.title, this.items, this.kind);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionHeader(title,
          onMore: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => SectionScreen(kind: kind)))),
      for (var i = 0; i < items.length; i++)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: TapScale(
            onTap: () => context.push('/novel/${items[i]['id']}'),
            child: Row(children: [
              SizedBox(
                width: 34,
                child: Text('${i + 1}',
                    style: t.headlineMedium?.copyWith(
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w800,
                        color: i < 3
                            ? cs.primary
                            : cs.onSurfaceVariant.withValues(alpha: 0.45))),
              ),
              Cover(url: items[i]['cover_url'], width: 46, label: _title(items[i])),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_title(items[i]),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: t.titleMedium?.copyWith(fontSize: 14.5, height: 1.2)),
                      const SizedBox(height: 3),
                      Text(
                          ((items[i]['genres'] as List?) ?? const [])
                                  .take(3)
                                  .join(' · ')
                                  .toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.labelSmall
                              ?.copyWith(color: cs.onSurfaceVariant)),
                    ]),
              ),
            ]),
          ),
        ),
    ]);
  }
}

/// Poster lớn "Đã hoàn thành": bìa to, tên đè lên chân bìa với gradient tối.
class _PosterRail extends StatelessWidget {
  final String title;
  final List<Rec> items;
  final SectionKind kind;
  const _PosterRail(this.title, this.items, this.kind);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionHeader(title,
          onMore: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => SectionScreen(kind: kind)))),
      SizedBox(
        height: 186,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(width: 14),
          itemBuilder: (_, i) {
            final n = items[i];
            return TapScale(
              onTap: () => context.push('/novel/${n['id']}'),
              child: Stack(children: [
                Cover(url: n['cover_url'], width: 130, label: _title(n)),
                // gradient + tên ở chân bìa (bo theo góc Cover = 8)
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: const [0.5, 1],
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.75),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 8, right: 8, bottom: 8,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_title(n),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: t.labelMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                height: 1.2)),
                        const SizedBox(height: 2),
                        Text('${n['chapter_count_source'] ?? 0} chương',
                            style: t.labelSmall?.copyWith(
                                color: Colors.white.withValues(alpha: 0.85))),
                      ]),
                ),
              ]),
            );
          },
        ),
      ),
    ]);
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
