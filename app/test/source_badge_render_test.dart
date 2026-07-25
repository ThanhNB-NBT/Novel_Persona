// Soi badge nguồn crawl trên UI khi sửa NovelListRow/PosterTile/SourceBadge:
//   flutter test test/source_badge_render_test.dart
// → build/source_badge_preview.png — MỞ RA NHÌN trước khi commit.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:novel_reader/data.dart';
import 'package:novel_reader/widgets.dart';

Rec _novel(String title, String source) => {
      'id': title.hashCode,
      'title_vi': title,
      'author_vi': 'Tác giả $source',
      'chapter_count_source': 1234,
      'genres': const ['Huyền Huyễn', 'Đô Thị'],
      'sources': {'name': source},
    };

void main() {
  // Preview chỉ dùng widget không phụ thuộc google_fonts (SourceBadge/PosterTile);
  // vẫn tắt runtime fetch như lưới an toàn phòng khi có widget con gọi mono.
  GoogleFonts.config.allowRuntimeFetching = false;

  test('sourceName lấy đúng slug, rỗng khi thiếu', () {
    expect(sourceName(_novel('A', 'shuhaige')), 'shuhaige');
    expect(sourceName({'title_vi': 'B'}), '');
  });

  testWidgets('render badge nguồn ra PNG', (tester) async {
    await tester.binding.setSurfaceSize(const Size(440, 400));
    final key = GlobalKey();
    final cs = ColorScheme.fromSeed(seedColor: const Color(0xFF3576F5));
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: cs, useMaterial3: true),
      home: RepaintBoundary(
        key: key,
        child: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Poster có badge nguồn (Khám phá: rail/poster/ranking).
                // Poster cuối không có nguồn → không hiện badge.
                Row(children: [
                  PosterTile(n: _novel('Phàm Nhân Tu Tiên', 'ddxs'), width: 118, onTap: () {}),
                  const SizedBox(width: 12),
                  PosterTile(n: _novel('Tru Tiên', 'xsbique'), width: 118, onTap: () {}),
                  const SizedBox(width: 12),
                  PosterTile(n: _novel('Không nguồn', ''), width: 118, onTap: () {}),
                ]),
                const SizedBox(height: 20),
                // Badge nguồn đứng riêng, đối chiếu trên nền sáng.
                const Wrap(spacing: 8, children: [
                  SourceBadge('shuhaige'),
                  SourceBadge('ddxs'),
                  SourceBadge('xsbique'),
                ]),
                const SizedBox(height: 20),
                // Dòng đáy NovelListRow: số chương + slug nguồn — tái dựng bỏ mono
                // (IconStat dùng google_fonts) để test không phải nạp font mạng.
                Row(children: [
                  Icon(Icons.menu_book_rounded, size: 14, color: cs.onSurfaceVariant),
                  const SizedBox(width: 4),
                  const Text('1234'),
                  const SizedBox(width: 10),
                  Text('shuhaige',
                      style: TextStyle(
                          fontSize: 11.5, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
                ]),
              ],
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await boundary.toImage(pixelRatio: 2);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      File('build/source_badge_preview.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes!.buffer.asUint8List());
    });
    expect(File('build/source_badge_preview.png').lengthSync(), greaterThan(5000));
    // gỡ widget để dispose AnimationController (TapScale) — tránh test kẹt
    await tester.pumpWidget(const SizedBox());
  });
}
