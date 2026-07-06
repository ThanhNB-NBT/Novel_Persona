import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data.dart';
import '../neo_theme.dart';
import '../neo_widgets.dart';

/// Khung 4 tab của NEO. Phase 1: tab thật là placeholder HUD, sẽ thay dần
/// ở Phase 2-5 (Explore, Library, Queue, Account).
class NeoShell extends StatefulWidget {
  const NeoShell({super.key});

  @override
  State<NeoShell> createState() => _NeoShellState();
}

class _NeoShellState extends State<NeoShell> {
  int _tab = 1; // mở vào Khám phá, giống app cũ
  bool _booted = false;

  static const _tabs = [
    (icon: Icons.bookmarks_outlined, label: 'Tủ truyện'),
    (icon: Icons.explore_outlined, label: 'Khám phá'),
    (icon: Icons.hourglass_empty_rounded, label: 'Hàng đợi'),
    (icon: Icons.settings_outlined, label: 'Hệ thống'),
  ];

  @override
  Widget build(BuildContext context) {
    if (!_booted) {
      return BootSequence(onDone: () => setState(() => _booted = true));
    }
    return NeoScaffold(
      body: IndexedStack(index: _tab, children: [
        for (final t in _tabs) _Placeholder(label: t.label),
      ]),
      bottom: NeoDock(index: _tab, items: _tabs, onTap: (i) => setState(() => _tab = i)),
    );
  }
}

/// Placeholder HUD cho tab chưa build — hiện trạng thái đăng nhập để chứng minh
/// pipeline Supabase chạy. Thay bằng màn thật ở phase sau.
class _Placeholder extends ConsumerWidget {
  final String label;
  const _Placeholder({required this.label});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(authStateProvider); // rebuild khi đăng nhập/đăng xuất
    final user = sb.auth.currentUser;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('NEO // ${label.toUpperCase()}', style: Neo.mono(11, color: Neo.cyan, spacing: 3)),
          const SizedBox(height: 6),
          Text(label, style: Neo.display(32)),
          const SizedBox(height: 24),
          NeoPanel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('MODULE ĐANG XÂY DỰNG', style: Neo.mono(10, spacing: 3)),
              const SizedBox(height: 10),
              const HudProgress(),
              const SizedBox(height: 18),
              Text(
                user == null ? 'PHIÊN: CHƯA ĐĂNG NHẬP' : 'PHIÊN: ${user.email}',
                style: Neo.mono(12, color: user == null ? Neo.danger : Neo.cyan),
              ),
              const SizedBox(height: 14),
              NeoButton(
                label: user == null ? 'ĐĂNG NHẬP' : 'ĐĂNG XUẤT',
                onPressed: () async {
                  if (user == null) {
                    context.push('/login');
                  } else {
                    await sb.auth.signOut();
                  }
                },
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Boot sequence ~1.2s: scanline quét + logo glitch, bỏ qua nếu tắt animation
/// hoặc chạm màn hình.
class BootSequence extends StatefulWidget {
  final VoidCallback onDone;
  const BootSequence({super.key, required this.onDone});

  @override
  State<BootSequence> createState() => _BootSequenceState();
}

class _BootSequenceState extends State<BootSequence>
    with SingleTickerProviderStateMixin {
  late final _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200));

  @override
  void initState() {
    super.initState();
    _ctrl.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (reduceMotion(context)) {
        widget.onDone();
      } else {
        _ctrl.forward();
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onDone, // đường tắt cho máy yếu / người vội
      child: Scaffold(
        body: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, _) => CustomPaint(
            size: Size.infinite,
            painter: _BootPainter(t: _ctrl.value),
          ),
        ),
      ),
    );
  }
}

class _BootPainter extends CustomPainter {
  final double t;
  _BootPainter({required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    // scanline quét từ trên xuống
    final y = size.height * Curves.easeInOut.transform(t);
    canvas.drawRect(
      Rect.fromLTWH(0, y - 2, size.width, 4),
      Paint()..color = Neo.cyan.withValues(alpha: 0.6 * (1 - t)),
    );
    // vài vệt scanline ngang mờ
    final rnd = math.Random((t * 24).floor()); // đổi seed theo bước -> nhiễu giật
    for (var i = 0; i < 5; i++) {
      canvas.drawRect(
        Rect.fromLTWH(0, rnd.nextDouble() * size.height, size.width, 1),
        Paint()..color = Neo.cyan.withValues(alpha: 0.05),
      );
    }
    // logo glitch: chữ NEO lệch RGB, ổn định dần về cuối
    final jitter = (1 - t) * 6;
    final center = Offset(size.width / 2, size.height / 2);
    void draw(String s, Color c, Offset off, {double size = 44}) {
      final tp = TextPainter(
        text: TextSpan(text: s, style: Neo.display(size, color: c)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2) + off);
    }

    if (t > 0.25) {
      draw('NEO TERMINAL', Neo.plasma.withValues(alpha: 0.7),
          Offset(rnd.nextDouble() * jitter - jitter / 2, 0));
      draw('NEO TERMINAL', Neo.cyan.withValues(alpha: 0.7),
          Offset(-rnd.nextDouble() * jitter + jitter / 2, 1));
      draw('NEO TERMINAL', Neo.text, Offset.zero);
    }
    if (t > 0.5) {
      draw('KHỞI ĐỘNG HỆ THỐNG ${(t * 100).round()}%', Neo.dim,
          const Offset(0, 46), size: 12);
    }
  }

  @override
  bool shouldRepaint(covariant _BootPainter old) => old.t != t;
}
