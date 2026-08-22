// Soi tab Crawl trong Quản trị (thẻ nhịp 24h + hàng cấu hình giá trị dài):
//   flutter test test/crawl_tab_render_test.dart
// → build/crawl_tab_preview.png — MỞ RA NHÌN trước khi commit.
//
// Font PJS/JetBrains Mono đã bundle trong assets/google_fonts/ nên google_fonts
// load từ rootBundle, không gọi mạng (widget test chặn mọi HTTP).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:novel_reader/data.dart';
import 'package:novel_reader/screens/admin/tabs/crawl_tab.dart';
import 'package:novel_reader/theme.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('render tab Crawl ra PNG', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    final key = GlobalKey();
    final now = DateTime.now().toUtc().toIso8601String();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        crawlPulseProvider.overrideWith((ref) async => const {
              'novels24h': 5, 'chapters24h': 812, 'done24h': 129, 'queued': 20,
              'failedChapters': 3, 'metaPending': 11, 'tracked': 940, 'failedJobs': 2,
            }),
        workerHeartbeatProvider.overrideWith((ref) async => [
              {'name': 'crawler', 'at': now, 'note': 'chu kỳ 75 phút'},
              {'name': 'translator', 'at': now, 'note': null},
            ]),
        crawlSettingsProvider.overrideWith((ref) async => [
              {
                'key': 'llm_model',
                'value': 'meta/llama-3.1-70b-instruct,minimaxai/minimax-m3,'
                    'nvidia/llama-3.3-nemotron-super-49b-v1',
                'note': 'DỊCH · Model NVIDIA cho 3 việc phụ',
              },
              {'key': 'llm_timeout_sec', 'value': '90', 'note': 'DỊCH · Timeout 1 call LLM'},
              {'key': 'crawl_interval_min', 'value': '75', 'note': 'Chu kỳ discovery (phút)'},
            ]),
        crawlSourcesProvider.overrideWith((ref) async => [
              {'id': 1, 'name': 'shuhaige', 'base_url': 'https://www.shuhaige.net',
               'enabled': true, 'fail_count': 0, 'last_ok_at': now},
            ]),
        newNovels24hProvider.overrideWith((ref) async => const <Rec>[]),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: lightTheme,
        home: RepaintBoundary(key: key, child: const Scaffold(body: CrawlTab())),
      ),
    ));
    await tester.pumpAndSettle();

    // mở mục CẤU HÌNH DỊCH để thấy hàng model LLM (mặc định thu gọn)
    await tester.tap(find.text('CẤU HÌNH DỊCH'));
    await tester.pumpAndSettle();

    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    // toImage cần event loop THẬT — await thẳng trong fake-async zone là treo tới timeout
    final bytes = await tester.runAsync(() async {
      final img = await boundary.toImage(pixelRatio: 2);
      return img.toByteData(format: ui.ImageByteFormat.png);
    });
    Directory('build').createSync(recursive: true);
    File('build/crawl_tab_preview.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    expect(File('build/crawl_tab_preview.png').lengthSync(), greaterThan(10000));
    await tester.pumpWidget(const SizedBox()); // gỡ widget, khỏi kẹt vì RefreshIndicator
    // nhả event-loop thật một nhịp để mọi timer treo lửng chạy xong trước khi test kết thúc
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
  });
}
