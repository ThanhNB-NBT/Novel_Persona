// Bộ màu nhấn (Tôi → Giao diện): mỗi bộ phải áp đúng màu và chữ trên nút đủ đọc.
//   flutter test test/accent_theme_test.dart
// → build/paper_preview.png (mỗi bộ nền sáng/tối) — MỞ RA NHÌN khi đổi màu nền.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:novel_reader/theme.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  test('mọi bộ màu: primary đúng bộ, triện đúng bộ, chữ trên nút ≥ 4.5:1', () {
    for (var i = 0; i < accents.length; i++) {
      for (final dark in [false, true]) {
        final th = appTheme(dark: dark, accent: i);
        final cs = th.colorScheme;
        expect(cs.primary, dark ? accents[i].dAccent : accents[i].accent);
        expect(th.extension<SealTone>()!.seal, dark ? accents[i].dSeal : accents[i].seal);
        expect(_contrast(cs.primary, cs.onPrimary), greaterThanOrEqualTo(4.5),
            reason: '${accents[i].name} ${dark ? "tối" : "sáng"}');
        // màu nhấn làm CHỮ trên nền giấy (link, "Xem tất cả") cũng phải đọc được
        expect(_contrast(cs.primary, th.scaffoldBackgroundColor), greaterThanOrEqualTo(4.5),
            reason: '${accents[i].name} ${dark ? "tối" : "sáng"} trên nền');
      }
    }
  });

  test('mọi bộ nền × bộ màu: nền đúng bộ, chữ chính/phụ và màu nhấn đọc được', () {
    for (var p = 0; p < papers.length; p++) {
      for (var a = 0; a < accents.length; a++) {
        for (final dark in [false, true]) {
          final th = appTheme(dark: dark, accent: a, paper: p);
          final cs = th.colorScheme;
          final why = '${papers[p].name}/${accents[a].name} ${dark ? "tối" : "sáng"}';
          expect(th.scaffoldBackgroundColor, dark ? papers[p].dBg : papers[p].bg);
          for (final surf in [th.scaffoldBackgroundColor, cs.surface]) {
            expect(_contrast(cs.onSurface, surf), greaterThanOrEqualTo(7), reason: why);
            expect(_contrast(cs.onSurfaceVariant, surf), greaterThanOrEqualTo(4.5), reason: why);
            expect(_contrast(cs.primary, surf), greaterThanOrEqualTo(4.5), reason: why);
          }
        }
      }
    }
  });

  testWidgets('render các bộ nền ra PNG', (tester) async {
    await tester.binding.setSurfaceSize(Size(720, 200.0 * papers.length));
    final key = GlobalKey();
    Widget sample(int p, bool dark) => Theme(
          data: appTheme(dark: dark, paper: p),
          child: Builder(builder: (context) {
            final th = Theme.of(context);
            return Container(
              color: th.scaffoldBackgroundColor,
              padding: const EdgeInsets.all(14),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(papers[p].name, style: th.textTheme.titleMedium),
                    Text('Chữ phụ trên thẻ', style: th.textTheme.bodyMedium),
                    const SizedBox(height: 8),
                    Row(children: [
                      FilledButton(onPressed: () {}, child: const Text('Đọc')),
                      const SizedBox(width: 8),
                      Chip(label: Text('Tu tiên', style: th.textTheme.labelMedium)),
                    ]),
                  ]),
                ),
              ),
            );
          }),
        );
    await tester.pumpWidget(MaterialApp(
      home: RepaintBoundary(
        key: key,
        child: Column(children: [
          for (var p = 0; p < papers.length; p++)
            Expanded(
                child: Row(children: [
              Expanded(child: sample(p, false)),
              Expanded(child: sample(p, true)),
            ])),
        ]),
      ),
    ));
    await tester.runAsync(() async {
      final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await boundary.toImage(pixelRatio: 1);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      File('build/paper_preview.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes!.buffer.asUint8List());
    });
    expect(File('build/paper_preview.png').existsSync(), isTrue);
  });
}
