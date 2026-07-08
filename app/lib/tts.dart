import 'dart:async' show unawaited;
import 'dart:io' show Platform;

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

  /// null = ổn; chuỗi = cảnh báo cho user (thiếu giọng Việt, engine hỏng...).
  /// Trả về từ _init để reader hiện snackbar — TTS "câm" thường do máy thiếu
  /// giọng vi-VN chứ không phải code, phải nói ra chứ đừng im.
  Future<String?> _init() async {
    if (_inited) return null;
    // Từng bước config bọc riêng: máy thiếu giọng vi-VN / lệnh không có trên nền
    // tảng đó thì vẫn đọc bằng giọng mặc định — đừng để chết im trước khi speak
    // (bug 2026-07-08: setIosAudioCategory gọi trên Android nổ → không ra tiếng).
    String? warn;
    try {
      await _tts.awaitSpeakCompletion(true); // speak() trả về khi ĐỌC XONG
    } catch (_) {}
    if (!kIsWeb && Platform.isAndroid) {
      // Máy Android hay câm vì: engine mặc định (Samsung TTS...) không có giọng
      // tiếng Việt. Thử engine hiện tại → không có vi thì ép sang Google TTS →
      // vẫn không có thì báo user cài giọng Việt.
      try {
        var ok = await _tts.isLanguageAvailable('vi-VN') == true;
        if (!ok) {
          final engines = List.from(await _tts.getEngines as List? ?? const []);
          if (engines.contains('com.google.android.tts')) {
            await _tts.setEngine('com.google.android.tts');
            ok = await _tts.isLanguageAvailable('vi-VN') == true;
          }
        }
        if (!ok) {
          warn = 'Máy chưa có giọng đọc tiếng Việt. Cài "Giọng nói Google" '
              '(Google TTS) rồi tải dữ liệu giọng Tiếng Việt trong '
              'Cài đặt > Trợ năng > Chuyển văn bản thành giọng nói.';
        }
      } catch (e) {
        warn = 'Không kiểm tra được engine TTS: $e';
      }
    }
    try {
      await _tts.setLanguage('vi-VN');
    } catch (_) {}
    try {
      await _tts.setSpeechRate(rate);
      await _tts.setVolume(1.0);
    } catch (_) {}
    if (!kIsWeb && Platform.isIOS) {
      // iOS: phát cả khi máy gạt im lặng + duy trì audio session nền
      try {
        await _tts.setIosAudioCategory(IosTextToSpeechAudioCategory.playback,
            [IosTextToSpeechAudioCategoryOptions.mixWithOthers]);
      } catch (_) {}
    }
    _inited = warn == null; // còn cảnh báo thì lần sau kiểm lại (user vừa cài giọng)
    return warn;
  }

  /// Bắt đầu đọc; trả về cảnh báo (nếu có) để UI hiện — vẫn thử phát bằng
  /// giọng mặc định chứ không chặn.
  Future<String?> start(int novelId, int chapterIndex) async {
    final warn = await _init();
    await stop();
    final gen = ++_gen;
    state.value = TtsState(novelId: novelId, chapterIndex: chapterIndex, playing: true);
    unawaited(_playLoop(gen, novelId, chapterIndex, fromPara: 0));
    return warn;
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
        try {
          // flutter_tts: 1 = ok, 0 = engine từ chối (thiếu giọng/engine chết)
          final r = await _tts.speak(_paras[_at]);
          if (r == 0) throw Exception('engine từ chối đọc');
        } catch (_) {
          await stop(); // engine TTS lỗi giữa chừng → tắt gọn thay vì kẹt im
          return;
        }
      }
      if (gen != _gen) return;
      index += 1; // hết chương → đọc tiếp chương sau
    }
  }
}
