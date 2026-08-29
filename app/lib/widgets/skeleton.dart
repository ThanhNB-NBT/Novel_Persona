import 'package:flutter/material.dart';

/// Skeleton có VỆT SÁNG chạy ngang (như skeleton web) — không phải chỉ mờ dần.
/// ShaderMask phủ gradient [nền→sáng→nền] lên cả cây con, dịch ngang mỗi frame;
/// blend srcATop nên chỉ tô lên các ô xám (nền trong suốt giữ nguyên). Một
/// controller cho cả cây: rẻ hơn mỗi ô một animation.
class _Shimmer extends StatefulWidget {
  final Widget child;
  const _Shimmer({required this.child});
  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200))
    ..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onSurf = Theme.of(context).colorScheme.onSurface;
    final base = onSurf.withValues(alpha: 0.09); // ô nền
    final glow = onSurf.withValues(alpha: 0.22); // vệt sáng lướt qua
    // srcIn: màu vẽ ra = gradient này, CẮT theo hình các ô bên dưới (chỗ trong suốt
    // vẫn trong suốt). Nên ô phải ĐỤC — xem _skelBox — và toàn bộ alpha nhìn thấy
    // do gradient quyết định, kể cả khi đứng yên. Bỏ ShaderMask đi thì ô đen kịt.
    // (srcATop thì ngược: nó GIỮ nền ở chỗ nguồn mờ, ô đục sẽ lòi ra nguyên màu.)
    Widget mask(ShaderCallback shader, Widget? child) => ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: shader,
          child: child,
        );
    LinearGradient gradient(double slide) => LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [base, glow, base],
          stops: const [0.3, 0.5, 0.7],
          // vệt (rộng ~40% ô) trượt từ ngoài trái sang ngoài phải mỗi vòng
          transform: _SlideGradient(slide),
        );
    // người dùng tắt hoạt ảnh → đứng yên (vệt nằm ngoài khung, chỉ còn nền)
    if (MediaQuery.of(context).disableAnimations) {
      return mask((bounds) => gradient(-0.9).createShader(bounds), widget.child);
    }
    // child dựng 1 lần rồi tái dùng: mỗi frame chỉ vẽ lại shader, không rebuild cây.
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) =>
          mask((bounds) => gradient(_c.value * 1.8 - 0.9).createShader(bounds), child),
    );
  }
}

/// Dịch ngang gradient theo bội số bề rộng vùng vẽ (cho vệt shimmer chạy).
class _SlideGradient extends GradientTransform {
  final double ratio;
  const _SlideGradient(this.ratio);
  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * ratio, 0, 0);
}

/// Một ô bo góc — viên gạch dựng skeleton. Ô này chỉ đóng vai KHUÔN CẮT cho
/// _Shimmer (srcIn), nên màu phải ĐỤC và màu gì cũng được; alpha nhìn thấy thật
/// (0.09 nền, 0.22 chỗ vệt sáng quét qua) nằm ở gradient bên đó.
/// Bản cũ để ô ở alpha 0.09 rồi phủ srcATop: vệt sáng bị nhân với 0.09, còn ~1%
/// alpha — chạy thật mà mắt không thấy. Xem test/skeleton_shimmer_test.dart.
Widget _skelBox(BuildContext context, {double? width, double height = 12, double radius = 7}) {
  return Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.onSurface,
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}

/// Skeleton cho danh sách truyện (Tủ truyện / Tìm kiếm / Lọc) — nhại NovelListRow:
/// bìa + 2 dòng chữ. Hiện ~6 dòng khi đang tải.
class SkeletonList extends StatelessWidget {
  final int rows;
  const SkeletonList({super.key, this.rows = 6});
  @override
  Widget build(BuildContext context) {
    return _Shimmer(
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: rows,
        itemBuilder: (context, _) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _skelBox(context, width: 76, height: 76 * 1.36, radius: 8),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SizedBox(height: 2),
                _skelBox(context, width: double.infinity, height: 15),
                const SizedBox(height: 10),
                _skelBox(context, width: 120, height: 12),
                const SizedBox(height: 18),
                _skelBox(context, width: 90, height: 12),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Skeleton cho trang Khám phá: 1 khối hero + vài rail bìa ngang.
class SkeletonHome extends StatelessWidget {
  const SkeletonHome({super.key});
  @override
  Widget build(BuildContext context) {
    Widget rail() => Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 0, 12),
              child: _skelBox(context, width: 140, height: 20),
            ),
            SizedBox(
              height: 150,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.only(left: 20),
                itemCount: 4,
                itemBuilder: (context, _) => Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: _skelBox(context, width: 108, height: 150, radius: 8),
                ),
              ),
            ),
          ]),
        );
    return _Shimmer(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        children: [
          _skelBox(context, width: double.infinity, height: 170, radius: 16),
          const SizedBox(height: 24),
          rail(),
          rail(),
        ],
      ),
    );
  }
}
