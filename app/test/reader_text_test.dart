// Test logic văn bản thuần của reader: ranh giới từ (chạm-để-sửa) + tách câu hiển thị.
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/chapter_paras.dart';
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

    test('đứng trên khoảng trắng → lấy trọn từ kề bên TRÁI (từ vừa chạm mép)', () {
      // index 3 là dấu cách ngay sau "Lâm" → chọn "Lâm"; muốn "Tùng" thì bấm nút ⟩.
      expect(wordLeft(s, 3), 0);
      expect(wordRight(s, 3), 3);
      expect(s.substring(wordLeft(s, 3), wordRight(s, 3)), 'Lâm');
    });

    test('dấu nháy, phẩy và hai chấm không bị chọn kèm từ', () {
      const p = '“Lâm Tùng,” hắn nói: đi thôi.';
      final comma = p.indexOf(',');
      final colon = p.indexOf(':');
      expect(p.substring(wordLeft(p, comma), wordRight(p, comma)), 'Tùng');
      expect(p.substring(wordLeft(p, colon), wordRight(p, colon)), 'nói');
    });

    test('nút mở rộng đi qua dấu câu để lấy từ kế tiếp', () {
      const p = 'Lâm, Tùng nói';
      expect(previousWordStart(p, 5), 0);
      expect(nextWordEnd(p, 3), 9);
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

  group('withoutLeadingPreviousEcho — không hiện lại đuôi chương trước', () {
    test('chỉ bỏ các dòng đầu khớp đuôi chương trước', () {
      const previous = 'Lâm Tùng khép cửa lại.\nĐêm nay hắn không ngủ.';
      const current = '$previous\nSáng hôm sau, hắn lên đường.';
      expect(withoutLeadingPreviousEcho(current, previous), 'Sáng hôm sau, hắn lên đường.');
    });

    test('không đụng nội dung mới', () {
      expect(withoutLeadingPreviousEcho('Sáng hôm sau, hắn lên đường.', 'Đêm nay hắn không ngủ.'),
          'Sáng hôm sau, hắn lên đường.');
    });
  });

  group('extendLeftWord / extendRightWord — mở rộng chọn, KHÔNG nuốt dấu câu', () {
    test('vượt khoảng trắng thì mở rộng thêm 1 từ', () {
      const s = 'Lâm Tùng nhìn về phía xa';
      // chọn "nhìn" = [9,13); mở phải → thêm "về", mở trái → thêm "Tùng"
      expect(s.substring(9, extendRightWord(s, 13)), 'nhìn về');
      expect(s.substring(extendLeftWord(s, 9), 13), 'Tùng nhìn');
    });

    test('gặp dấu câu thì DỪNG, không kéo dấu vào vùng chọn', () {
      const s = 'nói: nhìn về'; // n0 ó1 i2 :3 ␣4 n5..n8 ␣9 v10 ề11
      expect(extendRightWord(s, 3), 3); // "nói" + dấu ":" ngay sau → không mở rộng
      expect(extendLeftWord(s, 5), 5); // "nhìn" bên trái là ":" → không mở rộng
      expect(extendRightWord(s, 9), 12); // "nhìn" → "về" cách bởi khoảng trắng → mở được
    });
  });
}
