// sortLikeClaim phải ra đúng thứ tự worker claim (migration 117) — cùng 2 ca đã tái hiện lỗi
// trên Postgres: job dịch lại cùng created_at bị xáo, truyện nhảy cóc ch10-12 xếp trước ch1-3.
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/data.dart';

Rec job(int novel, int? ch, String created, {int prio = 45}) => {
      'novel_id': novel, 'priority': prio, 'created_at': created,
      'chapters': ch == null ? null : {'chapter_index': ch},
    };

void main() {
  test('xếp theo priority → truyện chờ lâu nhất → chương tăng dần', () {
    const t1 = '2026-09-14T01:00:00Z', t2 = '2026-09-14T02:00:00Z', t3 = '2026-09-14T03:00:00Z';
    final jobs = [
      for (final c in [6, 1, 8, 3, 2, 7, 5, 4]) job(1, c, t1), // dịch lại: cùng created_at
      for (final c in [12, 10, 11]) job(2, c, t2),
      for (final c in [3, 1, 2]) job(2, c, t3), // quay lại dịch đầu truyện
      job(2, null, t3, prio: 5), // metadata ưu tiên cao
    ];
    sortLikeClaim(jobs);
    expect([for (final j in jobs) (j['novel_id'], (j['chapters'] as Map?)?['chapter_index'])], [
      (2, null),
      for (var c = 1; c <= 8; c++) (1, c),
      (2, 1), (2, 2), (2, 3), (2, 10), (2, 11), (2, 12),
    ]);
  });
}
