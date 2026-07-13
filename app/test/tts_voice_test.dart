import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/tts.dart';

void main() {
  test('lọc locale Việt và ưu tiên voice chất lượng cao', () {
    expect(isVietnameseTtsLocale('vi-VN'), isTrue);
    expect(isVietnameseTtsLocale('vi_VN'), isTrue);
    expect(isVietnameseTtsLocale('en-US'), isFalse);

    final voices = sortTtsVoices(const [
      TtsVoice(name: 'Mặc định', locale: 'vi-VN', quality: 1),
      TtsVoice(name: 'Nâng cao online', locale: 'vi-VN', quality: 2, networkRequired: true),
      TtsVoice(name: 'Nâng cao offline', locale: 'vi-VN', quality: 2),
    ]);

    expect(voices.map((voice) => voice.name), [
      'Nâng cao offline',
      'Nâng cao online',
      'Mặc định',
    ]);
  });
}
