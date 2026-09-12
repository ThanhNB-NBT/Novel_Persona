// Test logic văn bản thuần của reader: ranh giới từ (chạm-để-sửa) + tách câu hiển thị.
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/chapter_paras.dart';
import 'package:novel_reader/models/chapter.dart';
import 'package:novel_reader/models/novel.dart';
import 'package:novel_reader/screens/reader/reader_text.dart';
import 'package:novel_reader/tts.dart';

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

  group('ttsLocalPara / ttsMovedAway — logic highlight TTS tách từ reader', () {
    const otherNovel = TtsState(novelId: 7, chapterIndex: 3, playing: true);
    const movedChapter =
        TtsState(novelId: 1, chapterIndex: 5, playing: true); // cùng truyện, chương khác
    const here = TtsState(novelId: 1, chapterIndex: 2, playing: true);
    const pausedHere = TtsState(novelId: 1, chapterIndex: 2, playing: false, paused: true);

    test('chương đang nghe → mirror đoạn; chương khác/pause → -1', () {
      expect(ttsLocalPara(here, novelId: 1, chapterIndex: 2, paraAt: 5), 5);
      expect(ttsLocalPara(otherNovel, novelId: 1, chapterIndex: 2, paraAt: 5), -1);
      expect(ttsLocalPara(pausedHere, novelId: 1, chapterIndex: 2, paraAt: 5), -1);
    });

    test('tự sang chương khác (cùng truyện, đang phát) → reader đi theo', () {
      expect(ttsMovedAway(movedChapter, novelId: 1, chapterIndex: 2), isTrue);
      expect(ttsMovedAway(here, novelId: 1, chapterIndex: 2), isFalse);
      // truyện khác thì không nhảy màn
      expect(ttsMovedAway(otherNovel, novelId: 1, chapterIndex: 2), isFalse);
    });
  });

  group('paginateText — phân trang chế độ lật trang', () {
    const style = TextStyle(fontSize: 16, height: 1.4);
    const maxWidth = 360.0;
    const pageH = 600.0;
    const firstH = 500.0;

    test('chuỗi rỗng trả về một trang rỗng', () {
      final pages = paginateText('', style, maxWidth, pageH, firstH);
      expect(pages, ['']);
    });

    test('chuỗi ngắn vừa trọn một trang', () {
      const shortText = 'Đây là một đoạn văn ngắn gọn.';
      final pages = paginateText(shortText, style, maxWidth, pageH, firstH);
      expect(pages, [shortText]);
    });

    test('văn bản dài nhiều đoạn được cắt thành nhiều trang và không sót chữ', () {
      final paras = List.generate(
          30,
          (i) =>
              'Đoạn văn thứ $i của chương truyện mô tả cảnh trời mây non nước '
              'khi nhân vật chính bước vào thế giới tu chân huyền diệu.');
      final fullText = paras.join('\n\n');
      final pages = paginateText(fullText, style, maxWidth, pageH, firstH);

      expect(pages.length, greaterThan(1));
      for (final p in pages) {
        expect(p.isNotEmpty, isTrue);
      }
    });
  });

  group('Novel & Chapter models test', () {
    test('Novel.fromJson parses json correctly', () {
      final json = {
        'id': 42,
        'title_vi': 'Mục Thần Ký',
        'title_zh': '牧神记',
        'author_vi': 'Trạch Trư',
        'status': 'completed',
        'chapter_count_source': 1800,
        'chapter_count_translated': 1800,
        'genres': ['Tiên Hiệp', 'Huyền Huyễn'],
        'sources': {'name': 'Qidian'},
      };
      final novel = Novel.fromJson(json);
      expect(novel.id, 42);
      expect(novel.titleVi, 'Mục Thần Ký');
      expect(novel.authorVi, 'Trạch Trư');
      expect(novel.sourceName, 'Qidian');
      expect(novel.genres, contains('Tiên Hiệp'));
    });

    test('Chapter.fromJson parses json correctly', () {
      final json = {
        'chapter_index': 1,
        'title_vi': 'Chương 1: Tàn Lão Thôn',
        'content_vi': 'Mặt trời lặn xuống núi...',
        'translation_status': 'translated',
      };
      final ch = Chapter.fromJson(json);
      expect(ch.chapterIndex, 1);
      expect(ch.titleVi, 'Chương 1: Tàn Lão Thôn');
      expect(ch.contentVi, contains('Mặt trời lặn'));
    });
  });
}
