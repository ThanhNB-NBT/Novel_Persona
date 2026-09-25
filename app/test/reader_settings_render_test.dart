// Sheet Cài đặt đọc: đủ 15 màu nền hiện ra, màu mặc định (Giấy cũ) không bị khuất.
//   flutter test test/reader_settings_render_test.dart
// → build/reader_settings_preview.png — MỞ RA NHÌN khi sửa sheet.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:novel_reader/data.dart';
import 'package:novel_reader/screens/reader/reader_settings.dart';
import 'package:novel_reader/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  testWidgets('đủ 15 màu nền, màu mặc định hiện trên màn', (tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));
    final key = GlobalKey();
    // chip font Lora/Literata… tải qua mạng — test chặn mạng nên nuốt riêng lỗi đó
    await runZonedGuarded(() async {
      await tester.pumpWidget(ProviderScope(
        child: RepaintBoundary(
          key: key,
          child: MaterialApp(
            theme: appTheme(dark: false),
            home: Consumer(
              builder: (context, ref, _) => Scaffold(
                body: TextButton(
                    onPressed: () => showReaderSettingsSheet(context, ref, onRetranslate: () {}),
                    child: const Text('mở')),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('mở'));
      await tester.pumpAndSettle();
    }, (e, st) {
      if (!'$e'.contains('allowRuntimeFetching')) throw e;
    });

    for (final c in readerColors) {
      expect(find.bySemanticsLabel('Nền ${c.name}'), findsOneWidget);
    }
    // Giấy cũ (mặc định) phải nằm trong khung nhìn, không khuất ngoài mép
    final r = tester.getRect(find.bySemanticsLabel('Nền Giấy cũ'));
    expect(r.right, lessThanOrEqualTo(412));
    expect(r.bottom, lessThanOrEqualTo(915));

    await tester.runAsync(() async {
      final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await boundary.toImage(pixelRatio: 1);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      File('build/reader_settings_preview.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  });
}
