// Bảng chọn model (tab Crawl → Cấu hình dịch) phải trả đúng định dạng worker đọc:
// gemini_models = 'tên RPM/TPM/RPD,…' theo thứ tự; chuỗi NVIDIA chỉ tên.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:novel_reader/screens/admin/tabs/model_picker.dart';

Future<String?> _run(WidgetTester tester, ModelListKind kind, String value,
    Future<void> Function() act) async {
  String? result = 'chưa đóng';
  await tester.binding.setSurfaceSize(const Size(420, 2400));
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => TextButton(
        onPressed: () async =>
            result = await showModelPicker(context, kind: kind, title: 't', value: value),
        child: const Text('mở'),
      ),
    ),
  ));
  await tester.tap(find.text('mở'));
  await tester.pumpAndSettle();
  await act();
  await tester.tap(find.text('Lưu'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('gemini: giữ thứ tự + trần, thêm model lấy trần từ danh mục', (tester) async {
    final r = await _run(tester, ModelListKind.gemini, 'gemini-3.1-flash-lite 15/250000/500', () async {
      await tester.tap(find.widgetWithText(ListTile, 'gemma-4-26b-a4b-it'));
      await tester.pumpAndSettle();
    });
    expect(r, 'gemini-3.1-flash-lite 15/250000/500,gemma-4-26b-a4b-it 30/16000/14400');
  });

  testWidgets('nvidia: chỉ tên, bỏ model đang dùng', (tester) async {
    final r = await _run(tester, ModelListKind.nvidia, 'google/gemma-4-31b-it,moonshotai/kimi-k3', () async {
      await tester.tap(find.byTooltip('Bỏ khỏi chuỗi').last);
      await tester.pumpAndSettle();
    });
    expect(r, 'google/gemma-4-31b-it');
  });
}
