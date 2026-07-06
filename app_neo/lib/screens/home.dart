import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data.dart';
import '../neo_theme.dart';
import '../ambient.dart';
import '../neo_widgets.dart';
import 'filter.dart';
import 'section.dart';

String _title(Rec n) => n['title_vi'] ?? n['title_zh'] ?? 'Không tên';
String _author(Rec n) => n['author_vi'] ?? n['author_zh'] ?? '';

/// Tab Khám phá — logic port từ app cũ, khung HUD mới.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sections = ref.watch(homeSectionsProvider);
    return SafeArea(
      child: sections.when(
        loading: () => const NeoLoading(label: 'Đang quét kho truyện…'),
        error: (e, _) => NeoMessage('Không tải được truyện.\n$e', error: true),
        data: (s) => RefreshIndicator(
          color: Neo.cyan,
          backgroundColor: Neo.surface,
          onRefresh: () async => ref.invalidate(homeSectionsProvider),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 110), // chừa chỗ dock
            children: [
              const _Brand(),
              if (s.recommended.isNotEmpty) _HeroCarousel(s.recommended.take(6).toList()),
              if (s.latest.isNotEmpty) _Rail('Mới cập nhật', s.latest, SectionKind.latest),
              if (s.recommended.length > 1)
                _Rail('Đề cử', s.recommended.skip(1).toList(), SectionKind.recommended),
              if (s.featured.isNotEmpty) _Rail('Nổi bật', s.featured, SectionKind.featured),
              if (s.completed.isNotEmpty)
                _Rail('Đã hoàn thành', s.completed, SectionKind.completed),
              if (s.latest.isEmpty)
                const NeoMessage('CHƯA CÓ TRUYỆN NÀO\nTHÊM TRUYỆN TỪ WORKER ĐỂ BẮT ĐẦU'),
            ],
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 8, 0),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('KHÁM PHÁ', style: Neo.mono(10, color: Neo.cyan, spacing: 3)),
            const SizedBox(height: 2),
            Text('Kho truyện', style: Neo.display(28)),
          ]),
        ),
        IconButton(
          tooltip: 'Tìm kiếm',
          icon: Icon(Icons.search, color: Neo.text, size: 22),
          onPressed: () => context.push('/search'),
        ),
        IconButton(
          tooltip: 'Lọc truyện',
          icon: Icon(Icons.tune, color: Neo.text, size: 22),
          onPressed: () async {
            final f = await showFilterSheet(context, const SearchFilter());
            if (f != null && context.mounted) {
              Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => FilterResultsScreen(filter: f)));
            }
          },
        ),
      ]),
    );
  }
}

/// Carousel đề cử — tự trượt, cuộn vô hạn (logic giữ nguyên app cũ), chấm chỉ trang HUD.
class _HeroCarousel extends StatefulWidget {
  final List<Rec> items;
  const _HeroCarousel(this.items);
  @override
  State<_HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<_HeroCarousel> {
  late final PageController _ctrl;
  late final bool _loop = widget.items.length > 1;
  Timer? _timer;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = PageController(
        viewportFraction: 0.9, initialPage: _loop ? widget.items.length * 10000 : 0);
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
    final n = widget.items.length;
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 4),
      child: Column(children: [
        SizedBox(
          height: 184,
          child: PageView.builder(
            controller: _ctrl,
            itemCount: _loop ? null : n,
            onPageChanged: (i) => setState(() => _page = i % n),
            itemBuilder: (_, i) => _HeroCard(widget.items[i % n]),
          ),
        ),
        if (n > 1) ...[
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < n; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _page ? 20 : 7,
                height: 3,
                color: i == _page ? Neo.cyan : Neo.faint,
              ),
          ]),
        ],
      ]),
    );
  }
}

/// Thẻ hero: bìa mờ nền + bìa nét + tag + nút đọc, khung vát glow plasma.
class _HeroCard extends StatelessWidget {
  final Rec n;
  const _HeroCard(this.n);
  @override
  Widget build(BuildContext context) {
    final cover = n['cover_url'] as String?;
    return Consumer(builder: (context, ref, _) {
      // khí quyển theo bìa: viền + ánh sáng + nút nhuộm màu riêng của truyện
      final amb = ref.watch(ambientProvider(cover)).value ?? Ambient.fallback;
      return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: NeoTapGlow(
        onTap: () => context.push('/novel/${n['id']}'),
        child: Container(
          decoration: ShapeDecoration(
            shape: NeoCutBorder(
                side: BorderSide(color: amb.accent.withValues(alpha: 0.35))),
            shadows: Neo.glow(amb.accent, blur: 18, alpha: 0.12),
          ),
          child: ClipPath(
            clipper: ShapeBorderClipper(shape: NeoCutBorder()),
            child: Stack(children: [
              Positioned.fill(
                child: (cover == null || cover.isEmpty)
                    ? Container(color: Neo.surface2)
                    : ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                        child: Image.network(cover, fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(color: Neo.surface2)),
                      ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Neo.bg.withValues(alpha: 0.85),
                        Neo.bg.withValues(alpha: 0.45),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Hero(
                      tag: 'cover-${n['id']}',
                      child: NeoCover(url: cover, width: 100, label: _title(n))),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          NeoTag(n['status'] == 'completed' ? 'Hoàn thành' : 'Đang ra'),
                          const SizedBox(height: 8),
                          Text(_title(n), maxLines: 2, overflow: TextOverflow.ellipsis,
                              style: Neo.display(18, weight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text(_author(n), maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: Neo.mono(10)),
                          const Spacer(),
                          InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () => context.push('/novel/${n['id']}/read/1'),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                color: amb.accent,
                              ),
                              child: Text('Đọc ngay',
                                  style: Neo.mono(12, color: Neo.onAccent(amb.accent),
                                      weight: FontWeight.w700)),
                            ),
                          ),
                        ]),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
    });
  }
}

/// Hàng truyện cuộn ngang.
class _Rail extends StatelessWidget {
  final String title;
  final List<Rec> items;
  final SectionKind kind;
  const _Rail(this.title, this.items, this.kind);
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      NeoSectionHeader(title,
          onMore: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => SectionScreen(kind: kind)))),
      SizedBox(
        height: 250,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(width: 14),
          itemBuilder: (_, i) => _RailCard(items[i]),
        ),
      ),
    ]);
  }
}

class _RailCard extends StatelessWidget {
  final Rec n;
  const _RailCard(this.n);
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 128,
      child: NeoTapGlow(
        onTap: () => context.push('/novel/${n['id']}'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Stack(children: [
            NeoCover(url: n['cover_url'], width: 128, label: _title(n)),
            Positioned(
              left: 5, bottom: 5,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                color: Neo.bg.withValues(alpha: 0.75),
                child: Text('CH ${n['chapter_count_source'] ?? 0}',
                    style: Neo.mono(9, color: Neo.cyan, spacing: 1)),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          SizedBox(
            height: 36,
            child: Text(_title(n), maxLines: 2, overflow: TextOverflow.ellipsis,
                style: Neo.display(13.5, weight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }
}
