import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'neo_theme.dart';

// ponytail: Phase 1 vẽ hiệu ứng bằng CustomPainter (đủ 60fps, zero asset);
// nâng lên FragmentShader .frag ở Phase 5 nếu cần grain/glow đắt hơn.

bool reduceMotion(BuildContext context) => MediaQuery.of(context).disableAnimations;

/// Góc vát (cắt 4 góc theo đường chéo) — ngôn ngữ hình khối của NEO.
class NeoCutBorder extends OutlinedBorder {
  final double cut;
  const NeoCutBorder({this.cut = Neo.cut, super.side});

  Path _path(Rect r) {
    final c = math.min(cut, r.shortestSide / 2);
    return Path()
      ..moveTo(r.left + c, r.top)
      ..lineTo(r.right - c, r.top)
      ..lineTo(r.right, r.top + c)
      ..lineTo(r.right, r.bottom - c)
      ..lineTo(r.right - c, r.bottom)
      ..lineTo(r.left + c, r.bottom)
      ..lineTo(r.left, r.bottom - c)
      ..lineTo(r.left, r.top + c)
      ..close();
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _path(rect.deflate(side.width));
  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => _path(rect);
  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none) return;
    canvas.drawPath(_path(rect), side.toPaint());
  }

  @override
  ShapeBorder scale(double t) => NeoCutBorder(cut: cut * t, side: side.scale(t));
  @override
  OutlinedBorder copyWith({BorderSide? side}) =>
      NeoCutBorder(cut: cut, side: side ?? this.side);
}

/// Panel góc vát + hairline border, tuỳ chọn glow.
class NeoPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color borderColor;
  final Color? glowColor;
  final double cut;
  final Color color;

  const NeoPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderColor = Neo.faint,
    this.glowColor,
    this.cut = Neo.cut,
    this.color = Neo.surface,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: ShapeDecoration(
        color: color,
        shape: NeoCutBorder(cut: cut, side: BorderSide(color: borderColor)),
        shadows: glowColor == null ? null : Neo.glow(glowColor!),
      ),
      padding: padding,
      child: child,
    );
  }
}

/// Nút chính: khối vát phát sáng cyan.
class NeoButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  const NeoButton({super.key, required this.label, this.onPressed, this.busy = false});

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    return Container(
      height: 52,
      decoration: ShapeDecoration(
        color: enabled ? Neo.cyan : Neo.surface2,
        shape: const NeoCutBorder(cut: Neo.cutSm),
        shadows: enabled ? Neo.glow(Neo.cyan, blur: 24) : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          customBorder: const NeoCutBorder(cut: Neo.cutSm),
          onTap: enabled
              ? () {
                  HapticFeedback.selectionClick();
                  onPressed!();
                }
              : null,
          child: Center(
            child: busy
                ? const SizedBox(width: 120, child: HudProgress())
                : Text(label,
                    style: Neo.mono(14,
                        color: enabled ? const Color(0xFF001318) : Neo.dim,
                        weight: FontWeight.w700,
                        spacing: 3)),
          ),
        ),
      ),
    );
  }
}

/// Thanh tiến trình HUD dạng segment — thay CircularProgressIndicator.
/// [value] null = indeterminate (segment chạy đuổi).
class HudProgress extends StatefulWidget {
  final double? value;
  const HudProgress({super.key, this.value});

  @override
  State<HudProgress> createState() => _HudProgressState();
}

class _HudProgressState extends State<HudProgress>
    with SingleTickerProviderStateMixin {
  late final _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void initState() {
    super.initState();
    if (widget.value == null) _ctrl.repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const segs = 14;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) {
        final v = widget.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < segs; i++)
              Expanded(
                child: Container(
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 1.2),
                  color: _lit(i, segs, v)
                      ? Neo.cyan
                      : Neo.cyan.withValues(alpha: 0.12),
                ),
              ),
            if (v != null) ...[
              const SizedBox(width: 8),
              Text('${(v * 100).round().toString().padLeft(3)}%',
                  style: Neo.mono(11, color: Neo.cyan)),
            ],
          ],
        );
      },
    );
  }

  bool _lit(int i, int segs, double? v) {
    if (v != null) return i < (v * segs).round();
    final head = (_ctrl.value * segs * 1.6) % (segs + 4);
    return (head - i).abs() < 2.5;
  }
}

/// Nền blueprint: grid mờ + noise nhẹ. Đặt dưới cùng mọi Scaffold qua [NeoScaffold].
class _BlueprintPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = Neo.cyan.withValues(alpha: 0.035)
      ..strokeWidth = 1;
    const step = 36.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    // noise thưa — chấm tĩnh, seed cố định để không nhấp nháy mỗi frame
    final rnd = math.Random(7);
    final dot = Paint()..color = Colors.white.withValues(alpha: 0.03);
    for (var i = 0; i < 260; i++) {
      canvas.drawCircle(
          Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height),
          rnd.nextDouble() * 1.1,
          dot);
    }
  }

  @override
  bool shouldRepaint(covariant _BlueprintPainter old) => false;
}

