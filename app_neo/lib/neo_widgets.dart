import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'neo_theme.dart';

bool reduceMotion(BuildContext context) => MediaQuery.of(context).disableAnimations;

/// Bo mềm — giữ tên NeoCutBorder từ bản terminal, giờ là rounded border
/// để mọi màn đang dùng khỏi sửa. [cut] = bán kính.
class NeoCutBorder extends RoundedRectangleBorder {
  NeoCutBorder({double cut = Neo.cut, super.side})
      : super(borderRadius: BorderRadius.circular(cut));
}

/// Panel bo mềm + hairline, tuỳ chọn ánh sáng loãng.
class NeoPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;
  final Color? glowColor;
  final double cut;
  final Color? color;

  const NeoPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderColor,
    this.glowColor,
    this.cut = Neo.cut,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color ?? Neo.surface,
        borderRadius: BorderRadius.circular(cut),
        border: Border.all(color: borderColor ?? Neo.faint),
        boxShadow: glowColor == null ? null : Neo.glow(glowColor!),
      ),
      padding: padding,
      child: child,
    );
  }
}

/// Nút chính: pill đầy màu accent, bóng mềm.
class NeoButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final Color? color; // cho phép nhuộm theo khí quyển truyện
  const NeoButton(
      {super.key, required this.label, this.onPressed, this.busy = false, this.color});

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    final c = color ?? Neo.cyan;
    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: enabled ? c : Neo.surface2,
        borderRadius: BorderRadius.circular(27),
        boxShadow: enabled ? Neo.glow(c, blur: 28, alpha: 0.35) : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(27),
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
                    style: GoogleFontsProxy.button(
                        color: enabled ? Neo.onAccent(c) : Neo.dim)),
          ),
        ),
      ),
    );
  }
}

/// Kiểu chữ nút — tách hàm để đồng bộ.
abstract final class GoogleFontsProxy {
  static TextStyle button({required Color color}) => Neo.display(15, color: color)
      .copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.2);
}

/// Thanh tiến trình: vạch mảnh bo tròn; indeterminate = dải sáng chạy.
class HudProgress extends StatefulWidget {
  final double? value;
  final Color? color;
  const HudProgress({super.key, this.value, this.color});

  @override
  State<HudProgress> createState() => _HudProgressState();
}

class _HudProgressState extends State<HudProgress>
    with SingleTickerProviderStateMixin {
  late final _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1300));

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
    final c = widget.color ?? Neo.cyan;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) => ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: SizedBox(
          height: 5,
          child: LayoutBuilder(builder: (_, cons) {
            final w = cons.maxWidth;
            final v = widget.value;
            return Stack(children: [
              Container(color: c.withValues(alpha: 0.14)),
              if (v != null)
                Container(width: w * v.clamp(0, 1), color: c)
              else
                Positioned(
                  left: (w + 90) * _ctrl.value - 90,
                  child: Container(
                    width: 90, height: 5,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        c.withValues(alpha: 0),
                        c,
                        c.withValues(alpha: 0),
                      ]),
                    ),
                  ),
                ),
            ]);
          }),
        ),
      ),
    );
  }
}

/// Scaffold nền trung tính — khí quyển màu do màn tự thêm (AmbientBackdrop).
class NeoScaffold extends StatelessWidget {
  final Widget body;
  final Widget? bottom;
  const NeoScaffold({super.key, required this.body, this.bottom});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(fit: StackFit.expand, children: [
        body,
        if (bottom != null) Align(alignment: Alignment.bottomCenter, child: bottom!),
      ]),
    );
  }
}

/// Chuyển trang: fade + nổi lên nhẹ (morph mềm, không slide cứng).
class MaterializePage<T> extends CustomTransitionPage<T> {
  MaterializePage({required super.child, super.key})
      : super(
          transitionDuration: const Duration(milliseconds: 340),
          transitionsBuilder: (context, animation, _, child) {
            if (reduceMotion(context)) return child;
            final curve =
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
            return FadeTransition(
              opacity: curve,
              child: ScaleTransition(
                scale: Tween(begin: 0.97, end: 1.0).animate(curve),
                child: SlideTransition(
                  position: Tween(begin: const Offset(0, 0.02), end: Offset.zero)
                      .animate(curve),
                  child: child,
                ),
              ),
            );
          },
        );
}

