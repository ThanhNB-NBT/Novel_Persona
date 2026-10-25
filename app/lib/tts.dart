import 'dart:async' show unawaited;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'chapter_paras.dart';
import 'data.dart';
import 'offline_voice.dart';

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

  /// Giọng offline của các gói đã tải — đứng đầu danh sách.
  static List<TtsVoice> offlineVoices() => [
        for (final p in OfflineVoice.packs)
          if (OfflineVoice.i.installed.value.contains(p.id))
            for (final (sid, name) in p.voices)
              TtsVoice(name: name, locale: 'vi-VN', identifier: OfflineVoice.idOf(p, sid), quality: 400),
      ];
  static const _previewText = 'Bạn đang nghe thử giọng đọc tiếng Việt của Gác Truyện.';
  bool get _offline => OfflineVoice.isOffline(_selectedVoice?.key);
  double get _speed => (rate * 2).clamp(0.5, 2.0); // rate 0.5 = 1× (thang flutter_tts)
  final ValueNotifier<TtsState> state = ValueNotifier(const TtsState());

  /// Đoạn NỘI DUNG đang đọc (khớp chỉ số đoạn màn hình reader hiển thị; -1 = đang đọc
  /// tiêu đề hoặc chưa đọc). Reader nghe cái này để highlight + cuộn theo.
  final ValueNotifier<int> paraAt = ValueNotifier(-1);

  List<String> _paras = []; // gồm tiêu đề ở đầu (nếu có) rồi tới các đoạn nội dung
  int _lead = 0; // 1 nếu _paras[0] là tiêu đề → paraAt = _at - _lead
  List<TtsVoice> _voices = [];
  TtsVoice? _selectedVoice;
  int _at = 0; // đoạn đang/ sắp đọc (chỉ số trong _paras)
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
      if (!OfflineVoice.isOffline(selected.key)) await _tts.setVoice(selected.selector);
    }
    return List.unmodifiable(_voices);
  }

  Future<void> selectVoice(TtsVoice voice) async {
    if (!OfflineVoice.isOffline(voice.key)) await _tts.setVoice(voice.selector);
    await prefs.setString('tts_voice_key', voice.key);
    _selectedVoice = voice;
  }

  Future<void> previewVoice(TtsVoice voice) async {
    await _tts.stop();
    await OfflineVoice.i.stop();
    await selectVoice(voice);
    if (_offline) {
      await OfflineVoice.i.say(voice.key, _previewText, _speed);
      return;
    }
    await _tts.setSpeechRate(rate);
    await _tts.speak(_previewText);
  }

  TtsVoice? _chooseVoice(List<TtsVoice> voices) {
    final saved = prefs.getString('tts_voice_key');
    // giọng offline: khi user đã chọn, hoặc máy không có giọng Việt nào khác
    final offline = offlineVoices();
    final pick = OfflineVoice.i.ready(saved)
        ? saved
        : (voices.isEmpty ? OfflineVoice.i.firstReady() : null);
    if (pick != null) return offline.firstWhere((v) => v.key == pick);
    if (voices.isEmpty) return null;
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
    } catch (e) {
      // liệt kê giọng lỗi không phải chuyện thường — trả rỗng để _chooseVoice
      // rơi về giọng mặc định; log ra để còn biết vì sao TTS câm.
      debugPrint('TTS: không liệt kê được giọng: $e');
      return const [];
    }
  }

  /// null = ổn; chuỗi = cảnh báo cho user (thiếu giọng Việt, engine hỏng...).
  /// Trả về từ _init để reader hiện snackbar — TTS "câm" thường do máy thiếu
  /// giọng vi-VN chứ không phải code, phải nói ra chứ đừng im.
  Future<String?> _init() async {
    if (_inited) return null;
    await OfflineVoice.i.check();
    // Từng bước config bọc riêng: máy thiếu giọng vi-VN / lệnh không có trên nền
    // tảng đó thì vẫn đọc bằng giọng mặc định — đừng để chết im trước khi speak
    // (bug 2026-07-08: setIosAudioCategory gọi trên Android nổ → không ra tiếng).
    String? warn;
    try {
      await _tts.awaitSpeakCompletion(true); // speak() trả về khi ĐỌC XONG
    } catch (e) { debugPrint('TTS: bỏ qua lỗi cấu hình: $e'); }
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
          warn = 'Máy chưa có giọng đọc tiếng Việt. Tải "Giọng Gác Truyện" (offline, '
              '~20 MB) trong mục Giọng đọc, hoặc cài giọng Tiếng Việt của Google TTS.';
        }
      } catch (e) {
        warn = 'Không kiểm tra được engine TTS: $e';
      }
    }
    try {
      await _tts.setLanguage('vi-VN');
    } catch (e) { debugPrint('TTS: bỏ qua lỗi cấu hình: $e'); }
    _voices = await _readVietnameseVoices();
    _selectedVoice = _chooseVoice(_voices);
    if (_offline) {
      warn = null; // giọng offline không cần engine/giọng của máy
    } else if (_selectedVoice != null) {
      try {
        await _tts.setVoice(_selectedVoice!.selector);
      } catch (e) { debugPrint('TTS: bỏ qua lỗi cấu hình: $e'); }
    } else {
      warn ??= 'Máy chưa có giọng đọc tiếng Việt. Tải "Giọng Gác Truyện" (offline, '
          '~20 MB) trong mục Giọng đọc.';
    }
    try {
      await _tts.setSpeechRate(rate);
      await _tts.setVolume(1.0);
    } catch (e) { debugPrint('TTS: bỏ qua lỗi cấu hình: $e'); }
    if (!kIsWeb && Platform.isIOS) {
      // iOS: phát cả khi máy gạt im lặng + duy trì audio session nền
      try {
        await _tts.setIosAudioCategory(IosTextToSpeechAudioCategory.playback,
            [IosTextToSpeechAudioCategoryOptions.mixWithOthers]);
      } catch (e) { debugPrint('TTS: bỏ qua lỗi cấu hình: $e'); }
    }
    _inited = warn == null; // còn cảnh báo thì lần sau kiểm lại (user vừa cài giọng)
    return warn;
  }

  /// Bắt đầu đọc từ ĐOẠN NỘI DUNG `fromContentPara` (mặc định đầu chương). `paras` là
  /// danh sách đoạn màn reader đang hiển thị — truyền vào để highlight khớp tuyệt đối
  /// chương đang mở; chương tự-sang sau đó TTS tự phân đoạn lại. Trả cảnh báo (nếu có).
  Future<String?> start(int novelId, int chapterIndex,
      {int fromContentPara = 0, List<String>? paras, String? title}) async {
    final warn = await _init();
    await stop();
    final gen = ++_gen;
    state.value = TtsState(novelId: novelId, chapterIndex: chapterIndex, playing: true);
    unawaited(_playLoop(gen, novelId, chapterIndex,
        fromContentPara: fromContentPara, seedParas: paras, seedTitle: title));
    return warn;
  }

  /// Dừng tạm — giữ vị trí để resume.
  Future<void> pause() async {
    _gen++; // vòng phát thoát sau utterance hiện tại
    await _tts.stop();
    await OfflineVoice.i.stop();
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
    // resume: _paras/_lead còn nguyên, tiếp từ _at (chỉ số trong _paras)
    await _playLoop(gen, s.novelId!, s.chapterIndex, resumeAt: _at);
  }

  /// Xoá gói giọng; đang đọc/chọn giọng của gói đó thì dừng + bỏ chọn (lần sau tự chọn lại).
  Future<void> dropPack(VoicePack p) async {
    final key = _selectedVoice?.key ?? '';
    if (key == OfflineVoice.idOf(p, 0) || key.startsWith('offline:${p.id}:')) {
      await stop();
      _selectedVoice = null;
      _inited = false;
      await prefs.remove('tts_voice_key');
    }
    await OfflineVoice.i.delete(p);
  }

  Future<void> stop() async {
    _gen++;
    await _tts.stop();
    await OfflineVoice.i.stop();
    paraAt.value = -1;
    state.value = const TtsState();
  }

  /// Vòng phát. `resumeAt` (chỉ số _paras) != null = tiếp bản đang có, không tải lại;
  /// ngược lại tải chương + phân đoạn, bắt đầu từ đoạn nội dung `fromContentPara`.
  /// `seedParas`/`seedTitle` (nếu có) = danh sách reader truyền cho chương ĐẦU để khớp.
  Future<void> _playLoop(int gen, int novelId, int chapterIndex,
      {int fromContentPara = 0,
      int? resumeAt,
      List<String>? seedParas,
      String? seedTitle}) async {
    var index = chapterIndex;
    var contentFrom = fromContentPara;
    var seedP = seedParas;
    var seedT = seedTitle;
    var startAt = resumeAt; // != null ở lần lặp đầu khi resume
    while (gen == _gen) {
      if (startAt == null) {
        List<String> content;
        String? title;
        if (seedP != null) {
          content = seedP; // reader đã phân đoạn sẵn cho chương đang mở → khớp tuyệt đối
          title = seedT;
          seedP = null;
          seedT = null;
        } else {
          final c = await sb
              .from('chapters')
              .select('title_vi, content_vi, translation_status')
              .eq('novel_id', novelId)
              .eq('chapter_index', index)
              .maybeSingle();
          if (gen != _gen) return;
          if (c == null || c['translation_status'] != 'done') {
            await stop(); // hết đường (chương kế chưa dịch) → dừng gọn
            return;
          }
          title = (c['title_vi'] as String?)?.trim();
          content = contentParagraphs(c['content_vi'] as String? ?? '');
        }
        _lead = (title != null && title.isNotEmpty) ? 1 : 0;
        _paras = [if (_lead == 1) title!, ...content];
        startAt = contentFrom.clamp(0, content.length) + _lead;
        contentFrom = 0; // chỉ chương đầu tôn trọng vị trí bắt đầu
      }
      state.value = TtsState(novelId: novelId, chapterIndex: index, playing: true);
      for (_at = startAt; _at < _paras.length; _at++) {
        if (gen != _gen) return;
        paraAt.value = _at - _lead; // đọc tiêu đề → -1; đoạn nội dung → khớp reader
        try {
          final text = halfWidthBrackets(_paras[_at]); // khối gốc → đọc như chữ hiển thị
          if (_offline) {
            final next = _at + 1 < _paras.length ? halfWidthBrackets(_paras[_at + 1]) : null;
            if (!await _sayOffline(gen, text, next)) throw Exception('giọng offline lỗi');
          } else {
            // flutter_tts: 1 = ok, 0 = engine từ chối (thiếu giọng/engine chết)
            final r = await _tts.speak(text);
            if (r == 0) throw Exception('engine từ chối đọc');
          }
        } catch (_) {
          await stop(); // engine TTS lỗi giữa chừng → tắt gọn thay vì kẹt im
          return;
        }
      }
      if (gen != _gen) return;
      paraAt.value = -1;
      startAt = null; // chương sau: tải lại + phân đoạn
      index += 1; // hết chương → đọc tiếp chương sau
    }
  }

  /// Offline sinh xong cả khối mới phát → cắt khối ngắn cho đỡ chờ, sinh trước khối kế
  /// (kể cả khối đầu đoạn sau) trong lúc khối này đang phát.
  Future<bool> _sayOffline(int gen, String text, String? nextPara) async {
    final cs = ttsChunks(text);
    for (var k = 0; k < cs.length; k++) {
      if (gen != _gen) return true;
      final next = k + 1 < cs.length ? cs[k + 1] : (nextPara == null ? null : ttsChunks(nextPara).first);
      final id = _selectedVoice!.key;
      if (next != null) OfflineVoice.i.prefetch(id, next, _speed);
      if (!await OfflineVoice.i.say(id, cs[k], _speed)) return false;
    }
    return true;
  }
}

/// Cắt chuỗi dài thành khối ≤ [max] ký tự, ưu tiên cắt sau dấu câu.
List<String> ttsChunks(String s, {int max = 300}) {
  final out = <String>[];
  var rest = s;
  while (rest.length > max) {
    final head = rest.substring(0, max);
    var cut = -1;
    for (final p in const ['.', '!', '?', '…', '”', ';', ',']) {
      final i = head.lastIndexOf(p);
      if (i > cut) cut = i;
    }
    if (cut < max ~/ 2) cut = max - 1;
    out.add(rest.substring(0, cut + 1));
    rest = rest.substring(cut + 1);
  }
  if (rest.trim().isNotEmpty || out.isEmpty) out.add(rest);
  return out;
}
