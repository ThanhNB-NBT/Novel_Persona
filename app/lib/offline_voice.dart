import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart' show extractFileToDisk;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as so;

/// Một gói giọng Piper tải về máy: một file .onnx (+ .onnx.json), có thể nhiều người đọc.
class VoicePack {
  final String id;
  final String title;
  final int sizeMb;
  final String onnx;
  final List<(int, String)> voices; // (sid, tên hiển thị)
  const VoicePack(this.id, this.title, this.sizeMb, this.onnx, this.voices);
}

const _hf = 'https://huggingface.co';
const _espeakUrl =
    'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/espeak-ng-data.zip';

/// Giọng Việt offline (Piper chạy bằng sherpa-onnx ngay trên máy) — không cần mạng, không
/// cần giọng hệ thống. Mỗi gói tải một lần từ nguồn gốc (.onnx Piper + .json); máy tự chuyển
/// sang dạng sherpa đọc được: sinh tokens.txt từ json + nối metadata vào cuối file onnx.
/// Bộ phát âm espeak-ng-data dùng chung mọi gói. Ghim sherpa_onnx 1.13.8: bản 2.0 bỏ espeak-ng.
/// Model sống trong một isolate riêng (generate() là FFI đồng bộ, chạy ở UI là giật);
/// isolate ghi WAV ra file tạm, audioplayers phát file đó.
class OfflineVoice {
  OfflineVoice._();
  static final OfflineVoice i = OfflineVoice._();

  static const packs = [
    VoicePack('vais1000', 'Giọng Gác Truyện', 64,
        '$_hf/rhasspy/piper-voices/resolve/main/vi/vi_VN/vais1000/medium/vi_VN-vais1000-medium.onnx',
        [(0, 'Gác Truyện (nữ)')]),
    VoicePack('csa', 'Bộ 5 giọng CSA', 74,
        '$_hf/CakeByVPBank/piper-pgl-v4-vi_VN-version39_epoch39/resolve/main/vi_VN-csa-voice-piper-v3-medium.onnx',
        [(0, 'Ngọc Lan (nữ)'), (1, 'Minh Anh (nữ)'), (2, 'Quang Huy (nam)'), (3, 'Thu Hà (nữ)'), (4, 'Yến Nhi (nữ)')]),
  ];

  /// Mã giọng: `offline:<gói>` (người đọc 0) hoặc `offline:<gói>:<sid>`. Giữ "offline:vais1000" như bản trước.
  static String idOf(VoicePack p, int sid) => sid == 0 ? 'offline:${p.id}' : 'offline:${p.id}:$sid';
  static bool isOffline(String? id) => id?.startsWith('offline:') == true;
  static (VoicePack, int)? _parse(String id) {
    final p = id.substring('offline:'.length).split(':');
    final pack = packs.where((x) => x.id == p[0]).firstOrNull;
    return pack == null ? null : (pack, int.tryParse(p.length > 1 ? p[1] : '') ?? 0);
  }

  bool ready(String? id) => id != null && installed.value.contains(_parse(id)?.$1.id);
  String? firstReady() => packs.where((p) => installed.value.contains(p.id)).map((p) => idOf(p, 0)).firstOrNull;

  final ValueNotifier<Set<String>> installed = ValueNotifier(const {});
  /// Gói đang tải (null = không) + tiến độ 0..1.
  final ValueNotifier<String?> downloading = ValueNotifier(null);
  final ValueNotifier<double> progress = ValueNotifier(0);
  String? error;

  final AudioPlayer _player = AudioPlayer();
  Completer<bool>? _playing;
  int _epoch = 0; // đổi mỗi stop() → khối đang sinh dở không được phát nữa
  SendPort? _worker;
  final _replies = <int, Completer<String?>>{};
  int _seq = 0;

  /// Khối đã/đang sinh, chờ đến lượt phát (khối hiện tại + khối kế).
  final _pending = <String, Future<String?>>{};

  Future<String> _root() async => '${(await getApplicationSupportDirectory()).path}/tts';
  Future<String> _espeak() async => '${await _root()}/espeak-ng-data';
  Future<String> _dir(VoicePack p) async => '${await _root()}/${p.id}';
  // chỉ ghi khi xong trọn → không dùng nhầm gói dở
  Future<File> _ok(VoicePack p) async => File('${await _dir(p)}/.ok');

  Future<void> check() async {
    // gói int8 bản trước: kém hay + chậm hơn
    final legacy = Directory('${await _root()}/vits-piper-vi_VN-vais1000-medium-int8');
    if (await legacy.exists()) await legacy.delete(recursive: true);
    installed.value = {
      for (final p in packs)
        if (await (await _ok(p)).exists()) p.id,
    };
  }

