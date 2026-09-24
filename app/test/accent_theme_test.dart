// Bộ màu nhấn (Tôi → Giao diện): mỗi bộ phải áp đúng màu và chữ trên nút đủ đọc.
//   flutter test test/accent_theme_test.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
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
}
