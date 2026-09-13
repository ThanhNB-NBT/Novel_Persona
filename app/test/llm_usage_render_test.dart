// Soi màn Thống kê API (Cài đặt → Quản trị → Thống kê API):
//   flutter test test/llm_usage_render_test.dart
// → build/llm_usage_preview.png — MỞ RA NHÌN trước khi commit.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:novel_reader/data.dart';
import 'package:novel_reader/screens/admin/llm_usage.dart';
import 'package:novel_reader/theme.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  test('parseGeminiModels khớp parse_gemini_models của worker', () {
    final m = parseGeminiModels(' a 15/250000/500 , b , c x/1/2, d 1/2/0');
    expect(m.map((e) => (e.name, e.rpm, e.tpm, e.rpd)).toList(), [
      ('a', 15, 250000, 500), ('b', 5, 250000, 20), ('c', 5, 250000, 20), ('d', 1, 2, 0),
    ]);
  });

  testWidgets('render màn Thống kê API ra PNG', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 2000));
    final key = GlobalKey();
    final p = DateTime.now().toUtc().subtract(const Duration(hours: 7));
    String day(int back) => DateTime.utc(p.year, p.month, p.day - back).toIso8601String().substring(0, 10);
    Rec row(int back, String prov, String k, String model, int req, {int rl = 0, int f = 0}) => {
          'day': day(back), 'provider': prov, 'key_label': k, 'model': model, 'requests': req,
          'ok': req - rl - f, 'rate_limited': rl, 'failed': f, 'prompt_tokens': req * 2900,
          'completion_tokens': req * 2600, 'total_latency_ms': req * 9800,
        };
    final usage = <Rec>[
      for (var b = 0; b < 12; b++) ...[
        for (var k = 1; k <= 4; k++) row(b, 'gemini', 'gemini#$k', 'gemini-3.1-flash-lite', 380 + 30 * k - b * 9),
        row(b, 'gemini', 'gemini#1', 'gemini-3.5-flash-lite', 120 + b * 10, rl: b == 3 ? 4 : 0),
        row(b, 'gemini', 'gemini#2', 'gemma-4-26b-a4b-it', 60),
        if (b % 3 == 0) row(b, 'nvidia', 'nvidia#1', 'google/gemma-4-31b-it', 140 - b * 5, f: 6),
      ],
    ];
    await tester.pumpWidget(ProviderScope(
      overrides: [
        llmUsageDailyProvider.overrideWith((ref) async => {
              'usage': usage,
              'chapters': [for (var b = 0; b < 12; b++) {'day': day(b), 'n': 900 - b * 20}],
            }),
        crawlSettingsProvider.overrideWith((ref) async => [
              {
                'key': 'gemini_models',
                'value': 'gemini-3.1-flash-lite 15/250000/500,gemini-3.5-flash-lite 15/250000/500,'
                    'gemma-4-26b-a4b-it 30/16000/14400,gemma-4-31b-it 30/16000/14400',
              },
            ]),
        tokenUsageProvider.overrideWith((ref) async => [
              {'model_used': 'gemini-3.1-flash-lite', 'chapters': 8400,
               'prompt_tokens': 24000000, 'completion_tokens': 21000000},
            ]),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: lightTheme,
        home: RepaintBoundary(key: key, child: const LlmUsageScreen()),
      ),
    ));
    await tester.pumpAndSettle();

    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final bytes = await tester.runAsync(() async {
      final img = await boundary.toImage(pixelRatio: 1.5);
      return img.toByteData(format: ui.ImageByteFormat.png);
    });
    Directory('build').createSync(recursive: true);
    File('build/llm_usage_preview.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    expect(File('build/llm_usage_preview.png').lengthSync(), greaterThan(10000));
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
  });
}
