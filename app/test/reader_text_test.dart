// Test logic văn bản thuần của reader: ranh giới từ (chạm-để-sửa) + tách câu hiển thị.
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/screens/reader/reader.dart';

void main() {
  group('wordLeft / wordRight — mở rộng vùng chọn theo từ', () {
    const s = 'Lâm Tùng nhìn về phía xa';

    test('giữa từ → lùi/tiến hết từ đó', () {
      // chạm giữa "Tùng" (index 5)
      expect(wordLeft(s, 5), 4); // đầu "Tùng"
      expect(wordRight(s, 5), 8); // cuối "Tùng"
      expect(s.substring(wordLeft(s, 5), wordRight(s, 5)), 'Tùng');
    });

    test('mép chuỗi không văng', () {
      expect(wordLeft(s, 0), 0);
      expect(wordRight(s, s.length), s.length);
      expect(s.substring(wordLeft(s, 0), wordRight(s, 0)), 'Lâm');
    });

    test('đứng trên khoảng trắng → nuốt trắng rồi lấy từ kề', () {
      // index 3 là dấu cách giữa "Lâm" và "Tùng"
      expect(wordLeft(s, 3), 0); // lùi về đầu "Lâm"
      expect(wordRight(s, 3), 8); // tiến qua "Tùng"
    });

    test(r'\n là ranh giới — không nuốt xuyên đoạn (chế độ lật trang)', () {
      const p = 'cuoi doan mot\ndau doan hai';
      final iMot = p.indexOf('mot'), iDau = p.indexOf('dau');
      // chạm vào "mot": không được lan xuống "dau"
      expect(p.substring(wordLeft(p, iMot + 1), wordRight(p, iMot + 1)), 'mot');
      // chạm vào "dau": không được lan ngược lên "mot"
      expect(p.substring(wordLeft(p, iDau + 1), wordRight(p, iDau + 1)), 'dau');
    });
  });

  group('splitBySentence — tách đoạn dài thành câu dễ đọc', () {
    test('đoạn 1 câu giữ nguyên (trim)', () {
      expect(splitBySentence(['  Một câu duy nhất.  ']), ['Một câu duy nhất.']);
    });

    test('đoạn nhiều câu tách ra, không mất chữ', () {
      final input = 'Câu một đủ dài để đứng riêng một dòng nhé. '
          'Câu hai cũng đủ dài để đứng riêng một dòng nhé. '
          'Câu ba cũng đủ dài để đứng riêng một dòng nhé.';
      final out = splitBySentence([input]);
      expect(out.length, greaterThan(1));
      expect(out.join(' '), input); // ghép lại đủ nội dung
    });

    test('câu quá ngắn gộp với câu sau, không để mẩu cụt', () {
      final out = splitBySentence(['Ngắn. Cũng ngắn. Vẫn còn khá ngắn mà.']);
      expect(out, hasLength(1)); // cả 3 câu ngắn gộp làm 1
    });

    test('không ngắt dấu ? nằm sát ngoặc kép đóng', () {
      const p = '"Ngươi có biết không?" hắn hỏi với giọng trầm thấp đầy đe dọa.';
      expect(splitBySentence([p]), [p]);
    });

    test('dấu kết câu full-width (。！？) cũng ngắt được', () {
      final out = splitBySentence([
        'Câu tiếng Trung dài đủ bốn mươi ký tự thì phải。 '
        'Câu thứ hai cũng dài đủ bốn mươi ký tự thì phải！'
      ]);
      expect(out.length, 2);
    });
  });
}
