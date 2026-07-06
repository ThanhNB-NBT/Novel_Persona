import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:palette_generator/palette_generator.dart';

/// Khí quyển của một truyện (port từ app NEO): màu trích từ bìa, nhuộm nền
/// trang thông tin truyện. Giữ màu THÔ; accent/deep chỉnh độ sáng theo chế độ.
class Ambient {
  final Color _vivid;
  final Color _dark;
  const Ambient(this._vivid, this._dark);

  static const fallback = Ambient(Color(0xFF3576F5), Color(0xFF16202E));

  /// Màu nổi bật: nâng sáng trên nền tối, dìm xuống trên nền sáng.
  Color accent(bool isDark) {
    final hsl = HSLColor.fromColor(_vivid);
    final l = isDark ? hsl.lightness.clamp(0.62, 0.8) : hsl.lightness.clamp(0.3, 0.44);
    return hsl.withLightness(l).withSaturation(hsl.saturation.clamp(0.25, 0.75)).toColor();
  }

  /// Màu nhuộm nền: rất trầm khi tối, rất nhạt khi sáng.
  Color deep(bool isDark) {
    final hsl = HSLColor.fromColor(isDark ? _dark : _vivid);
    final l = isDark ? hsl.lightness.clamp(0.06, 0.14) : 0.92;
    return hsl.withLightness(l.toDouble()).toColor();
  }
}

/// Trích màu từ URL bìa (cache theo URL — mỗi bìa chỉ tính 1 lần).
final ambientProvider = FutureProvider.family<Ambient, String?>((ref, url) async {
  if (url == null || url.isEmpty) return Ambient.fallback;
  ref.keepAlive();
  try {
    final p = await PaletteGenerator.fromImageProvider(
      NetworkImage(url),
      size: const Size(96, 128), // decode nhỏ — đủ để lấy màu, rẻ
      maximumColorCount: 12,
    );
    final vivid = p.vibrantColor?.color ??
        p.lightVibrantColor?.color ??
        p.dominantColor?.color ??
        const Color(0xFF3576F5);
    final dark =
        p.darkMutedColor?.color ?? p.darkVibrantColor?.color ?? const Color(0xFF16202E);
    return Ambient(vivid, dark);
  } catch (_) {
    return Ambient.fallback; // lỗi mạng/ảnh → khí quyển mặc định
  }
});

/// Nền khí quyển: gradient màu bìa loãng từ đỉnh màn tan vào nền chung.
class AmbientBackdrop extends StatelessWidget {
  final Ambient ambient;
  final Widget child;
  const AmbientBackdrop({super.key, required this.ambient, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = Theme.of(context).scaffoldBackgroundColor;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: const Alignment(0, 0.75),
          colors: [
            Color.lerp(ambient.deep(isDark), bg, 0.15)!,
            ambient.accent(isDark).withValues(alpha: 0.05),
            bg,
          ],
        ),
      ),
      child: child,
    );
  }
}
