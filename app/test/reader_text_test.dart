// Test logic văn bản thuần của reader: ranh giới từ (chạm-để-sửa) + tách câu hiển thị.
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/chapter_paras.dart';
import 'package:novel_reader/models/chapter.dart';
import 'package:novel_reader/models/novel.dart';
import 'package:novel_reader/screens/reader/reader_text.dart';
import 'package:novel_reader/tts.dart';

void main() {
  _glossaryRangeTests();
  _termsFromSourceTests();
  _sourceLineTests();
  _nameRunTests();
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
    test('contentParagraphs đổi 【】 thành [ ] (hết thụt nửa ô đầu đoạn)', () {
      expect(contentParagraphs('【Haiz, phải nói sao đây?】\n\nHắn cười.'),
          ['[Haiz, phải nói sao đây?]', 'Hắn cười.']);
    });

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

/// Dò vùng thuật ngữ để tô dấu: phải khớp theo RANH GIỚI TỪ giống replace_word của
/// worker, kẻo tô một đằng vá một nẻo.
void _glossaryRangeTests() {
  group('glossaryRanges — tô dấu chỗ glossary đã áp', () {
    test('khớp trọn từ, trả đúng vị trí', () {
      const s = 'Lâm Hiên bước vào, Lâm Hiên mỉm cười.';
      final r = glossaryRanges(s, ['Lâm Hiên']);
      expect(r.length, 2);
      expect(s.substring(r[0].$1, r[0].$2), 'Lâm Hiên');
      expect(s.substring(r[1].$1, r[1].$2), 'Lâm Hiên');
    });

    test('KHÔNG khớp khi dính vào từ khác (bài học "xmuội")', () {
      expect(glossaryRanges('Hiênnhà rất rộng', ['Hiên']), isEmpty);
      expect(glossaryRanges('ngoài hiênnhà', ['hiên']), isEmpty);
    });

    test('phân biệt hoa thường — tên riêng mới tô', () {
      expect(glossaryRanges('ngồi ngoài hiên nhà', ['Hiên']), isEmpty);
    });

    test('term DÀI thắng term ngắn, không chồng nhau', () {
      const s = 'Lâm Hiên Nhi gật đầu.';
      final r = glossaryRanges(s, ['Lâm Hiên', 'Lâm Hiên Nhi']);
      expect(r.length, 1);
      expect(s.substring(r[0].$1, r[0].$2), 'Lâm Hiên Nhi');
    });

    test('kết quả xếp theo vị trí tăng dần', () {
      const s = 'Tiêu Viêm gặp Lâm Hiên rồi gặp Tiêu Viêm lần nữa.';
      final r = glossaryRanges(s, ['Lâm Hiên', 'Tiêu Viêm']);
      expect(r.map((e) => e.$1).toList(), [for (final e in r) e.$1]..sort());
      expect(r.length, 3);
    });

    test('trần maxMarks chặn đoạn dày đặc tên', () {
      final s = List.filled(100, 'Lâm Hiên').join(' ');
      expect(glossaryRanges(s, ['Lâm Hiên'], maxMarks: 10).length, 10);
    });

    test('rỗng / term quá ngắn → không tô', () {
      expect(glossaryRanges('', ['Lâm Hiên']), isEmpty);
      expect(glossaryRanges('Lâm Hiên', ['L', ' ', '']), isEmpty);
    });
  });
}

void _termsFromSourceTests() {
  group('termsFromSource — gợi ý tên theo bản gốc chữ Trung', () {
    final terms = [
      {'term_zh': '巴拉巴拉', 'correct_vi': 'Ba Lạp Ba Lạp'},
      {'term_zh': '林轩', 'correct_vi': 'Lâm Hiên'},
      {'term_zh': '天王', 'correct_vi': 'Thiên Vương'},
      {'term_zh': '猎人', 'correct_vi': 'Liệp Nhân'},
    ];
    const zh = '巴拉巴拉说了一大堆。林轩看着天王。';

    test('tên lệch dấu/cụt âm vẫn ra đúng term (so cũ có dấu thì trơ)', () {
      final r = termsFromSource('Ba La', 'Ba La nói.', zh, terms);
      expect(r.first['correct_vi'], 'Ba Lạp Ba Lạp');
    });

    test('term không có chữ Hán trong chương → không gợi', () {
      final r = termsFromSource('Liệp', 'Liệp đến', zh, terms);
      expect(r, isEmpty);
    });

    test('bản đúng đã có trong đoạn → xếp sau tên còn thiếu', () {
      final t2 = [...terms, {'term_zh': '林贤', 'correct_vi': 'Lâm Hiền'}];
      const zh2 = '林轩和林贤。';
      // "Lâm Hiên" đã đúng trong đoạn → tên còn thiếu "Lâm Hiền" lên trước
      final r = termsFromSource('Lâm Hiên', 'Lâm Hiên và Lâm Hiên', zh2, t2);
      expect(r.map((t) => t['correct_vi']), ['Lâm Hiền', 'Lâm Hiên']);
    });

    test('chung một âm không đủ gợi (ca thật: "Thôn Thiên Nga" ra "Thương Thiên Tử")', () {
      final t2 = [
        {'term_zh': '吞天蛾', 'correct_vi': 'Thôn Thiên Nga'},
        {'term_zh': '商天子', 'correct_vi': 'Thương Thiên Tử'},
        {'term_zh': '地下黑市', 'correct_vi': 'Địa Hạ Hắc Thị'},
      ];
      const zh2 = '吞天蛾在这里，商天子去地下黑市。';
      final r = termsFromSource('Thôn Thiên Nga', 'Thôn Thiên Nga ở đây', zh2, t2);
      expect(r.map((t) => t['correct_vi']), ['Thôn Thiên Nga']);
    });

    test('âm 1 chữ cái không khớp tiền tố lỏng', () {
      expect(termsFromSource('B', 'B', zh, terms), isEmpty);
    });
  });
}

void _sourceLineTests() {
  group('sourceLineFor — câu gốc chữ Trung của khối đang chạm', () {
    const zh = '第一章\n林风笑了。\n\n他去了城主府。';
    const vi = 'Lâm Phong cười.\n\nHắn đi tới Thành Chủ Phủ. Trời đã tối.';

    test('khớp dòng theo chỉ số, nguồn thừa dòng tiêu đề vẫn khớp', () {
      expect(sourceLineFor('Lâm Phong cười.', vi, zh), '林风笑了。');
      // khối là một câu đã tách khỏi dòng dài
      expect(sourceLineFor('Hắn đi tới Thành Chủ Phủ.', vi, zh), '他去了城主府。');
    });

    test('lệch số dòng hoặc không thấy khối → null', () {
      expect(sourceLineFor('Lâm Phong cười.', vi, '林风笑了。'), isNull);
      expect(sourceLineFor('Không có câu này', vi, zh), isNull);
    });
  });
}

void _nameRunTests() {
  group('nameRunBounds — chạm tên gom trọn cụm viết hoa', () {
    (String, String) pick(String s, String word) {
      final i = s.indexOf(word);
      final (a, b) = nameRunBounds(s, i, i + word.length);
      return (s.substring(a, b), '');
    }

    test('không nuốt từ nối viết hoa đầu câu (ca thật chương 229)', () {
      expect(pick('Nếu Thôn Thiên Nga ở đây, thì', 'Thôn').$1, 'Thôn Thiên Nga');
      expect(pick('Nhưng Lâm Phong không tin.', 'Phong').$1, 'Lâm Phong');
    });

    test('họ ở đầu câu vẫn là một phần tên', () {
      expect(pick('Lâm Phong cười.', 'Phong').$1, 'Lâm Phong');
      expect(pick('Hắn gặp Trần Đại Chinh rồi.', 'Đại').$1, 'Trần Đại Chinh');
    });
  });
}