/// Scaffold chuẩn của NEO: nền đen + blueprint grid, body đè lên trên.
class NeoScaffold extends StatelessWidget {
  final Widget body;
  final Widget? bottom;
  const NeoScaffold({super.key, required this.body, this.bottom});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(fit: StackFit.expand, children: [
        CustomPaint(painter: _BlueprintPainter()),
        body,
        if (bottom != null) Align(alignment: Alignment.bottomCenter, child: bottom!),
      ]),
    );
  }
}

/// Chuyển trang "materialize": fade + scanline quét dọc thay slide mặc định.
class MaterializePage<T> extends CustomTransitionPage<T> {
  MaterializePage({required super.child, super.key})
      : super(
          transitionDuration: const Duration(milliseconds: 320),
          transitionsBuilder: (context, animation, _, child) {
            if (reduceMotion(context)) return child;
            final fade = CurvedAnimation(parent: animation, curve: Curves.easeOut);
            return FadeTransition(
              opacity: fade,
              child: AnimatedBuilder(
                animation: fade,
                builder: (_, w) => Stack(fit: StackFit.expand, children: [
                  w!,
                  if (fade.value < 1)
                    IgnorePointer(
                      child: CustomPaint(
                          painter: _ScanlinePainter(progress: fade.value)),
                    ),
                ]),
                child: child,
              ),
            );
          },
        );
}

class _ScanlinePainter extends CustomPainter {
  final double progress;
  _ScanlinePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height * progress;
    final line = Paint()
      ..shader = LinearGradient(colors: [
        Neo.cyan.withValues(alpha: 0),
        Neo.cyan.withValues(alpha: 0.5),
        Neo.cyan.withValues(alpha: 0),
      ]).createShader(Rect.fromLTWH(0, y - 1.5, size.width, 3));
    canvas.drawRect(Rect.fromLTWH(0, y - 1.5, size.width, 3), line);
    // phần chưa quét tới tối hơn
    canvas.drawRect(Rect.fromLTWH(0, y, size.width, size.height - y),
        Paint()..color = Neo.bg.withValues(alpha: 0.5 * (1 - progress)));
  }

  @override
  bool shouldRepaint(covariant _ScanlinePainter old) => old.progress != progress;
}

/// Thanh đầu màn phụ: nút back + tiêu đề mono + actions. Không dùng AppBar Material.
class NeoAppBar extends StatelessWidget {
  final String title;
  final List<Widget> actions;
  const NeoAppBar({super.key, required this.title, this.actions = const []});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 8, 2),
      child: Row(children: [
        IconButton(
          icon: const Icon(Icons.arrow_back, color: Neo.dim),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        Expanded(
          child: Text(title.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Neo.mono(13, color: Neo.text, weight: FontWeight.w700, spacing: 2)),
        ),
        ...actions,
      ]),
    );
  }
}

/// Ảnh bìa truyện NEO: khung góc vát + hairline, placeholder chữ cái đầu.
class NeoCover extends StatelessWidget {
  final String? url;
  final double width;
  final double aspect;
  final String? label;
  const NeoCover({super.key, this.url, this.width = 108, this.aspect = 1.4, this.label});

  @override
  Widget build(BuildContext context) {
    final h = width * aspect;
    final initial = (label ?? '').trim();
    final fallback = Container(
      width: width,
      height: h,
      alignment: Alignment.center,
      color: Neo.surface2,
      child: initial.isEmpty
          ? const Icon(Icons.auto_stories_outlined, color: Neo.dim)
          : Text(initial.characters.first.toUpperCase(),
              style: Neo.display(width * 0.4, color: Neo.cyan.withValues(alpha: 0.6))),
    );
    return Container(
      decoration: ShapeDecoration(
        shape: NeoCutBorder(
            cut: Neo.cutSm, side: BorderSide(color: Neo.cyan.withValues(alpha: 0.25))),
      ),
      child: ClipPath(
        clipper: ShapeBorderClipper(shape: const NeoCutBorder(cut: Neo.cutSm)),
        child: (url == null || url!.isEmpty)
            ? fallback
            : Image.network(url!,
                width: width,
                height: h,
                fit: BoxFit.cover,
                cacheWidth: (width * MediaQuery.of(context).devicePixelRatio).round(),
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, _, _) => fallback,
                loadingBuilder: (c, child, prog) => prog == null ? child : fallback),
      ),
    );
  }
}

/// Tag mono kiểu terminal: [ĐANG RA]
class NeoTag extends StatelessWidget {
  final String label;
  final Color color;
  const NeoTag(this.label, {super.key, this.color = Neo.cyan});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(label.toUpperCase(),
          style: Neo.mono(9, color: color, weight: FontWeight.w700, spacing: 2)),
    );
  }
}

/// Ô bọc bấm được: viền glow cyan sáng lên khi nhấn giữ (hiệu ứng bắt buộc §3.3).
/// ponytail: parallax theo scroll để Phase 5 polish — glow long-press đã đủ "sống".
class NeoTapGlow extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const NeoTapGlow({super.key, required this.child, required this.onTap});

  @override
  State<NeoTapGlow> createState() => _NeoTapGlowState();
}

