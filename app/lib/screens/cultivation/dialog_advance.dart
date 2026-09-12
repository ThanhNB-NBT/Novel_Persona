import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';

import '../../cultivation.dart';
import '../../data.dart';
import 'painters_fx.dart';
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
    with SingleTickerProviderStateMixin {
  static const _cloudEnd = 0.18;
  // mốc lộ kết quả — hằng dùng chung với BurstPainter (painters_fx.dart)
  static const _resultStart = advanceResultStart;

  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    // Đại cảnh giới cần đủ nhịp tụ mây → ba đạo lôi → dư chấn; tiểu cảnh giới gọn hơn.
    duration: Duration(milliseconds: widget.major ? 8000 : 1250),
  )..forward();
  bool _tammaPhase = false; // pha Tâm Ma trước khi lộ kết quả đột phá
  Timer? _tammaTimer;
  ui.FragmentShader? _shader; // nấc 2 (major); null = fallback về nấc 1

  Future<void> _loadShader() async {
    try {
      final prog = await ui.FragmentProgram.fromAsset(
        'shaders/breakthrough.frag',
      );
      if (mounted) setState(() => _shader = prog.fragmentShader());
    } catch (_) {
      // shader lỗi/thiết bị không hỗ trợ → giữ nguyên hiệu ứng nấc 1
    }
  }

  @override
  void initState() {
    super.initState();
    _ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) _impactHaptic();
    });
    if (widget.major) _loadShader(); // chỉ cảnh lớn mới cần shader
    // đại cảnh giới có Tâm Ma → diễn ~1.9s rồi mới sang kết quả đột phá
    if (widget.result['tamma'] != null) {
      _tammaPhase = true;
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
    _shader?.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final r = widget.result;
    if (_tammaPhase) return _tammaView(t, r['tamma'] as Rec);
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
        ..._residualOverlays(ok),
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
                    child: AnimatedCultivator(
                      realm: realm,
                      race: widget.race,
                      gender: widget.gender,
                    ),
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
                          ? AnimatedCultivator(
                              realm: realm,
                              race: widget.race,
                              gender: widget.gender,
                            )
                          : Image.asset(
                              'assets/cult_fx/heart_demon.webp',
                              width: 126,
                              height: 126,
                              fit: BoxFit.contain,
                            ),
                    ),
                    const SizedBox(height: 10),
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
                        child: Text(
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

  /// WebP động chứa trọn ba đạo kiếp lôi, tự giữ đúng nhịp và điểm chạm nhân vật.
  List<Widget> _tribulationOverlays(bool loi) {
    if (!loi) return const [];
    return [
      Positioned.fill(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, _) {
            final active = _ctrl.value >= _cloudEnd && _ctrl.value < _resultStart;
            if (!active) return const SizedBox.shrink();
            final stormT =
                ((_ctrl.value - _cloudEnd) / (_resultStart - _cloudEnd))
                    .clamp(0.0, 1.0)
                    .toDouble();
            return CustomPaint(
              painter: TribulationAtmospherePainter(stormT),
              child: const TribulationPreview(),
            );
          },
        ),
      ),
    ];
  }

  /// Rung màn theo từng đạo lôi chạm đất, đạo sau mạnh hơn đạo trước.
  Offset _strikeShake(double v) {
    var dx = 0.0, dy = 0.0;
    for (final (i, hit) in [0.38, 0.56, 0.74].indexed) {
      final d = v - hit;
      if (d >= 0 && d < 0.09) {
        final sh = (1 - d / 0.09) * (4 + i * 2.5);
        dx += math.sin(d * math.pi * 90) * sh;
        dy += math.cos(d * math.pi * 76) * sh;
      }
    }
    return Offset(dx, dy);
  }

  /// Hào quang + sét tàn dư chỉ xuất hiện SAU khi thành công.
  /// major: mount lúc lộ kết quả (mount muộn để Lottie tự chạy đúng lúc);
  /// minor: mount ngay từ đầu.
  List<Widget> _residualOverlays(bool ok) {
    if (!ok) return const [];
    final phase = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(_resultStart, 1, curve: Curves.easeOut),
    );
    return [
      // aura linh khí xoáy quanh nhân vật — mọi lần thành công, xoay lặp
      // liên tục tới khi đóng dialog
      Positioned.fill(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, child) =>
              !widget.major || _ctrl.value >= _resultStart
              ? child!
              : const SizedBox.shrink(),
          child: Align(
            alignment: const Alignment(0, -0.18),
            child: FractionallySizedBox(
              widthFactor: widget.major ? 0.9 : 0.6,
              child: AspectRatio(
                aspectRatio: 1,
                child: Lottie.asset(
                  'assets/cult_fx/fx_aura.json',
                  repeat: true,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ),
      ),
      if (widget.major)
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (_, child) => Offstage(
              offstage: _ctrl.value < _resultStart,
              child: child,
            ),
            child: Align(
              alignment: const Alignment(0, -0.45),
              child: FractionallySizedBox(
                widthFactor: 0.95,
                child: Lottie.asset(
                  'assets/cult_fx/fx_lightning.json',
                  controller: phase,
                  repeat: false,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ),
    ];
  }

  /// Pha Tâm Ma (~1.9s, tự chuyển sang kết quả): linh thể co giãn và trôi nhẹ,
  /// tím đạo nếu áp chế được, đỏ ma + rung nếu bị quấy nhiễu.
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
                painter: TammaPainter(v, win),
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
                AnimatedBuilder(
                  animation: _ctrl,
                  builder: (_, child) {
                    final pulse = 1 + math.sin(_ctrl.value * math.pi * 5) * 0.06;
                    return Transform.translate(
                      offset: Offset(0, math.sin(_ctrl.value * math.pi * 3) * 7),
                      child: Transform.scale(scale: pulse, child: child),
                    );
                  },
                  child: Image.asset(
                    'assets/cult_fx/heart_demon.webp',
                    width: 126,
                    height: 126,
                    fit: BoxFit.contain,
                  ),
                ),
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
}
