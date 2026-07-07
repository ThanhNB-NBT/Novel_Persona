import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'data.dart';

/// Trạng thái máy đọc — bất biến, đổi qua TtsPlayer.
class TtsState {
  final int? novelId;
  final int chapterIndex;
  final bool playing; // đang phát tiếng
  final bool paused; // dừng tạm, còn nhớ vị trí
  const TtsState(
      {this.novelId, this.chapterIndex = 0, this.playing = false, this.paused = false});
  bool get active => novelId != null;
}

/// Máy đọc chương bằng TTS hệ thống: phát tuần tự từng đoạn, hết chương tự sang
/// chương kế (nếu đã dịch). Singleton sống NGOÀI reader — rời màn đọc / tắt màn
/// hình vẫn phát tiếp (iOS cần UIBackgroundModes=audio, đã khai báo Info.plist).
/// ponytail: pause = stop + nhớ đoạn đang đọc (Android không pause được utterance).
class TtsPlayer {
  TtsPlayer._();
  static final TtsPlayer i = TtsPlayer._();

  final FlutterTts _tts = FlutterTts();
  final ValueNotifier<TtsState> state = ValueNotifier(const TtsState());

  List<String> _paras = [];
  int _at = 0; // đoạn đang/ sắp đọc
  int _gen = 0; // đổi mỗi start/stop → vòng phát cũ tự thoát
  bool _inited = false;

  /// Tốc độ đọc (0.5 = chuẩn của flutter_tts). Lưu prefs.
  double get rate => prefs.getDouble('tts_rate') ?? 0.5;

  Future<void> setRate(double r) async {
    await prefs.setDouble('tts_rate', r);
    await _tts.setSpeechRate(r);
  }

  Future<void> _init() async {
    if (_inited) return;
    _inited = true;
    await _tts.awaitSpeakCompletion(true); // speak() trả về khi ĐỌC XONG
    await _tts.setLanguage('vi-VN');
    await _tts.setSpeechRate(rate);
    // iOS: phát cả khi máy gạt im lặng + duy trì audio session nền
    await _tts.setIosAudioCategory(IosTextToSpeechAudioCategory.playback,
        [IosTextToSpeechAudioCategoryOptions.mixWithOthers]);
  }

  Future<void> start(int novelId, int chapterIndex) async {
    await _init();
    await stop();
    final gen = ++_gen;
    state.value = TtsState(novelId: novelId, chapterIndex: chapterIndex, playing: true);
    await _playLoop(gen, novelId, chapterIndex, fromPara: 0);
  }

  /// Dừng tạm — giữ vị trí để resume.
  Future<void> pause() async {
    _gen++; // vòng phát thoát sau utterance hiện tại
    await _tts.stop();
    if (state.value.active) {
      state.value = TtsState(
          novelId: state.value.novelId,
          chapterIndex: state.value.chapterIndex,
          paused: true);
    }
  }

  Future<void> resume() async {
    final s = state.value;
    if (!s.active || !s.paused) return;
    final gen = ++_gen;
    state.value = TtsState(novelId: s.novelId, chapterIndex: s.chapterIndex, playing: true);
    await _playLoop(gen, s.novelId!, s.chapterIndex, fromPara: _at, reuseParas: true);
  }

  Future<void> stop() async {
    _gen++;
    await _tts.stop();
    state.value = const TtsState();
  }

  Future<void> _playLoop(int gen, int novelId, int chapterIndex,
      {required int fromPara, bool reuseParas = false}) async {
    var index = chapterIndex;
    var from = fromPara;
    var reuse = reuseParas;
    while (gen == _gen) {
      if (!reuse) {
        final c = await sb
            .from('chapters')
            .select('title_vi, content_vi, translation_status')
            .eq('novel_id', novelId)
            .eq('chapter_index', index)
            .maybeSingle();
        if (gen != _gen) return;
        if (c == null || c['translation_status'] != 'done') {
          // hết đường (chương kế chưa dịch/không có) → dừng gọn
          await stop();
          return;
        }
        _paras = [
          if ((c['title_vi'] as String?)?.isNotEmpty == true) c['title_vi'] as String,
          ...((c['content_vi'] as String? ?? '')
              .split('\n')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)),
        ];
        from = 0;
      }
      reuse = false;
      state.value = TtsState(novelId: novelId, chapterIndex: index, playing: true);
      for (_at = from; _at < _paras.length; _at++) {
        if (gen != _gen) return;
        await _tts.speak(_paras[_at]);
      }
      if (gen != _gen) return;
      index += 1; // hết chương → đọc tiếp chương sau
    }
  }
}
