import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/tts.dart';

void main() {
  test('ttsChunks giữ nguyên chuỗi ngắn', () {
    expect(ttsChunks('Xin chào.'), ['Xin chào.']);
  });

  test('ttsChunks cắt sau dấu câu, không mất chữ, khối không quá max', () {
    final s = List.filled(40, 'Hắn rút kiếm ra khỏi vỏ.').join(' ');
    final cs = ttsChunks(s, max: 100);
    expect(cs.join(), s);
    expect(cs.every((c) => c.length <= 100), isTrue);
    expect(cs.first.endsWith('.'), isTrue);
  });

  test('ttsChunks cắt cứng khi không có dấu câu', () {
    final s = 'a' * 250;
    final cs = ttsChunks(s, max: 100);
    expect(cs.join(), s);
    expect(cs.length, 3);
  });
}
