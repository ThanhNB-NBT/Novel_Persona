import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../cultivation.dart';
import '../../data.dart';
import 'painters_fx.dart';
import 'painters_lightning.dart';
import 'painters_qi.dart';
import 'pixel.dart';
import 'preview.dart';

/// Dialog kết quả lên tầng/đột phá, tự vẽ hiệu ứng chạy 1 lần (~1.1s):
/// thành công = chớp sáng + vòng xung kích + 12 tia lan ra + nhân vật hiện dần;
/// thất bại = rung ngang + quầng đỏ tắt dần.
class AdvanceFxDialog extends StatefulWidget {
  final Rec result;
  final bool major;
  final bool ascend; // phi thăng: đổi chữ + tông vàng tiên
  final String? race;
  final String? gender;
  const AdvanceFxDialog({
    super.key,
    required this.result,
    required this.major,
    this.ascend = false,
    this.race,
    this.gender,
  });
  @override
  State<AdvanceFxDialog> createState() => _AdvanceFxDialogState();
}

class _AdvanceFxDialogState extends State<AdvanceFxDialog>
    with TickerProviderStateMixin {
  static const _cloudEnd = 0.18;
  // mốc lộ kết quả — hằng dùng chung với BurstPainter (painters_fx.dart)
  static const _resultStart = advanceResultStart;

  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    // Đại cảnh giới cần đủ nhịp tụ mây → ba đạo lôi → dư chấn; tiểu cảnh giới gọn hơn.
    duration: Duration(milliseconds: widget.major ? 8000 : 1250),
  )..forward();
  // Đồng hồ liên tục (đơn vị vòng 4s) cho linh khí quấn quanh — không reset như _ctrl.
  final _qiTime = ValueNotifier<double>(0);
  late final Ticker _qiTicker; // tạo + chạy trong initState (late lười sẽ không bao giờ start)
  bool _tammaPhase = false; // pha Tâm Ma trước khi lộ kết quả đột phá
  Timer? _tammaTimer;
  ui.FragmentShader? _shader; // nấc 2 (major); null = fallback về nấc 1
  // Tâm Ma 3D: 2 bản shader (sau/trước ảnh) — null = TammaPainter canvas cũ
  (ui.FragmentShader, ui.FragmentShader)? _tammaShaders;
  ui.FragmentShader? _storm; // trần mây kiếp 3D — null = mây canvas

  Future<void> _loadShader() async {
    try {
      final prog = await ui.FragmentProgram.fromAsset(
        'shaders/breakthrough.frag',
      );
      if (mounted) setState(() => _shader = prog.fragmentShader());
    } catch (_) {
      // shader lỗi/thiết bị không hỗ trợ → giữ nguyên hiệu ứng nấc 1
    }
    try {
      final prog = await ui.FragmentProgram.fromAsset('shaders/storm.frag');
      if (mounted) setState(() => _storm = prog.fragmentShader());
    } catch (_) {}
  }

  Future<void> _loadTammaShader() async {
    try {
      final prog = await ui.FragmentProgram.fromAsset('shaders/tamma.frag');
      if (mounted) {
        setState(() => _tammaShaders = (prog.fragmentShader(), prog.fragmentShader()));
      }
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _qiTicker = createTicker((e) => _qiTime.value = e.inMicroseconds / 4e6)
      ..start();
    _ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) _impactHaptic();
    });
    if (widget.major) _loadShader(); // chỉ cảnh lớn mới cần shader
    // đại cảnh giới có Tâm Ma → diễn ~1.9s rồi mới sang kết quả đột phá
    if (widget.result['tamma'] != null) {
      _tammaPhase = true;
      _loadTammaShader();
      HapticFeedback.mediumImpact(); // vào khảo nghiệm
      _tammaTimer = Timer(const Duration(milliseconds: 2200), () {
        if (mounted) {
          setState(() => _tammaPhase = false);
          _ctrl
            ..reset()
            ..forward();
        }
      });
    }
  }

  void _impactHaptic() {
    final ok = widget.result['success'] == true;
    if (!ok) {
      HapticFeedback.mediumImpact();
    } else if (widget.major) {
      HapticFeedback.heavyImpact(); // đại cảnh giới thành công = cú va chạm mạnh
    } else {
      HapticFeedback.lightImpact();
    }
  }

  @override
  void dispose() {
    _tammaTimer?.cancel();
    _qiTicker.dispose();
    _qiTime.dispose();
    _shader?.dispose();
    _storm?.dispose();
    _tammaShaders?.$1.dispose();
    _tammaShaders?.$2.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final r = widget.result;
    if (_tammaPhase) {
      return Stack(
        fit: StackFit.expand,
        children: [
          _backdrop(false, const Color(0xFF7048E8)),
          _tammaView(t, r['tamma'] as Rec),
        ],
      );
    }
    final ok = r['success'] == true;
    final realm = r['realm'] as int;
    final grade = (realm + 1) ~/ 2;
    final color = ok
        ? (widget.ascend
              ? gradeColor(5)
              : gradeColor(grade)) // vàng tiên khi phi thăng
        : const Color(0xFFE03131);
    // đột phá VÀO Kim Đan trở lên → thiên lôi giáng xuống (lore: kết đan dẫn kiếp)
    final loi = widget.major;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (widget.major) _backdrop(ok, color),
        // FX phủ TOÀN MÀN HÌNH → vụ nổ tan vào bóng tối, không chạm mép hộp thoại
        Positioned.fill(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (_, _) => CustomPaint(
                painter: BurstPainter(
                  _ctrl.value,
                  color,
                  ok,
                  loi,
                  major: widget.major,
                  shader: _shader,
                ),
              ),
            ),
          ),
        ),
        // Asset kiếp lôi động phủ lên thiên tượng Canvas, kết thúc đúng điểm nhân vật.
        ..._tribulationOverlays(loi),
        if (widget.major)
          AnimatedBuilder(
            animation: _ctrl,
            builder: (_, _) => Offstage(
              offstage: _ctrl.value >= _resultStart,
              // rung màn theo từng đạo lôi chạm đất — áp vào nhân vật đang chịu kiếp
              child: Transform.translate(
                offset: _strikeShake(_ctrl.value),
                child: Center(
                  child: Material(
                    color: Colors.transparent,
                    child: _hero(AnimatedCultivator(
                      realm: realm,
                      race: widget.race,
                      gender: widget.gender,
                    )),
                  ),
                ),
              ),
            ),
          ),
        // Nội dung (nhân vật + chữ + nút) căn giữa; chỉ phần này rung máy
        AnimatedBuilder(
          animation: _ctrl,
          builder: (_, child) => Offstage(
            offstage: widget.major && _ctrl.value < _resultStart,
            child: child,
          ),
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: AnimatedBuilder(
                animation: _ctrl,
                builder: (_, child) {
                final v = _ctrl.value;
                var dx = ok ? 0.0 : math.sin(v * math.pi * 10) * 8 * (1 - v);
                var dy = 0.0;
                // major thành công: cú "slam" rung mạnh tắt dần ngay khi lộ kết quả
                if (widget.major && ok) {
                  final d = v - _resultStart;
                  if (d >= 0 && d < 0.08) {
                    final sh = (1 - d / 0.08) * 9;
                    dx += math.sin(d * math.pi * 90) * sh;
                    dy += math.cos(d * math.pi * 76) * sh;
                  }
                }
                  return Transform.translate(
                    offset: Offset(dx, dy),
                    child: child,
                  );
                },
                child: Padding(
                padding: const EdgeInsets.all(
                  48,
                ), // chừa chỗ cho vòng xung kích
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // nhân vật/phù hiện dần sau chớp sáng
                    FadeTransition(
                      opacity: CurvedAnimation(
                        parent: _ctrl,
                        curve: const Interval(0.15, 0.6, curve: Curves.easeOut),
                      ),
                      child: ok
                          ? _hero(AnimatedBuilder(
                              animation: Listenable.merge([_ctrl, _qiTime]),
                              // linh khí quấn quanh người: pháp trận + dải + hạt,
                              // lớp sau dưới nhân vật, lớp trước đè lên (painters_qi)
                              builder: (_, child) {
                                final intro = widget.major
                                    ? (_ctrl.value - _resultStart) / 0.1
                                    : _ctrl.value / 0.7;
                                return CustomPaint(
                                  painter: QiVortexPainter(
                                    _qiTime.value, intro, color,
                                    front: false, major: widget.major),
                                  foregroundPainter: QiVortexPainter(
                                    _qiTime.value, intro, color,
                                    front: true, major: widget.major),
                                  child: child,
                                );
                              },
                              child: AnimatedCultivator(
                                realm: realm,
                                race: widget.race,
                                gender: widget.gender,
                              ),
                            ))
                          : Image.asset(
                              'assets/cult_fx/heart_demon.webp',
                              width: 126,
                              height: 126,
                              fit: BoxFit.contain,
                            ),
                    ),
                    // chừa chỗ cho pháp trận dưới chân (QiVortexPainter) khỏi đè tiêu đề
                    SizedBox(height: ok ? 24 : 10),
                    // major thành công: tên "slam" vào (phóng to → co về, nảy) sau va chạm
                    FadeTransition(
                      opacity: widget.major && ok
                          ? CurvedAnimation(
                              parent: _ctrl,
                              curve: const Interval(0.90, 0.96),
                            )
                          : const AlwaysStoppedAnimation(1.0),
                      child: ScaleTransition(
                        scale: widget.major && ok
                            ? Tween(begin: 1.5, end: 1.0).animate(
                                CurvedAnimation(
                                  parent: _ctrl,
                                  curve: const Interval(
                                    0.90,
                                    1.0,
                                    curve: Curves.elasticOut,
                                  ),
                                ),
                              )
                            : const AlwaysStoppedAnimation(1.0),
                        child: widget.major && ok && !widget.ascend
                            ? _realmTitle(t, realm, loi)
                            : Text(
                          widget.ascend
                              ? (ok
                                    ? 'PHI THĂNG THÀNH CÔNG'
                                    : 'PHI THĂNG THẤT BẠI')
                              : widget.major
                              ? (ok
                                    ? (loi
                                          ? 'VƯỢT LÔI KIẾP THÀNH CÔNG'
                                          : 'ĐỘT PHÁ THÀNH CÔNG')
                                    : 'ĐỘT PHÁ THẤT BẠI')
                              : 'LÊN TẦNG',
                          style: t.titleLarge?.copyWith(
                            color: ok ? Colors.white : color,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.ascend
                          ? (ok
                                ? 'Vượt Tâm Ma cuối, độ kiếp phi thăng —\nđắc đạo thành Tiên Nhân!'
                                : 'Tâm ma còn vương, phi thăng bất thành.\nTĩnh tâm rồi thử lại.')
                          : ok
                          ? '${realmNames[realm - 1]} · tầng ${r['stage']}'
                          : loi
                          ? 'Lôi kiếp đánh rớt, tâm ma quấy nhiễu — mất 30% tu vi tầng này.\nTĩnh tâm dưỡng thương rồi thử lại!'
                          : 'Tẩu hỏa nhập ma nhẹ, mất 30% tu vi tầng này.\nTĩnh tâm tu luyện tiếp!',
                      textAlign: TextAlign.center,
                      style: t.bodyMedium?.copyWith(color: Colors.white70),
                    ),
                    if (widget.major && !widget.ascend)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Tỷ lệ lúc roll: ${r['chance']}%',
                          style: t.labelMedium?.copyWith(color: Colors.white38),
                        ),
                      ),
                    if (!widget.ascend && (r['tamma'] as Rec?)?['win'] == true)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '⚔ Áp chế Tâm Ma · +15% đột phá',
                          style: t.labelMedium?.copyWith(
                            color: const Color(0xFF9775FA),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    const SizedBox(height: 18),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: color,
                        foregroundColor: ok && grade >= 4
                            ? Colors.black87
                            : Colors.white,
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        ok
                            ? (widget.ascend
                                  ? 'Đắc đạo thành tiên'
                                  : 'Tiếp tục tu luyện')
                            : 'Tĩnh tâm',
                      ),
                    ),
                  ],
                ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Lôi kiếp vẽ thủ tục (painters_lightning.dart): tia dẫn → cú đánh chớp lại →
  /// tàn sáng, lóe trời, hồ quang + tia lửa tại điểm chạm (đầu nhân vật giữa màn).
  List<Widget> _tribulationOverlays(bool loi) {
    if (!loi) return const [];
    return [
      Positioned.fill(
        child: IgnorePointer(
          child: RepaintBoundary(
            child: LayoutBuilder(
              builder: (_, box) => AnimatedBuilder(
                animation: _ctrl,
                builder: (_, _) => CustomPaint(
                  painter: LightningStormPainter(
                    _ctrl.value,
                    from: _cloudEnd,
                    to: _resultStart,
                    target: Offset(box.maxWidth / 2, box.maxHeight / 2 - 58),
                    cloud: _storm,
                    seconds: _ctrl.value * 8,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ];
  }

  /// Rung màn theo từng đạo lôi chạm đất, đạo sau mạnh hơn đạo trước.
  Offset _strikeShake(double v) {
    var dx = 0.0, dy = 0.0;
    for (final (i, hit) in tribulationHits.indexed) {
      final d = v - hit;
      if (d >= 0 && d < 0.09) {
        final sh = (1 - d / 0.09) * (4 + i * 2.5);
        dx += math.sin(d * math.pi * 90) * sh;
        dy += math.cos(d * math.pi * 76) * sh;
      }
    }
    return Offset(dx, dy);
  }

  /// Pha Tâm Ma (~1.9s, tự chuyển sang kết quả): linh thể co giãn và trôi nhẹ,
  /// tím đạo nếu áp chế được, đỏ ma + rung nếu bị quấy nhiễu.
  /// Phông nền điện ảnh phủ kín (chỉ đại cảnh giới) — che UI app phía sau.
  Widget _backdrop(bool ok, Color color) => Positioned.fill(
        child: IgnorePointer(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: Listenable.merge([_ctrl, _qiTime]),
              builder: (_, _) => CustomPaint(
                painter: MajorBackdropPainter(
                  _tammaPhase ? 0.05 : _ctrl.value,
                  _qiTime.value,
                  color,
                  ok: ok && !_tammaPhase,
                  resultStart: _resultStart,
                ),
              ),
            ),
          ),
        ),
      );

  /// Đại cảnh giới: nhân vật là tâm điểm — phóng 1.6× (FittedBox giữ đúng layout,
  /// painter tràn khung vẫn vẽ). Lên tầng giữ cỡ gốc.
  Widget _hero(Widget cultivator) => widget.major
      ? SizedBox(
          width: 150 * 1.6,
          height: 145 * 1.6,
          child: FittedBox(clipBehavior: Clip.none, child: cultivator),
        )
      : cultivator;

  /// Tiêu đề phá cảnh: dòng nhỏ giãn chữ + TÊN CẢNH GIỚI MỚI cỡ lớn, vàng chuyển sắc
  /// có quầng sáng — thay dòng chữ nhỏ cũ lẫn vào nền.
  Widget _realmTitle(TextTheme t, int realm, bool loi) {
    const gold = [Color(0xFFFFF3BF), Color(0xFFFFD25A), Color(0xFFE8A80C)];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          loi ? 'VƯỢT LÔI KIẾP · ĐỘT PHÁ' : 'ĐỘT PHÁ ĐẠI CẢNH GIỚI',
          style: t.labelLarge?.copyWith(
            color: const Color(0xFFFFE8A3),
            letterSpacing: 4,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        ShaderMask(
          shaderCallback: (b) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: gold,
          ).createShader(b),
          child: Text(
            realmNames[realm - 1].toUpperCase(),
            textAlign: TextAlign.center,
            style: t.displaySmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              letterSpacing: 6,
              shadows: const [
                Shadow(color: Color(0xCCFFB300), blurRadius: 18),
                Shadow(color: Color(0x88FF8F00), blurRadius: 36),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _tammaView(TextTheme t, Rec tm) {
    final win = tm['win'] == true;
    final color = win ? const Color(0xFF7048E8) : const Color(0xFFC92A2A);
    return Center(
      child: Material(
        color: Colors.transparent,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, child) {
            final v = _ctrl.value;
            final dx = win ? 0.0 : math.sin(v * math.pi * 12) * 6 * (1 - v);
            return Transform.translate(
              offset: Offset(dx, 0),
              child: CustomPaint(
                painter: _tammaShaders == null ? TammaPainter(v, win) : null,
                foregroundPainter: BurstPainter(v, color, win, false),
                child: child,
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(48),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _tammaHeart(win),
                const SizedBox(height: 10),
                Text(
                  'TÂM MA KHẢO NGHIỆM',
                  style: t.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  win
                      ? 'Đạo tâm bất động — áp chế tâm ma!'
                      : 'Tâm thần chấn động, tâm ma trỗi dậy...',
                  textAlign: TextAlign.center,
                  style: t.bodyMedium?.copyWith(color: Colors.white70),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Đạo tâm ${tm['chance']}%',
                    style: t.labelMedium?.copyWith(color: Colors.white38),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Mặt quỷ: xoay phối cảnh 3D (lắc Y + gật X) giữa hai lớp khói thể tích.
  Widget _tammaHeart(bool win) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) {
        final v = _ctrl.value;
        final sec = v * _ctrl.duration!.inMilliseconds / 1000;
        final pulse = 1 + math.sin(v * math.pi * 5) * 0.06;
        final face = Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0022)
            ..translateByDouble(0, math.sin(v * math.pi * 3) * 7, 0, 1)
            ..rotateY(math.sin(sec * 1.7) * 0.55)
            ..rotateX(math.sin(sec * 1.1) * 0.22)
            ..scaleByDouble(pulse, pulse, 1, 1),
          child: child,
        );
        final sh = _tammaShaders;
        if (sh == null) return face;
        // tiến trình trong pha Tâm Ma (2.2s đầu của timeline)
        final p = (sec / 2.2).clamp(0.0, 1.0);
        return CustomPaint(
          painter: TammaVolumePainter(sh.$1, p, sec, win, front: false),
          foregroundPainter: TammaVolumePainter(sh.$2, p, sec, win, front: true),
          child: face,
        );
      },
      child: Image.asset(
        'assets/cult_fx/heart_demon.webp',
        width: 126,
        height: 126,
        fit: BoxFit.contain,
      ),
    );
  }
}
