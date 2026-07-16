import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/ink_transition.dart';

// Vết mực phải PHỦ KÍN màn ở t=1 (không thì màn mới bị khuyết góc vĩnh viễn)
// và còn NHỎ ở t thấp (không thì chẳng có gì để loang).
void main() {
  test('inkBlobPath phủ kín màn ở t=1, còn nhỏ ở t=0.05', () {
    const size = Size(411, 890); // cỡ điện thoại thật
    final full = inkBlobPath(size, 1);
    for (final corner in [
      Offset.zero,
      const Offset(411, 0),
      const Offset(0, 890),
      const Offset(411, 890),
    ]) {
      expect(full.contains(corner), isTrue, reason: 'khuyết góc $corner');
    }
    final small = inkBlobPath(size, 0.05);
    expect(small.contains(Offset.zero), isFalse);
    expect(small.contains(const Offset(411, 890)), isFalse);
    // tâm loang phải đã hiện từ sớm
    expect(small.contains(Offset(size.width * 0.5, size.height * 0.42)), isTrue);
  });
}