  /// Tải + chuyển gói. null = xong; chuỗi = lỗi cho user.
  Future<String?> download(VoicePack p) async {
    if (downloading.value != null) return null;
    downloading.value = p.id;
    progress.value = 0;
    error = null;
    final tmp = Directory('${await _root()}/tmp-${p.id}');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    Future<HttpClientResponse> get(String url) async {
      final res = await (await client.getUrl(Uri.parse(url))).close();
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      return res;
    }

    try {
      if (await tmp.exists()) await tmp.delete(recursive: true);
      await tmp.create(recursive: true);
      final espeak = await _espeak();
      if (!await File('$espeak/phontab').exists()) {
        final zip = File('${tmp.path}/espeak.zip');
        await (await get(_espeakUrl)).timeout(const Duration(seconds: 30)).pipe(zip.openWrite());
        // compute + hàm top-level: closure trong method kéo theo `this` (AudioPlayer không gửi qua isolate được)
        await compute(_extract, [zip.path, tmp.path]);
        final old = Directory(espeak);
        if (await old.exists()) await old.delete(recursive: true);
        await Directory('${tmp.path}/espeak-ng-data').rename(espeak);
      }
      final cfg = jsonDecode(await utf8.decodeStream(await get('${p.onnx}.json'))) as Map<String, dynamic>;
      await File('${tmp.path}/tokens.txt').writeAsString(piperTokens(cfg));
      final model = File('${tmp.path}/model.onnx');
      final total = p.sizeMb * 1048576;
      var got = 0;
      await (await get(p.onnx)).timeout(const Duration(seconds: 30)).map((b) {
        got += b.length;
        final v = (got / total).clamp(0.0, 0.99);
        if (v - progress.value >= 0.01) progress.value = v; // mỗi 1% vẽ lại một lần, không phải mỗi 64 KB
        return b;
      }).pipe(model.openWrite());
      await model.writeAsBytes(piperMeta(cfg), mode: FileMode.append, flush: true);
      final zip = File('${tmp.path}/espeak.zip');
      if (await zip.exists()) await zip.delete();
      final dir = Directory(await _dir(p));
      if (await dir.exists()) await dir.delete(recursive: true);
      await tmp.rename(dir.path);
      await (await _ok(p)).writeAsString('1');
      installed.value = {...installed.value, p.id};
      return null;
    } catch (e) {
      return error = 'Tải lỗi: $e';
    } finally {
      client.close();
      if (await tmp.exists()) await tmp.delete(recursive: true);
      downloading.value = null;
    }
  }

  /// Xoá gói khỏi máy; hết gói thì xoá luôn bộ phát âm dùng chung. Gọi khi gói không đang đọc.
  Future<void> delete(VoicePack p) async {
    final dir = await _dir(p);
    _worker?.send([-1, dir]); // isolate nhả model khỏi RAM
    _pending.clear();
    installed.value = {...installed.value}..remove(p.id);
    final d = Directory(dir);
    if (await d.exists()) await d.delete(recursive: true);
    if (installed.value.isEmpty) {
      final e = Directory(await _espeak());
      if (await e.exists()) await e.delete(recursive: true);
    }
  }

  Future<SendPort> _spawn() async {
    if (_worker != null) return _worker!;
    final wavDir = (await getTemporaryDirectory()).path;
    final inbox = ReceivePort();
    final errors = ReceivePort();
    final first = Completer<SendPort>();
    // isolate chết (model hỏng, thiếu .so cho kiến trúc máy) → báo lỗi thay vì treo im
    errors.listen((e) {
      debugPrint('OfflineVoice: worker lỗi: $e');
      _worker = null;
      if (!first.isCompleted) first.completeError(StateError('$e'));
      for (final c in _replies.values) {
        c.complete(null);
      }
      _replies.clear();
      _pending.clear();
      inbox.close();
      errors.close();
    });
    inbox.listen((m) {
      if (m is SendPort) {
        first.complete(m);
      } else if (m is List) {
        _replies.remove(m[0] as int)?.complete(m[1] as String?);
      }
    });
    await Isolate.spawn(_workerMain, [inbox.sendPort, wavDir],
        onError: errors.sendPort, onExit: errors.sendPort);
    // iOS: phát cả khi gạt im lặng (UIBackgroundModes=audio đã khai cho flutter_tts)
    await _player.setAudioContext(AudioContextConfig(respectSilence: false).build());
    return _worker = await first.future;
  }

  Future<String?> _synth(String id, String text, double speed) =>
      _pending.putIfAbsent('$id|$speed|$text', () {
        // bỏ khối cũ khi nhảy đoạn/đổi giọng/tốc độ
        while (_pending.length >= 3) {
          _pending.remove(_pending.keys.first);
        }
        final v = _parse(id);
        if (v == null) return Future.value(null);
        return Future.wait([_spawn(), _dir(v.$1), _espeak()]).then((r) {
          final n = ++_seq;
          final c = _replies[n] = Completer<String?>();
          (r[0] as SendPort).send([n, r[1], r[2], v.$2, text, speed]);
          return c.future;
        }, onError: (_) => null);
      });

