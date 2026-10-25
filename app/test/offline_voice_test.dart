import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader/offline_voice.dart';

void main() {
  final cfg = <String, dynamic>{
    'audio': {'sample_rate': 22050},
    'espeak': {'voice': 'vi'},
    'num_speakers': 1,
    'phoneme_id_map': {
      '_': [0],
      'a': [14],
    },
  };

  test('piperMeta khớp byte đã kiểm bằng onnx + sherpa trên máy tính', () {
    final b = piperMeta(cfg);
    expect(b.length, 131);
    final hex = b.take(24).map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    expect(hex, '72120a0a6d6f64656c5f7479706512047669747372100a07');
  });

  test('piperTokens: mỗi âm vị một dòng kèm id đầu tiên', () {
    expect(piperTokens(cfg), '_ 0\na 14\n');
  });

  test('mã giọng: người đọc 0 giữ mã cũ, sid khác thêm hậu tố', () {
    final csa = OfflineVoice.packs.firstWhere((p) => p.id == 'csa');
    expect(OfflineVoice.idOf(OfflineVoice.packs.first, 0), 'offline:vais1000');
    expect(OfflineVoice.idOf(csa, 2), 'offline:csa:2');
    expect(OfflineVoice.isOffline('vi-VN-language'), isFalse);
  });
}
