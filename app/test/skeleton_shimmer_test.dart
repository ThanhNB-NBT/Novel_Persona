// Vệt sáng skeleton phải THẤY ĐƯỢC, không chỉ tồn tại trên lý thuyết.
//   flutter test test/skeleton_shimmer_test.dart
//
// Bản cũ vẽ ô ở alpha 0.09 rồi phủ gradient bằng BlendMode.srcATop — srcATop giữ
// lại nền ở chỗ nguồn mờ, nên vệt 0.09→0.22 co lại còn 0.008→0.02: chạy thật mà
// mắt không thấy. Test giữ cho lỗi đó không quay lại: chụp 2 khung ở 2 pha khác
// nhau của vòng shimmer, đòi độ chênh ALPHA phải vượt ngưỡng nhìn được.
//
// Đo alpha chứ không đo màu: ảnh chụp ra là premultiplied, kênh màu đã bị nhân
// với alpha nên số rất nhỏ và phụ thuộc màu chủ đề. Alpha là đại lượng thiết kế
// thật: nền 0.09 (≈23/255), chỗ vệt quét qua 0.22 (≈56/255).
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/widgets.dart';

/// Alpha của từng pixel trên 1 hàng cắt ngang các ô skeleton.
/// toImage/toByteData phải chạy trong runAsync — trong widget test thời gian bị
/// đóng băng, await thẳng sẽ treo vĩnh viễn chứ không lỗi.
Future<List<int>> _rowAlpha(WidgetTester tester, GlobalKey key) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final (image, data) = (await tester.runAsync(() async {
    final img = await boundary.toImage();
    return (img, await img.toByteData(format: ui.ImageByteFormat.rawRgba));
  }))!;
  final w = image.width, h = image.height;
  final y = h ~/ 4; // cắt qua khối hero, chỗ chắc chắn có ô skeleton
  final out = [
    for (var x = 0; x < w; x++) data!.getUint8(((y * w) + x) * 4 + 3),
  ];
  image.dispose();
  return out;
}

void main() {
  testWidgets('vệt shimmer đủ tương phản để nhìn thấy', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 700));
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RepaintBoundary(key: key, child: const SkeletonHome()),
      ),
    ));
    await tester.pump();

    // Ba pha trong một vòng (controller 1200ms) — vệt hẹp nên hai pha bất kỳ vẫn
    // có thể trùng chỗ tối; lấy biên độ trên cả ba mới chắc.
    final frames = <List<int>>[await _rowAlpha(tester, key)];
    for (var i = 0; i < 2; i++) {
      await tester.pump(const Duration(milliseconds: 400));
      frames.add(await _rowAlpha(tester, key));
    }

    // Với mỗi pixel, chênh lệch alpha lớn nhất giữa các khung.
    var maxDelta = 0;
    for (var x = 0; x < frames.first.length; x++) {
      final vals = [for (final f in frames) f[x]];
      final d = vals.reduce((a, b) => a > b ? a : b) -
          vals.reduce((a, b) => a < b ? a : b);
      if (d > maxDelta) maxDelta = d;
    }
    // Thiết kế: 0.09 → 0.22, tức ~23 → ~56 trên thang 255 (chênh ~33).
    // Đã thử ngược: dựng lại bản srcATop cũ thì số này ra ĐÚNG 0 — srcATop giữ
    // nguyên alpha của nền, vệt chỉ nhúc nhích ở kênh màu vài phần nghìn.
    expect(maxDelta, greaterThan(15),
        reason: 'vệt sáng gần như không đổi giữa các khung → shimmer vô hình');
  });
}
