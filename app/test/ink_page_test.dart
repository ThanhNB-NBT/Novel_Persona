// Trang mở riêng (ngoài shell) có Scaffold nền trong suốt không được lộ nền đen.
//   flutter test test/ink_page_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:novel_reader/ink_transition.dart';
import 'package:novel_reader/theme.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('inkPage tô nền theme dưới màn nền trong suốt', (tester) async {
    final theme = appTheme(dark: false, paper: 1);
    final router = GoRouter(routes: [
      GoRoute(
          path: '/',
          pageBuilder: (_, s) => inkPage(
              key: s.pageKey,
              child: const Scaffold(backgroundColor: Colors.transparent, body: Text('q')))),
    ]);
    await tester.pumpWidget(MaterialApp.router(theme: theme, routerConfig: router));
    await tester.pumpAndSettle();
    final boxes = tester.widgetList<ColoredBox>(
        find.ancestor(of: find.text('q'), matching: find.byType(ColoredBox)));
    expect(boxes.any((b) => b.color == theme.scaffoldBackgroundColor), isTrue);
  });
}