  /// Sinh trước câu sắp đọc trong lúc câu này đang phát → không hở giữa các đoạn.
  void prefetch(String id, String text, double speed) => unawaited(_synth(id, text, speed));

  /// Đọc [text] tới hết. true = xong (hoặc bị stop()); false = engine lỗi.
  Future<bool> say(String id, String text, double speed) async {
    final epoch = _epoch;
    final wav = await _synth(id, text, speed);
    _pending.remove('$id|$speed|$text');
    if (wav == null) return false;
    if (wav.isEmpty || epoch != _epoch) return true; // chỉ dấu câu, hoặc đã stop() lúc đang sinh
    final done = _playing = Completer<bool>();
    final sub = _player.onPlayerComplete.listen((_) {
      if (!done.isCompleted) done.complete(true);
    });
    try {
      await _player.play(DeviceFileSource(wav));
      return await done.future;
    } finally {
      await sub.cancel();
      unawaited(File(wav).delete().then((_) {}, onError: (_) {}));
    }
  }

  Future<void> stop() async {
    _epoch++;
    if (_playing?.isCompleted == false) _playing!.complete(true);
    _playing = null;
    await _player.stop();
  }
}

/// tokens.txt của sherpa: mỗi dòng `<âm vị> <id>` lấy từ phoneme_id_map của Piper.
String piperTokens(Map<String, dynamic> cfg) => (cfg['phoneme_id_map'] as Map)
    .entries
    .map((e) => '${e.key} ${(e.value as List).first}\n')
    .join();

/// Metadata sherpa cần cho Piper, mã hoá thành trường 14 (metadata_props) của ModelProto.
/// Protobuf gộp trường lặp nối ở cuối → chỉ việc append vào file onnx gốc, không cần thư viện onnx.
Uint8List piperMeta(Map<String, dynamic> cfg) {
  List<int> varint(int n) => [
        for (; n >= 0x80; n >>= 7) (n & 0x7F) | 0x80,
        n,
      ];
  List<int> field(int tag, List<int> data) => [...varint(tag), ...varint(data.length), ...data];
  final meta = {
    'model_type': 'vits',
    'comment': 'piper',
    'language': 'Vietnamese',
    'voice': '${(cfg['espeak'] as Map)['voice']}',
    'has_espeak': '1',
    'n_speakers': '${cfg['num_speakers']}',
    'sample_rate': '${(cfg['audio'] as Map)['sample_rate']}',
  };
  return Uint8List.fromList([
    for (final e in meta.entries)
      ...field(0x72, [...field(0x0A, utf8.encode(e.key)), ...field(0x12, utf8.encode(e.value))]),
  ]);
}

/// Giải nén theo luồng; extractFileToDisk tự chặn đường dẫn lọt ra ngoài, trần 50 MB chặn "bom nén".
Future<void> _extract(List<String> a) => extractFileToDisk(a[0], a[1], maxSize: 50 << 20);

/// Isolate sinh tiếng: nhận [id, modelDir, espeakDir, sid, text, speed] → trả [id, wav | '' | null];
/// [-1, modelDir] = nhả model đó (gói vừa bị xoá). Giữ một model trong RAM (mỗi gói ~70 MB).
void _workerMain(List args) {
  final out = args[0] as SendPort;
  final wavDir = args[1] as String;
  so.initBindings();
  so.OfflineTts? tts;
  String? loaded;
  final inbox = ReceivePort();
  out.send(inbox.sendPort);
  inbox.listen((m) {
    final req = m as List;
    final n = req[0] as int;
    final dir = req[1] as String;
    if (n == -1) {
      if (loaded == dir) {
        tts?.free();
        tts = null;
        loaded = null;
      }
      return;
    }
    try {
      if (loaded != dir) {
        tts?.free();
        tts = so.OfflineTts(so.OfflineTtsConfig(
          model: so.OfflineTtsModelConfig(
            vits: so.OfflineTtsVitsModelConfig(
                model: '$dir/model.onnx', tokens: '$dir/tokens.txt', dataDir: req[2] as String),
            numThreads: 2,
          ),
        ));
        loaded = dir;
      }
      final a = tts!.generate(text: req[4] as String, sid: req[3] as int, speed: req[5] as double);
      if (a.samples.isEmpty) return out.send([n, '']);
      final path = '$wavDir/ov_$n.wav';
      final ok = so.writeWave(filename: path, samples: a.samples, sampleRate: a.sampleRate);
      out.send([n, ok ? path : null]);
    } catch (_) {
      out.send([n, null]);
    }
  });
}
