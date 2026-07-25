// Test widget chung: render đúng, không crash, semantics ổn.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/widgets.dart';

/// Bọc widget trong MaterialApp + theme chuẩn để test độc lập.
Widget wrap(Widget child) => MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1A6B54)),
        useMaterial3: true,
      ),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  group('TagChip', () {
    testWidgets('hiện label', (tester) async {
      await tester.pumpWidget(wrap(const TagChip('Hoàn thành')));
      expect(find.text('Hoàn thành'), findsOneWidget);
    });

    testWidgets('màu tuỳ chỉnh không crash', (tester) async {
      await tester.pumpWidget(wrap(const TagChip('Đang ra', color: Colors.orange)));
      expect(find.text('Đang ra'), findsOneWidget);
    });
  });

  group('GenreChips', () {
    testWidgets('nối thể loại bằng chấm giữa', (tester) async {
      await tester.pumpWidget(
          wrap(const GenreChips(['Huyền Huyễn', 'Đô Thị', 'Tiên Hiệp'])));
      expect(find.text('Huyền Huyễn · Đô Thị · Tiên Hiệp'), findsOneWidget);
    });

    testWidgets('max giới hạn số thể loại hiện', (tester) async {
      await tester.pumpWidget(
          wrap(const GenreChips(['A', 'B', 'C', 'D'], max: 2)));
      expect(find.text('A · B'), findsOneWidget);
    });
  });

  group('ProgressRibbon', () {
    testWidgets('render với value 0..1', (tester) async {
      await tester.pumpWidget(wrap(const ProgressRibbon(0.5)));
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('semantics có nhãn tiến độ', (tester) async {
      await tester.pumpWidget(wrap(const ProgressRibbon(0.75)));
      final sem = tester.getSemantics(find.bySemanticsLabel('Tiến độ đọc'));
      expect(sem, isNotNull);
    });
  });

  group('SectionHeader', () {
    testWidgets('hiện tiêu đề', (tester) async {
      await tester.pumpWidget(wrap(const SectionHeader('Mới cập nhật')));
      expect(find.text('Mới cập nhật'), findsOneWidget);
    });

    testWidgets('có nút Xem tất cả khi onMore != null', (tester) async {
      await tester.pumpWidget(
          wrap(SectionHeader('Nổi bật', onMore: () {})));
      expect(find.text('Xem tất cả'), findsOneWidget);
    });

    testWidgets('không có nút Xem tất cả khi onMore null', (tester) async {
      await tester.pumpWidget(wrap(const SectionHeader('Đề cử')));
      expect(find.text('Xem tất cả'), findsNothing);
    });
  });

  group('RowDivider', () {
    testWidgets('render không crash', (tester) async {
      await tester.pumpWidget(wrap(const RowDivider()));
      expect(find.byType(Divider), findsOneWidget);
    });
  });

  group('AppError', () {
    testWidgets('lỗi mạng → hiện "Mất kết nối"', (tester) async {
      await tester.pumpWidget(
          wrap(const AppError(SocketException('Failed host lookup'))));
      expect(find.text('Mất kết nối mạng'), findsOneWidget);
    });

    testWidgets('lỗi khác → hiện "Có lỗi xảy ra"', (tester) async {
      await tester.pumpWidget(wrap(const AppError('something broke')));
      expect(find.text('Có lỗi xảy ra'), findsOneWidget);
    });

    testWidgets('có nút Thử lại khi onRetry != null', (tester) async {
      await tester.pumpWidget(
          wrap(AppError('err', onRetry: () {})));
      expect(find.text('Thử lại'), findsOneWidget);
    });
  });

  group('TapScale', () {
    testWidgets('tap gọi onTap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(wrap(TapScale(
        onTap: () => tapped = true,
        child: const Text('Nhấn tôi'),
      )));
      await tester.tap(find.text('Nhấn tôi'));
      expect(tapped, isTrue);
    });
  });
}

/// Fake exception class for testing (không cần import dart:io).
class SocketException implements Exception {
  final String message;
  const SocketException(this.message);
  @override
  String toString() => 'SocketException: $message';
}
