import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'painters_aura.dart';
import 'painters_fx.dart';
import 'pixel.dart';

// Cảnh nhân vật động + các widget preview cho render test — tách khỏi
// cultivation.dart (màn hình chỉ import file này, không vòng phụ thuộc).

String cultivatorAsset(String? race, String? gender) {
  final raceKey = switch (race) {
    'yeu' => 'fox',
    'ma' => 'demon',
    'linh' => 'spirit',
    _ => 'human',
  };
  final genderKey = gender == 'nu' ? 'female' : 'male';
  // CHỈ webp được bundle trong pubspec (png là file gốc, không ship)
  return 'assets/cultivators/${raceKey}_$genderKey.webp';
}

/// Bóng tiên nhân động: lơ lửng lên xuống, quầng thở, hiệu ứng bay theo công pháp.
/// Cảnh TIẾN HÓA theo cảnh giới: trăng to dần, đá → đài sen → kiếm bay,
/// sao trời hiện từ Hóa Thần, nhị nguyệt luân từ Đại Thừa. Lặp 4 giây.
class AnimatedCultivator extends StatefulWidget {
  final int realm; // 1..9
  final String? cpCode; // code công pháp đang tu → kiểu hiệu ứng
  final String? cpElem; // hệ công pháp — nguồn màu chính
  final String? element; // hệ linh căn — fallback màu khi công pháp vô hệ
  final String? race; // dáng nhân vật theo chủng tộc
  final String? gender; // nam/nu — dáng + kiểu tóc
  final String? halo; // kiểu vòng sáng sau đầu (từ pháp bảo vòng)
  final String? weaponSprite; // vũ khí đang đeo bay quanh (null = không)
  final String? phapbaoSprite; // pháp bảo đang đeo bay quanh, lệch pha nửa vòng
  final int tienTier; // bậc tiên hậu phi thăng (0..6); -1 = chưa phi thăng, không hào quang
  final List<String> elements; // bộ hệ linh căn cố định → sương linh khí ngũ sắc quanh người
  final String? haloWorn; // mã trận pháp đang đội (hậu phi thăng) → vòng lớn xoay sau lưng
  const AnimatedCultivator({
    super.key,
    required this.realm,
    this.cpCode,
    this.cpElem,
    this.element,
    this.race,
    this.gender,
    this.halo,
    this.weaponSprite,
    this.phapbaoSprite,
    this.tienTier = -1,
    this.elements = const [],
    this.haloWorn,
  });
  @override
  State<AnimatedCultivator> createState() => _AnimatedCultivatorState();
}

