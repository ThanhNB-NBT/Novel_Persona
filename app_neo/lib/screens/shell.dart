
import 'package:flutter/material.dart';

import '../neo_theme.dart';
import '../neo_widgets.dart';
import 'home.dart';
import 'library.dart';
import 'queue.dart';
import 'settings.dart';

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
        const LibraryScreen(),
        const HomeScreen(),
        const QueueScreen(),
        const SettingsScreen(),
      ]),
      bottom: NeoDock(index: _tab, items: _tabs, onTap: (i) => setState(() => _tab = i)),
    );
  }
}

/// Intro ~0.9s: tên app hiện dần trên nền khí quyển rồi tan vào màn chính.
/// Chạm để bỏ qua; tắt animation thì vào thẳng.
class BootSequence extends StatefulWidget {
  final VoidCallback onDone;
  const BootSequence({super.key, required this.onDone});

  @override
  State<BootSequence> createState() => _BootSequenceState();
}

class _BootSequenceState extends State<BootSequence>
    with SingleTickerProviderStateMixin {
  late final _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900));

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
      onTap: widget.onDone,
      child: Scaffold(
        body: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, _) {
            final t = Curves.easeOutCubic.transform(_ctrl.value);
            return DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.3),
                  radius: 1.2,
                  colors: [
                    Neo.plasma.withValues(alpha: 0.1 * (1 - t)),
                    Neo.bg,
                  ],
                ),
              ),
              child: Center(
                child: Opacity(
                  opacity: (t * 1.6).clamp(0, 1) * (1 - (t - 0.75).clamp(0, 0.25) * 4),
                  child: Transform.scale(
                    scale: 0.94 + t * 0.06,
                    child: Text('Truyện', style: Neo.display(52)),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
