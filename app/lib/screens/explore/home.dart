import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../ambient.dart';
import '../../cultivation.dart';
import '../../data.dart';
import '../../endpoint.dart';
import '../../theme.dart' show Rad;
import '../../widgets.dart';
import '../shell.dart';
import 'filter.dart';
import 'section.dart';

/// Xoay danh sách theo ngày để carousel không đứng yên: thứ tự "Đề cử" là tất
/// định (source_rank = lượt đọc toàn thời gian), nên không xoay thì 6 truyện đầu
/// gần như cố định vĩnh viễn.
/// ponytail: xoay client theo ngày; muốn cá nhân hoá thì cộng thêm hash user id.
List<Rec> _rotateDaily(List<Rec> items, int take) {
  if (items.length <= take) return items;
  final day = DateTime.now().difference(DateTime(2026)).inDays;
  final start = (day * take) % items.length;
  return [...items, ...items].sublist(start, start + take);
}

String _title(Rec n) => n['title_vi'] ?? n['title_zh'] ?? 'Không tên';
String _author(Rec n) => n['author_vi'] ?? n['author_zh'] ?? '';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sections = ref.watch(homeSectionsProvider);
    return Scaffold(
      backgroundColor: Colors.transparent, // lộ tầng khí quyển của shell
      // 2.0: KHÔNG SafeArea trên — băng chuyền bìa tràn lên cả thanh trạng thái (điện ảnh)
      body: SafeArea(
        top: false,
        child: sections.when(
          loading: () => const SkeletonHome(),
          error: (e, _) =>
              AppError(e, onRetry: () => ref.invalidate(homeSectionsProvider)),
          data: (s) => _TopScrim(
            child: RefreshIndicator(
              onRefresh: () async => ref.invalidate(homeSectionsProvider),
              child: ListView(
                padding: const EdgeInsets.only(
                  bottom: 110,
                ), // chừa chỗ dock nổi
                children: [
                  if (s.recommended.isEmpty)
                    SafeArea(bottom: false, child: const _Brand())
                  else
                    // thương hiệu nổi TRÊN bìa, không chiếm một hàng riêng
                    Stack(
                      children: [
                        _HeroCarousel(_rotateDaily(s.recommended, 6)),
                        const SafeArea(bottom: false, child: _Brand()),
                      ],
                    ),
                  const _DongPhuStrip(),
                  // Mỗi mục một kiểu bày riêng để trang không lặp một dạng rail:
                  // spotlight → rail dọc → bảng xếp hạng → poster lớn.
                  if (s.latest.isNotEmpty)
                    _Spotlight(
                      'Mới cập nhật',
                      s.latest.take(8).toList(),
                      SectionKind.latest,
                    ),
                  if (s.recommended.length > 1)
                    _Rail(
                      'Đề cử',
                      s.recommended.skip(1).toList(),
                      SectionKind.recommended,
                    ),
                  if (s.featured.isNotEmpty)
                    _Ranking(
                      'Nổi bật',
                      s.featured.take(6).toList(),
                      SectionKind.featured,
                    ),
                  if (s.completed.isNotEmpty)
                    _PosterRail(
                      'Đã hoàn thành',
                      s.completed,
                      SectionKind.completed,
                    ),
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
      ),
    );
  }
}

/// Hero tràn lên thanh trạng thái → cuộn xuống thì giờ/pin đè lên bìa. Dải nền giấy
/// hiện dần ở mép trên khi đã cuộn (khỏi che hero lúc đứng đầu trang).
class _TopScrim extends StatefulWidget {
  final Widget child;
  const _TopScrim({required this.child});
  @override
  State<_TopScrim> createState() => _TopScrimState();
}

class _TopScrimState extends State<_TopScrim> {
  final _on = ValueNotifier(false);

  @override
  void dispose() {
    _on.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).scaffoldBackgroundColor;
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.depth == 0) _on.value = n.metrics.pixels > 120;
        return false;
      },
      child: Stack(
        children: [
          widget.child,
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.paddingOf(context).top,
            child: IgnorePointer(
              child: ValueListenableBuilder(
                valueListenable: _on,
                builder: (_, on, _) => AnimatedOpacity(
                  opacity: on ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: ColoredBox(color: bg.withValues(alpha: 0.94)),
                ),
              ),
            ),
          ),
        ],
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
          // header kiểu NEO: nhãn nhỏ tracking rộng + tiêu đề display — đồng họ
          // với PageHeader (vạch nhấn + tiêu đề mực loang) cho cả 4 tab một giọng
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 16,
                      height: 2,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: cs.primary,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                    Text(
                      'KHÁM PHÁ',
                      style: t.labelSmall?.copyWith(
                        color: cs.primary,
                        letterSpacing: 3,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Gác truyện',
                  maxLines: 1,
                  style: t.displaySmall?.copyWith(color: cs.onSurface),
                ),
              ],
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
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => FilterResultsScreen(filter: f),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}

/// Dải Động Phủ (2.0 — vòng chơi C): cảnh giới + thanh tu vi ngay trang chủ, chạm là
/// sang tab Tu Tiên. Khách / chưa nhập đạo thì mời vào, không giấu.
class _DongPhuStrip extends ConsumerWidget {
  const _DongPhuStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final st = ref.watch(cultStateProvider).value; // khách → null (provider tự lo)
    final realm = (st?['realm'] as num?)?.toInt();
    final tien = st?['ascended_at'] != null;
    final name = st == null || realm == null
        ? 'Chưa nhập đạo'
        : tien
        ? tienTierNames[((st['tien_tier'] as num?)?.toInt() ?? 0).clamp(
            0,
            tienTierMax,
          )]
        : '${realmNames[(realm - 1).clamp(0, 8)]} · tầng ${st['stage']}';
    final req = (st?['req'] as num?)?.toDouble() ?? 0;
    final exp = (st?['exp'] as num?)?.toDouble() ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      child: Material(
        color: cs.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Rad.lg),
          side: BorderSide(color: cs.outlineVariant),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(Rad.lg),
          onTap: () => RootShell.goTab.value = 2,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              children: [
                const Seal(char: '道', size: 34),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ĐỘNG PHỦ',
                        style: t.labelSmall?.copyWith(
                          color: cs.primary,
                          letterSpacing: 2.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: req > 0 ? (exp / req).clamp(0.0, 1.0) : 0,
                          minHeight: 4,
                          color: cs.primary,
                          backgroundColor: cs.surfaceContainerHighest,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  st == null ? 'Nhập đạo' : 'Tu luyện',
                  style: t.labelLarge?.copyWith(color: cs.primary),
                ),
                Icon(Icons.chevron_right_rounded, color: cs.primary),
              ],
            ),
          ),
        ),
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
      viewportFraction: 1.0, // full-bleed: ảnh tràn mép màn, không hé thẻ kế
      initialPage: _loop ? widget.items.length * 10000 : 0,
    );
    if (_loop) {
      _timer = Timer.periodic(const Duration(milliseconds: 4500), (_) {
        if (_ctrl.hasClients) {
          _ctrl.nextPage(
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeInOut,
          );
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
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        children: [
          SizedBox(
            // hero cao, choán tầm mắt — ấn tượng đầu tiên của app; cộng phần tai thỏ
            // vì 2.0 cho băng chuyền tràn lên thanh trạng thái
            height: 400 + MediaQuery.paddingOf(context).top,
            child: PageView.builder(
              controller: _ctrl,
              itemCount: _loop ? null : n, // null = vô hạn 2 chiều
              itemBuilder: (_, i) => _HeroCard(widget.items[i % n], _ctrl, i),
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
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < n; i++)
                      Builder(
                        builder: (_) {
                          // khoảng cách vòng tròn (cuộn vô hạn: cuối nối về đầu)
                          final d = (i - p).abs();
                          final near = (1 - (d > n / 2 ? n - d : d)).clamp(
                            0.0,
                            1.0,
                          );
                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: 6 + 12 * near,
                            height: 6,
                            decoration: BoxDecoration(
                              color: Color.lerp(
                                cs.outlineVariant,
                                cs.primary,
                                near,
                              ),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          );
                        },
                      ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// 1 thẻ hero FULL-BLEED (đại tu 2026-07-16): ảnh bìa SẮC NÉT tràn mép màn,
/// chân ảnh tan vào nền trang bằng gradient (không khung, không viền — ảnh LÀ
/// giao diện), chữ + nút đè trực tiếp lên vùng đã tan. Nút vẫn nhuộm màu bìa.
class _HeroCard extends ConsumerWidget {
  final Rec n;
  final PageController ctrl; // để tính parallax theo vị trí vuốt thật
  final int page;
  const _HeroCard(this.n, this.ctrl, this.page);

  /// Lệch trang hiện tại (0 = đứng giữa, ±1 = lệch nguyên trang).
  double get _delta {
    if (!ctrl.hasClients || !ctrl.position.haveDimensions) return 0;
    return ((ctrl.page ?? page.toDouble()) - page).clamp(-1.0, 1.0);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cover = endpointStorageUrl(n['cover_url'] as String?);
    // khí quyển theo bìa: mỗi truyện một màu riêng (như NEO)
    final amb = ref.watch(ambientProvider(cover)).value ?? Ambient.fallback;
    final accent = amb.accent(dark);
    return TapScale(
      onTap: () => context.push('/novel/${n['id']}'),
      child: RepaintBoundary(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // NỀN = chính ảnh bìa phóng to + blur (không sợ cắt vì chỉ là khí quyển);
            // bìa THẬT hiển thị nguyên vẹn ở lớp trên — hết cảnh cắt đầu cắt đuôi.
            (cover == null || cover.isEmpty)
                ? Container(color: cs.primaryContainer)
                : ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: Image.network(
                      cover,
                      fit: BoxFit.cover,
                      cacheWidth: 300,
                      filterQuality: FilterQuality.low,
                      errorBuilder: (_, _, _) =>
                          Container(color: cs.primaryContainer),
                    ),
                  ),
            // chân ảnh tan dần vào nền trang — hero "mọc ra" từ trang, không đóng khung
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.28, 0.72, 1],
                  colors: [
                    bg.withValues(alpha: 0.12),
                    bg.withValues(alpha: 0.86),
                    bg,
                  ],
                ),
              ),
            ),
            // bìa nét NGUYÊN VẸN đứng giữa như poster, đổ bóng màu bìa.
            // Parallax: bìa trôi NHANH hơn nền khi vuốt + thu nhỏ nhẹ lúc rời tâm
            // → thẻ có chiều sâu, "linh hoạt" thay vì dán cứng.
            Positioned(
              top: MediaQuery.paddingOf(context).top + 78,
              left: 0,
              right: 0,
              child: AnimatedBuilder(
                animation: ctrl,
                builder: (_, child) => Transform.translate(
                  offset: Offset(-_delta * 70, 0),
                  child: Transform.scale(
                    scale: 1 - 0.12 * _delta.abs(),
                    child: child,
                  ),
                ),
                child: Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.45),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Hero(
                      tag: 'cover-${n['id']}',
                      child: Cover(url: cover, width: 132, label: _title(n)),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 10,
              child: AnimatedBuilder(
                animation: ctrl,
                builder: (_, child) => Opacity(
                  opacity: (1 - _delta.abs() * 1.4).clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(-_delta * 26, 0),
                    child: child,
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      _title(n),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: t.titleLarge?.copyWith(height: 1.15),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${_author(n)} · ${n['chapter_count_source'] ?? 0} chương · '
                      '${n['status'] == 'completed' ? 'Hoàn thành' : 'Đang ra'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: () => context.push('/novel/${n['id']}/read/1'),
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: accent.computeLuminance() > 0.45
                            ? const Color(0xFF1D2129)
                            : Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 26,
                          vertical: 8,
                        ),
                        textStyle: t.labelLarge?.copyWith(fontSize: 13),
                      ),
                      child: const Text('Đọc ngay'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Mới cập nhật": dải bìa nhỏ + tên, chạm là mở truyện. 1.x kèm thêm thẻ chi tiết lớn
/// có nút "Đọc ngay" riêng — thành hero thứ hai ngay dưới carousel, hai kiểu nút khác nhau.
class _Spotlight extends StatelessWidget {
  final String title;
  final List<Rec> items;
  final SectionKind kind;
  const _Spotlight(this.title, this.items, this.kind);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    const w = 76.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title,
          onMore: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => SectionScreen(kind: kind))),
        ),
        SizedBox(
          // bìa 76×106 + 2 dòng tên (cao dòng 1.2). Phóng CỠ CHỮ THẬT rồi nhân dòng:
          // Android 14+ phóng phi tuyến (số lớn phóng ít), scale(36) hụt 17px ở 200%.
          height: 106 + 12 +
              2 * 1.2 * MediaQuery.textScalerOf(context).scale(t.labelMedium?.fontSize ?? 13),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, i) => TapScale(
              onTap: () => openNovel(context, items[i], 'sp$kind'),
              child: SizedBox(
                width: w,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Hero(
                      tag: coverTag('sp$kind', items[i]['id']),
                      child: Cover(
                        url: items[i]['cover_url'],
                        width: w,
                        flat: true,
                        label: _title(items[i]),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _title(items[i]),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.labelMedium?.copyWith(height: 1.2),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title,
          onMore: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => SectionScreen(kind: kind))),
        ),
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: TapScale(
              onTap: () => openNovel(context, items[i], 'rk$kind'),
              child: Row(
                children: [
                  SizedBox(
                    width: 34,
                    child: Text(
                      '${i + 1}',
                      style: t.headlineMedium?.copyWith(
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w800,
                        color: i < 3
                            ? cs.primary
                            : cs.onSurfaceVariant.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                  Hero(
                    tag: coverTag('rk$kind', items[i]['id']),
                    child: Cover(
                      url: items[i]['cover_url'],
                      width: 46,
                      label: _title(items[i]),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _title(items[i]),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: t.titleMedium?.copyWith(
                            fontSize: 14.5,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          [
                            if (sourceName(items[i]).isNotEmpty)
                              sourceName(items[i]),
                            ...((items[i]['genres'] as List?) ?? const []).take(
                              3,
                            ),
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title,
          onMore: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => SectionScreen(kind: kind))),
        ),
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
                onTap: () => openNovel(context, n, 'po$kind'),
                // chữ phủ trên bìa khổ cố định: 200% đè nhau → chặn 1.3
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.3,
                  child: Stack(
                  children: [
                    Hero(
                      tag: coverTag('po$kind', n['id']),
                      child: Cover(url: n['cover_url'], width: 130, label: _title(n)),
                    ),
                    if (sourceName(n).isNotEmpty)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: SourceBadge(sourceName(n)),
                      ),
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
                      left: 8,
                      right: 8,
                      bottom: 8,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _title(n),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: t.labelMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${n['chapter_count_source'] ?? 0} chương',
                            style: t.labelSmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
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
        SectionHeader(
          title,
          onMore: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => SectionScreen(kind: kind))),
        ),
        SizedBox(
          height: 262,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (_, i) => _RailCard(items[i], 'rl$kind'),
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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.menu_book_rounded, size: 11, color: Colors.white),
          const SizedBox(width: 3),
          Text(
            '$count',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _RailCard extends StatelessWidget {
  final Rec n;
  final String list; // tag Hero riêng mỗi dải (coverTag)
  const _RailCard(this.n, this.list);
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SizedBox(
      width: 132,
      child: TapScale(
        onTap: () => openNovel(context, n, list),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Badge số chương nằm ở CHÂN ảnh (luôn cùng vị trí, không lệ thuộc độ dài tên).
            Stack(
              children: [
                Hero(
                  tag: coverTag(list, n['id']),
                  child: Cover(url: n['cover_url'], width: 132, label: _title(n)),
                ),
                Positioned(
                  left: 6,
                  bottom: 6,
                  child: _ChapterBadge(n['chapter_count_source'] ?? 0),
                ),
                if (sourceName(n).isNotEmpty)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: SourceBadge(sourceName(n)),
                  ),
              ],
            ),
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
