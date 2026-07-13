import 'dart:async' show unawaited;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'data.dart';

class TtsVoice {
  final String name;
  final String locale;
  final String identifier;
  final int quality;
  final bool networkRequired;

  const TtsVoice({
    required this.name,
    required this.locale,
    this.identifier = '',
    this.quality = 0,
    this.networkRequired = false,
  });

  String get key => identifier.isNotEmpty ? identifier : '$locale|$name';

  String get qualityLabel {
    if (quality >= 500) return 'Rất cao';
    if (quality >= 400) return 'Cao';
    if (quality >= 300) return 'Tiêu chuẩn';
    if (quality >= 3) return 'Premium';
    if (quality >= 2) return 'Nâng cao';
    return 'Tiêu chuẩn';
  }

  Map<String, String> get selector => identifier.isNotEmpty
      ? {'identifier': identifier}
      : {'name': name, 'locale': locale};
}

bool isVietnameseTtsLocale(String locale) {
  final normalized = locale.toLowerCase().replaceAll('_', '-');
  return normalized == 'vi' || normalized.startsWith('vi-');
}

List<TtsVoice> sortTtsVoices(Iterable<TtsVoice> voices) {
  int score(TtsVoice voice) => voice.quality >= 100 ? voice.quality : voice.quality * 100;
  return voices.toList()
    ..sort((a, b) {
      final quality = score(b).compareTo(score(a));
      if (quality != 0) return quality;
      final offline = a.networkRequired ? 1 : 0;
      final otherOffline = b.networkRequired ? 1 : 0;
      if (offline != otherOffline) return offline.compareTo(otherOffline);
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
}

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
  List<TtsVoice> _voices = [];
  TtsVoice? _selectedVoice;
  int _at = 0; // đoạn đang/ sắp đọc
  int _gen = 0; // đổi mỗi start/stop → vòng phát cũ tự thoát
  bool _inited = false;

  /// Tốc độ đọc (0.5 = chuẩn của flutter_tts). Lưu prefs.
  double get rate => prefs.getDouble('tts_rate') ?? 0.5;
  String? get selectedVoiceKey => _selectedVoice?.key;

  Future<void> setRate(double r) async {
    await prefs.setDouble('tts_rate', r);
    await _tts.setSpeechRate(r);
  }

  Future<List<TtsVoice>> availableVoices() async {
    await _init();
    _voices = await _readVietnameseVoices();
    final selected = _chooseVoice(_voices);
    if (selected != null) {
      _selectedVoice = selected;
      await _tts.setVoice(selected.selector);
    }
    return List.unmodifiable(_voices);
  }

  Future<void> selectVoice(TtsVoice voice) async {
    await _tts.setVoice(voice.selector);
    await prefs.setString('tts_voice_key', voice.key);
    _selectedVoice = voice;
  }

  Future<void> previewVoice(TtsVoice voice) async {
    await _tts.stop();
    await selectVoice(voice);
    await _tts.setSpeechRate(rate);
    await _tts.speak('Bạn đang nghe thử giọng đọc tiếng Việt của Gác Truyện.');
  }

  TtsVoice? _chooseVoice(List<TtsVoice> voices) {
    if (voices.isEmpty) return null;
    final saved = prefs.getString('tts_voice_key');
    return voices.where((voice) => voice.key == saved).firstOrNull ?? voices.first;
  }

  Future<List<TtsVoice>> _readVietnameseVoices() async {
    try {
      final raw = List.from(await _tts.getVoices as List? ?? const []);
      return sortTtsVoices(raw.whereType<Map>().map((voice) {
        final quality = int.tryParse('${voice['quality'] ?? 0}') ?? 0;
        final network = voice['network_required'];
        return TtsVoice(
          name: '${voice['name'] ?? 'Giọng tiếng Việt'}',
          locale: '${voice['locale'] ?? ''}',
          identifier: '${voice['identifier'] ?? ''}',
          quality: quality,
          networkRequired: network == true || '$network'.toLowerCase() == 'true',
        );
      }).where((voice) => isVietnameseTtsLocale(voice.locale)));
    } catch (_) {
      return const [];
    }
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
    _voices = await _readVietnameseVoices();
    _selectedVoice = _chooseVoice(_voices);
    if (_selectedVoice != null) {
      try {
        await _tts.setVoice(_selectedVoice!.selector);
      } catch (_) {}
    } else {
      warn ??= !kIsWeb && Platform.isIOS
          ? 'Máy chưa có giọng tiếng Việt. Vào Cài đặt > Trợ năng > Nội dung được đọc '
              '> Giọng nói để tải giọng Tiếng Việt.'
          : 'Máy chưa có giọng đọc tiếng Việt. Hãy tải dữ liệu giọng Tiếng Việt '
              'trong phần Chuyển văn bản thành giọng nói của hệ thống.';
    }
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