/// Thanh đầu màn phụ.
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
          icon: Icon(Icons.arrow_back, color: Neo.dim),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        Expanded(
          child: Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Neo.display(18, weight: FontWeight.w600)),
        ),
        ...actions,
      ]),
    );
  }
}

/// Ảnh bìa: bo mềm + bóng đổ sâu (nguồn sáng của cả giao diện).
class NeoCover extends StatelessWidget {
  final String? url;
  final double width;
  final double aspect;
  final String? label;
  const NeoCover({super.key, this.url, this.width = 108, this.aspect = 1.4, this.label});

  @override
  Widget build(BuildContext context) {
    final h = width * aspect;
    final r = BorderRadius.circular(width * 0.11);
    final initial = (label ?? '').trim();
    final fallback = Container(
      width: width,
      height: h,
      alignment: Alignment.center,
      color: Neo.surface2,
      child: initial.isEmpty
          ? Icon(Icons.auto_stories_outlined, color: Neo.dim)
          : Text(initial.characters.first.toUpperCase(),
              style: Neo.display(width * 0.4, color: Neo.cyan.withValues(alpha: 0.7))),
    );
    return Container(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 22, offset: const Offset(0, 10)),
        ],
      ),
      child: ClipRRect(
        borderRadius: r,
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

/// Chip mềm.
class NeoTag extends StatelessWidget {
  final String label;
  final Color? color;
  const NeoTag(this.label, {super.key, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Neo.cyan;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: Neo.mono(11, color: c, weight: FontWeight.w600)),
    );
  }
}

/// Ô bấm được: co nhẹ khi nhấn (spring press) — thay glow terminal.
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
      child: AnimatedScale(
        scale: _held && !reduceMotion(context) ? 0.965 : 1,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Header mục — editorial: chữ display lớn + link xem tất cả.
class NeoSectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onMore;
  const NeoSectionHeader(this.title, {super.key, this.onMore});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 16, 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(child: Text(title, style: Neo.display(22))),
        if (onMore != null)
          InkWell(
            onTap: onMore,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text('Tất cả →', style: Neo.mono(12, color: Neo.cyan)),
            ),
          ),
      ]),
    );
  }
}

/// Một dòng truyện trong danh sách dọc.
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
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          NeoCover(url: n['cover_url'], width: 64, aspect: 1.36, label: title),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: Neo.display(16, weight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(n['author_vi'] ?? n['author_zh'] ?? '',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: Neo.mono(11)),
              const SizedBox(height: 8),
              Row(children: [
                Text('${n['chapter_count_source'] ?? 0} chương',
                    style: Neo.mono(11, color: Neo.cyan)),
                const SizedBox(width: 10),
                if (genres.isNotEmpty)
                  Expanded(
                    child: Text(genres.take(3).join(' · '),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: Neo.mono(11)),
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

class NeoDivider extends StatelessWidget {
  const NeoDivider({super.key});
  @override
  Widget build(BuildContext context) =>
      Container(height: 1, margin: const EdgeInsets.symmetric(horizontal: 20), color: Neo.faint);
}

/// Trạng thái tải toàn màn.
class NeoLoading extends StatelessWidget {
  final String label;
  const NeoLoading({super.key, this.label = 'Đang tải…'});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(width: 160, child: HudProgress()),
        const SizedBox(height: 14),
        Text(label, style: Neo.mono(12)),
      ]),
    );
  }
}

class NeoMessage extends StatelessWidget {
  final String text;
  final bool error;
  const NeoMessage(this.text, {super.key, this.error = false});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(text,
            textAlign: TextAlign.center,
            style: Neo.mono(13, color: error ? Neo.danger : Neo.dim)
                .copyWith(height: 1.6)),
      ),
    );
  }
}

/// Dock nổi: kính mờ (frosted), pill chọn tab trượt mềm, haptic khi chuyển.
class NeoDock extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  final List<({IconData icon, String label})> items;
  const NeoDock({super.key, required this.index, required this.onTap, required this.items});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(24, 0, 24, 14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Neo.surface.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      if (i != index) HapticFeedback.lightImpact();
                      onTap(i);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: i == index
                            ? Neo.text.withValues(alpha: 0.1)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(26),
                      ),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(items[i].icon,
                            size: 22, color: i == index ? Neo.text : Neo.dim),
                        const SizedBox(height: 2),
                        Text(items[i].label,
                            style: Neo.mono(10,
                                color: i == index ? Neo.text : Neo.dim,
                                weight: i == index ? FontWeight.w600 : FontWeight.w500)),
                      ]),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