class _AnimatedCultivatorState extends State<AnimatedCultivator>
    with SingleTickerProviderStateMixin {
  int _elementTurn = 0;
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        // Linh khí dùng thời gian tích luỹ để các tần số vô tỉ không bị reset sau 4s.
        _elementTurn++;
        _ctrl.forward(from: 0);
      }
    })
    ..forward();
  ui.Image? _weaponImg; // icon webp của vũ khí đang đeo, decode 1 lần
  ui.Image? _phapbaoImg; // icon pháp bảo đang đeo — bay lệch pha nửa vòng
  ui.Image? _swordWheelImg; // kiếm luân minh họa, xoay sau đầu
  ui.Image? _haloImg; // trận pháp đang đội — vòng lớn xoay sau lưng
  // Frame idle phụ (tóc/áo lay, chớp mắt) nếu có trong bundle: đặt cạnh ảnh
  // gốc với hậu tố _f2.._f4 (vd human_male_f2.webp) là TỰ NHẬN, không cần
  // sửa code. Chưa có frame phụ → danh sách 1 phần tử, hành vi như ảnh tĩnh.
  List<String> _frames = const [];

  @override
  void initState() {
    super.initState();
    _loadIcons();
    _loadFrames();
  }

  @override
  void didUpdateWidget(covariant AnimatedCultivator old) {
    super.didUpdateWidget(old);
    if (old.weaponSprite != widget.weaponSprite ||
        old.phapbaoSprite != widget.phapbaoSprite ||
        old.haloWorn != widget.haloWorn) {
      _loadIcons();
    }
    if (old.race != widget.race || old.gender != widget.gender) _loadFrames();
  }

  Future<void> _loadFrames() async {
    final base = cultivatorAsset(widget.race, widget.gender);
    final found = [base];
    for (var i = 2; i <= 4; i++) {
      final p = base.replaceFirst('.webp', '_f$i.webp');
      try {
        await rootBundle.load(p); // chỉ dò tồn tại — decode để Image.asset lo
        found.add(p);
      } catch (_) {
        break; // frame phải liền số: thiếu _f2 thì khỏi dò _f3
      }
    }
    if (mounted) setState(() => _frames = found);
  }

  /// Painter không tự decode asset được → decode ở đây rồi truyền ui.Image vào.
  Future<void> _loadIcons() async {
    // decode SONG SONG — tuần tự sẽ dồn trễ, khung hình đầu thiếu đồ bay
    final imgs = await Future.wait([
      _decodeItem(widget.weaponSprite),
      _decodeItem(widget.phapbaoSprite),
      _decodeAsset('assets/cult_fx/sword_wheel.webp'),
      widget.haloWorn == null
          ? Future.value(null)
          : _decodeAsset('assets/cult_halo/${widget.haloWorn}.webp'),
    ]);
    if (!mounted) {
      for (final im in imgs) {
        im?.dispose();
      }
      return;
    }
    _disposeImages(); // giải phóng bộ ảnh cũ trước khi thay bộ mới
    setState(() {
      _weaponImg = imgs[0];
      _phapbaoImg = imgs[1];
      _swordWheelImg = imgs[2];
      _haloImg = imgs[3];
    });
  }

  void _disposeImages() {
    _weaponImg?.dispose();
    _phapbaoImg?.dispose();
    _swordWheelImg?.dispose();
    _haloImg?.dispose();
    _weaponImg = null;
    _phapbaoImg = null;
    _swordWheelImg = null;
    _haloImg = null;
  }

  Future<ui.Image?> _decodeItem(String? key) async {
    if (key == null) return null;
    try {
      final data = await rootBundle.load(
        'assets/cult_items/${key == 'gourd_big' ? 'gourd' : key}.webp',
      );
      return await decodeImageFromList(data.buffer.asUint8List());
    } catch (_) {
      return null; // thiếu asset thì thôi, không vẽ món đó
    }
  }

  Future<ui.Image?> _decodeAsset(String path) async {
    try {
      final data = await rootBundle.load(path);
      return await decodeImageFromList(data.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _disposeImages();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (style, elem) = auraFor(
      widget.cpCode,
      widget.cpElem,
      widget.element,
    );
    final grade = (widget.realm + 1) ~/ 2;
    // Nền màn hình cũng nhuộm gradeColor → vòng/trận cùng màu gốc sẽ chìm.
    // Tách tông theo chế độ nền: tối → đẩy vòng SÁNG lên (pha trắng), sáng →
    // dìm vòng ĐẬM xuống (pha đen) — vẫn giữ "họ màu" cảnh giới, chỉ lệch bậc.
    final dark = Theme.of(context).brightness == Brightness.dark;
    final moon = Color.lerp(
      gradeColor(grade),
      dark ? Colors.white : Colors.black,
      dark ? 0.45 : 0.25,
    )!;
    final color = elem ?? moon;
    return SizedBox(
      width: 150,
      height: 145,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, _) => CustomPaint(
          // nền: halo sau đầu + trận pháp dưới chân + sương + quầng thở
          // nền nhận cả đồ bay quanh: nửa vòng SAU vẽ ở đây → bị người che thật
          painter: SkyPainter(
            _ctrl.value,
            moon,
            color,
            widget.realm,
            halo: widget.halo,
            weaponImg: _weaponImg,
            phapbaoImg: _phapbaoImg,
            swordWheelImg: _swordWheelImg,
            tienTier: widget.tienTier,
            elements: widget.elements,
            haloImg: _haloImg,
            elementTime: _elementTurn + _ctrl.value,
          ),
          // trước: hiệu ứng công pháp + nửa vòng TRƯỚC của vũ khí/pháp bảo
          foregroundPainter: AuraPainter(
            _ctrl.value,
            color,
            style,
            weaponImg: _weaponImg,
            phapbaoImg: _phapbaoImg,
          ),
          child: Center(
            // Ảnh chibi 1 tấm không có layer riêng → giả chuyển động bằng
            // 4 tín hiệu chồng nhau (mọi tần số là bội NGUYÊN của loop 4s):
            // trôi Lissajous, xoay quanh trục Y có phối cảnh (2.5D), nghiêng
            // Z nhẹ, và THỞ neo ở chân (giãn dọc, bụng phập phồng) thay vì
            // phóng đều cả ảnh. Bóng dưới chân bên SkyPainter co giãn ngược
            // pha [bob] để bán cảm giác lơ lửng.
            child: Builder(
              builder: (_) {
                final ph = _ctrl.value * 2 * math.pi;
                final bob = math.sin(ph); // -1..1, cùng pha bóng dưới chân
                final breath = math.sin(ph * 2); // thở 2 nhịp mỗi vòng
                // có frame phụ → chạy ping-pong 1..n..1 (8 bước/vòng ≈ 2fps),
                // gaplessPlayback giữ frame cũ khi decode nên không nháy trắng
                final n = _frames.length;
                final asset = n <= 1
                    ? cultivatorAsset(widget.race, widget.gender)
                    : () {
                        final step = (_ctrl.value * 8).floor() % (2 * n - 2);
                        return _frames[step < n ? step : 2 * n - 2 - step];
                      }();
                return Transform.translate(
                  offset: Offset(
                    bob * 1.5 + math.sin(ph * 2 + 0.9) * 0.7, // trôi lệch nhịp
                    10 + bob * 4,
                  ),
                  child: Transform(
                    alignment: Alignment.bottomCenter,
                    transform: Matrix4.identity()
                      ..setEntry(
                        3,
                        2,
                        0.0015,
                      ) // phối cảnh cho rotateY có chiều sâu
                      ..rotateY(math.sin(ph + 1.1) * 0.07) // khẽ xoay người
                      ..rotateZ(bob * 0.012)
                      ..scaleByDouble(
                        1.0 - breath * 0.006,
                        1.0 + breath * 0.011,
                        1.0,
                        1.0,
                      ),
                    child: Image.asset(
                      asset,
                      width: 104,
                      height: 128,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Bản public của nhân vật động — cho test render soi hình + có thể tái dùng nơi khác.
class CultivatorPreview extends StatelessWidget {
  final int realm;
  final String? cpCode;
  final String? cpElem; // hệ của công pháp (effect.element từ server)
  final String? element; // hệ LINH CĂN người chơi — fallback màu trận pháp
  final String? race;
  final String? gender;
  final String? halo; // kiểu vòng sáng (pháp bảo vòng đang đeo)
  final String? weaponSprite; // key icon vũ khí đang đeo (assets/cult_items)
  final String? phapbaoSprite; // key icon pháp bảo đang đeo — bay đối xứng
  final int tienTier; // bậc tiên hậu phi thăng (0..6); -1 = chưa phi thăng
  final List<String> elements; // bộ hệ linh căn → sương ngũ sắc
  final String? haloWorn; // mã trận pháp đang đội
  const CultivatorPreview({
    super.key,
    required this.realm,
    this.cpCode,
    this.cpElem,
    this.element,
    this.race,
    this.gender,
    this.halo,
    this.weaponSprite,
    this.phapbaoSprite,
    this.tienTier = -1,
    this.elements = const [],
    this.haloWorn,
  });
  @override
  Widget build(BuildContext context) => AnimatedCultivator(
    realm: realm,
    cpCode: cpCode,
    cpElem: cpElem,
    element: element,
    race: race,
    gender: gender,
    halo: halo,
    weaponSprite: weaponSprite,
    phapbaoSprite: phapbaoSprite,
    tienTier: tienTier,
    elements: elements,
    haloWorn: haloWorn,
  );
}

/// Preview TĨNH 1 frame hiệu ứng đột phá tại thời điểm [t] (0..1) — cho render
/// test soi filmstrip khi sửa BurstPainter (docs/tu-tien.md §3, bước soi PNG).
class BurstPreview extends StatelessWidget {
  final double t;
  final Color color;
  final bool ok;
  final bool loi;
  final bool major;
  const BurstPreview({
    super.key,
    required this.t,
    required this.color,
    this.ok = true,
    this.loi = false,
    this.major = false,
  });
  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: BurstPainter(t, color, ok, loi, major: major),
    child: const SizedBox.expand(),
  );
}

/// Asset kiếp lôi động dùng chung giữa dialog thật và render test trên khung điện thoại.
class TribulationPreview extends StatefulWidget {
  const TribulationPreview({super.key});

  @override
  State<TribulationPreview> createState() => _TribulationPreviewState();
}

class _TribulationPreviewState extends State<TribulationPreview> {
  MemoryImage? _img;

  @override
  void initState() {
    super.initState();
    rootBundle.load('assets/cult_fx/tribulation_sequence.webp').then((data) {
      if (!mounted) return;
      // Copy byte để MemoryImage có identity mới: mỗi lần đột phá luôn phát lại từ frame 0.
      setState(
        () => _img = MemoryImage(Uint8List.fromList(data.buffer.asUint8List())),
      );
    });
  }

  @override
  void dispose() {
    // identity mới mỗi lần mở → phải tự nhả, không thì mỗi lần đột phá
    // đọng thêm một codec webp ~1.2MB trong imageCache
    _img?.evict();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _img == null
      ? const SizedBox.expand()
      : Image(image: _img!, fit: BoxFit.cover, gaplessPlayback: true);
}
