// Luồng tab Khám phá đi hết một vòng: chờ → có dữ liệu → bấm vào truyện,
// và nhánh hỏng: lỗi mạng → bấm Thử lại → nạp lại.
//   flutter test test/explore_flow_test.dart
//
// Đây là test LUỒNG, không phải test đơn vị: nó dựng HomeScreen thật, router
// thật, chỉ thay tầng dữ liệu. Mục đích là bắt những chỗ gãy Ở KHỚP NỐI —
// provider trả về mà màn không vẽ, bấm vào bìa mà đi sai đường — thứ mà test
// từng hàm riêng lẻ không thấy.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:novel_reader/data.dart';
import 'package:novel_reader/screens/explore/home.dart';
import 'package:novel_reader/theme.dart';
import 'package:novel_reader/widgets.dart';

/// cover_url để null ở mọi truyện: widget test chặn HTTP, có URL thì mỗi tấm bìa
/// là một lần tải hỏng vô ích. Bìa đã có test riêng ở endpoint_failover_test.
Rec _novel(int id, String title) => {
      'id': id,
      'title_vi': title,
      'author_vi': 'Tác giả $id',
      'cover_url': null,
      'status': 'ongoing',
      'chapter_count_source': 100,
      'chapter_count_translated': 50,
      'genres': const ['Tiên hiệp'],
      'last_chapter_at': '2026-08-28T00:00:00Z',
      'source_rank': id,
      'source_id': 1,
      'sources': const {'name': 'shuhaige'},
    };

HomeSections _sections() => HomeSections(
      [_novel(1, 'Truyện Mới Một'), _novel(2, 'Truyện Mới Hai')],
      [_novel(3, 'Truyện Nổi Bật')],
      [_novel(4, 'Truyện Đề Cử A'), _novel(5, 'Truyện Đề Cử B')],
      [_novel(6, 'Truyện Đã Xong')],
    );

/// HomeScreen + router thật, nguồn dữ liệu do test quyết định.
Widget _app(Future<HomeSections> Function(Ref) load, {List<String>? visited}) {
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
    GoRoute(
      path: '/novel/:id',
      builder: (_, s) {
        visited?.add(s.pathParameters['id']!);
        return Scaffold(body: Text('CHI TIẾT ${s.pathParameters['id']}'));
      },
    ),
  ]);
  return ProviderScope(
    overrides: [homeSectionsProvider.overrideWith(load)],
    child: MaterialApp.router(theme: lightTheme, routerConfig: router),
  );
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('đang tải thì hiện skeleton, xong thì hiện các mục', (tester) async {
    // Cao 2400 để cả 4 mục cùng được dựng: ListView chỉ dựng phần lọt khung,
    // màn 900px thì "Nổi bật"/"Đã hoàn thành" nằm dưới đáy và không tồn tại.
    await tester.binding.setSurfaceSize(const Size(400, 2400));
    final gate = Completer<HomeSections>();
    await tester.pumpWidget(_app((_) => gate.future));
    await tester.pump();

    expect(find.byType(SkeletonHome), findsOneWidget,
        reason: 'chưa có dữ liệu thì phải là skeleton, không phải màn trắng');

    gate.complete(_sections());
    await tester.pumpAndSettle();

    expect(find.byType(SkeletonHome), findsNothing);
    for (final muc in ['Mới cập nhật', 'Nổi bật', 'Đề cử', 'Đã hoàn thành']) {
      expect(find.text(muc), findsWidgets, reason: 'thiếu mục "$muc"');
    }
  });

  testWidgets('bấm vào truyện thì mở đúng trang truyện đó', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 2400));
    final visited = <String>[];
    await tester.pumpWidget(
        _app((_) async => _sections(), visited: visited));
    await tester.pumpAndSettle();

    // "Truyện Mới Một" nằm ở mục Mới cập nhật, id = 1.
    await tester.tap(find.text('Truyện Mới Một').first, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(visited, ['1'], reason: 'bấm bìa phải đẩy đúng /novel/1');
    expect(find.text('CHI TIẾT 1'), findsOneWidget);
  });

  testWidgets('mất mạng thì hiện Thử lại, bấm vào thì nạp lại', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 2400));
    // Điều khiển bằng CỜ chứ không bằng "lần gọi thứ mấy": provider là autoDispose,
    // nó tự dựng lại vài lần trong một vòng pump, nên đếm lần gọi thì lần thứ hai
    // đã thành công trước khi test kịp nhìn thấy trạng thái lỗi.
    var dangHong = true;
    var soLanGoi = 0;
    await tester.pumpWidget(_app((_) async {
      soLanGoi++;
      if (dangHong) throw Exception('SocketException: mất kết nối');
      return _sections();
    }));
    await tester.pumpAndSettle();

    expect(find.text('Mất kết nối mạng'), findsOneWidget,
        reason: 'lỗi mạng phải nói tiếng người, không phơi SocketException');
    final truocKhiThuLai = soLanGoi;

    dangHong = false;
    await tester.tap(find.text('Thử lại'));
    await tester.pumpAndSettle();

    expect(soLanGoi, greaterThan(truocKhiThuLai),
        reason: 'Thử lại phải gọi lại tầng dữ liệu');
    expect(find.text('Mất kết nối mạng'), findsNothing);
    expect(find.text('Truyện Mới Một'), findsWidgets);
  });
}