class _NeoTapGlowState extends State<NeoTapGlow> {
  bool _held = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      onTapDown: (_) => setState(() => _held = true),
      onTapUp: (_) => setState(() => _held = false),
      onTapCancel: () => setState(() => _held = false),
      onLongPressStart: (_) => setState(() => _held = true),
      onLongPressEnd: (_) => setState(() => _held = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: ShapeDecoration(
          shape: NeoCutBorder(
              cut: Neo.cutSm,
              side: BorderSide(
                  color: _held ? Neo.cyan : Colors.transparent, width: 1)),
          shadows: _held ? Neo.glow(Neo.cyan, blur: 20) : null,
        ),
        child: widget.child,
      ),
    );
  }
}

/// Header mục: "// MỚI CẬP NHẬT" + nút xem tất cả.
class NeoSectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onMore;
  const NeoSectionHeader(this.title, {super.key, this.onMore});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 26, 12, 12),
      child: Row(children: [
        Text('//', style: Neo.mono(14, color: Neo.plasma, weight: FontWeight.w700)),
        const SizedBox(width: 8),
        Expanded(child: Text(title.toUpperCase(), style: Neo.mono(13, color: Neo.text, weight: FontWeight.w700, spacing: 2.5))),
        if (onMore != null)
          InkWell(
            onTap: onMore,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Text('TẤT CẢ >', style: Neo.mono(10, color: Neo.cyan, spacing: 1.5)),
            ),
          ),
      ]),
    );
  }
}

/// Một dòng truyện trong danh sách dọc (tìm kiếm / lọc / xem tất cả).
class NeoNovelRow extends StatelessWidget {
  final Map<String, dynamic> n;
  final VoidCallback onTap;
  final Widget? trailing;
  const NeoNovelRow({super.key, required this.n, required this.onTap, this.trailing});

  @override
  Widget build(BuildContext context) {
    final title = n['title_vi'] ?? n['title_zh'] ?? '';
    final genres = (n['genres'] as List?)?.whereType<String>().toList() ?? const [];
    return NeoTapGlow(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          NeoCover(url: n['cover_url'], width: 64, aspect: 1.36, label: title),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: Neo.display(15, weight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(n['author_vi'] ?? n['author_zh'] ?? '',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: Neo.mono(10)),
              const SizedBox(height: 8),
              Row(children: [
                Text('CH ${n['chapter_count_source'] ?? 0}',
                    style: Neo.mono(10, color: Neo.cyan)),
                const SizedBox(width: 10),
                if (genres.isNotEmpty)
                  Expanded(
                    child: Text(genres.take(3).map((g) => '#$g').join(' '),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: Neo.mono(10)),
                  ),
              ]),
            ]),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ]),
      ),
    );
  }
}

/// Đường kẻ hairline giữa các dòng.
class NeoDivider extends StatelessWidget {
  const NeoDivider({super.key});
  @override
  Widget build(BuildContext context) =>
      Container(height: 1, margin: const EdgeInsets.symmetric(horizontal: 16), color: Neo.faint);
}

/// Trạng thái tải toàn màn: HUD progress + nhãn mono.
class NeoLoading extends StatelessWidget {
  final String label;
  const NeoLoading({super.key, this.label = 'ĐANG TẢI DỮ LIỆU'});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(width: 180, child: HudProgress()),
        const SizedBox(height: 12),
        Text(label, style: Neo.mono(10, spacing: 3)),
      ]),
    );
  }
}

/// Lỗi / rỗng toàn màn.
class NeoMessage extends StatelessWidget {
  final String text;
  final bool error;
  const NeoMessage(this.text, {super.key, this.error = false});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(error ? '! $text' : text,
            textAlign: TextAlign.center,
            style: Neo.mono(12, color: error ? Neo.danger : Neo.dim)),
      ),
    );
  }
}

/// Dock HUD nổi — thay BottomNavigationBar. Icon phát sáng khi active, haptic khi chuyển.
class NeoDock extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  final List<({IconData icon, String label})> items;
  const NeoDock({super.key, required this.index, required this.onTap, required this.items});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: NeoPanel(
        padding: const EdgeInsets.symmetric(vertical: 8),
        color: Neo.surface.withValues(alpha: 0.92),
        borderColor: Neo.cyan.withValues(alpha: 0.35),
        glowColor: Neo.cyan,
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: InkWell(
                  onTap: () {
                    if (i != index) HapticFeedback.lightImpact();
                    onTap(i);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(items[i].icon,
                          size: 22,
                          color: i == index ? Neo.cyan : Neo.dim,
                          shadows: i == index
                              ? [const Shadow(color: Neo.cyan, blurRadius: 14)]
                              : null),
                      const SizedBox(height: 3),
                      Text(items[i].label.toUpperCase(),
                          style: Neo.mono(9,
                              color: i == index ? Neo.cyan : Neo.dim, spacing: 2)),
                    ]),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
