import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/cultivation.dart';

void main() {
  Map<String, dynamic> st(int realm, String? race,
          {int btBonus = 0, int? phapchuBt}) =>
      {
        'realm': realm,
        'race': race,
        'bt_bonus_pct': btBonus,
        if (phapchuBt != null)
          'equipped': {
            'phapchu': {
              'effect': {'bt_pct': phapchuBt}
            }
          },
      };

  test('cultBreakthroughChance khớp công thức SQL cult_advance (044 dòng 163-165)',
      () {
    expect(cultBreakthroughChance(st(1, 'nhan')), 90); // +5 nhân tộc
    expect(cultBreakthroughChance(st(1, 'ma')), 80); // −5 ma tộc
    expect(cultBreakthroughChance(st(1, 'yeu')), 85); // tộc khác: 0
    expect(cultBreakthroughChance(st(1, null)), 85); // chưa chọn tộc: 0
    expect(cultBreakthroughChance(st(3, 'nhan')), 74); // 85−16+5
    expect(cultBreakthroughChance(st(9, 'ma')), 16); // 85−64−5
    // pháp chú + đan hộ thân + nhân → vượt trần, kẹp 100
    expect(cultBreakthroughChance(st(1, 'nhan', btBonus: 20, phapchuBt: 10)), 100);
  });
}
