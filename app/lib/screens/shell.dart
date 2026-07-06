import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data.dart';
import 'explore/home.dart';
import 'library/library.dart';
import 'library/queue.dart';
import 'account/settings.dart';

/// Khung 4 tab: Tủ truyện · Khám phá · Hàng đợi · Cài đặt.
/// Mặc định mở Tủ truyện (chưa đăng nhập → Khám phá). Giữ trạng thái bằng IndexedStack.
class RootShell extends ConsumerStatefulWidget {
  const RootShell({super.key});
  @override
  ConsumerState<RootShell> createState() => _RootShellState();
}

class _RootShellState extends ConsumerState<RootShell> {
  late int _i;
  static const _pages = [LibraryScreen(), HomeScreen(), QueueScreen(), SettingsScreen()];

  @override
  void initState() {
    super.initState();
    _i = sb.auth.currentUser != null ? 0 : 1; // Tủ truyện nếu đã đăng nhập, ngược lại Khám phá
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // extendBody: nội dung chạy xuống dưới nav → blur "kính mờ" mới có gì để mờ
      extendBody: true,
      body: IndexedStack(index: _i, children: _pages),
      bottomNavigationBar: ClipRect(
          child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: NavigationBar(
        selectedIndex: _i,
        onDestinationSelected: (i) {
          // Tab dùng IndexedStack (giữ sống) nên không tự fetch lại — mở tab thì làm mới
          // dữ liệu để thấy thay đổi vừa gây ở màn khác (vd bấm "dịch thêm" trong reader).
          if (i == 0) ref.invalidate(readingProvider);
          if (i == 2) ref.invalidate(translateQueueProvider);
          setState(() => _i = i);
        },
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.bookmarks_outlined),
              selectedIcon: Icon(Icons.bookmarks_rounded),
              label: 'Tủ truyện'),
          NavigationDestination(
              icon: Icon(Icons.explore_outlined),
              selectedIcon: Icon(Icons.explore_rounded),
              label: 'Khám phá'),
          NavigationDestination(
              icon: Icon(Icons.hourglass_empty_rounded),
              selectedIcon: Icon(Icons.hourglass_bottom_rounded),
              label: 'Hàng đợi'),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings_rounded),
              label: 'Cài đặt'),
        ],
      ))),
    );
  }
}
