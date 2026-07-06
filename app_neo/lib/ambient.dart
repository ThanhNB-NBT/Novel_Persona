import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:palette_generator/palette_generator.dart';

import 'neo_theme.dart';

/// Khí quyển của một truyện: màu trích từ bìa, dùng nhuộm nền/viền/nút.
/// Giữ màu THÔ; accent/deep là getter chỉnh độ sáng theo chế độ hiện hành
/// nên đổi sáng/tối không phải trích lại.
class Ambient {
  final Color _vivid;
  final Color _dark;
  const Ambient(this._vivid, this._dark);

  static const fallback = Ambient(Color(0xFFC9A96E), Color(0xFF1A1820));

  /// Màu nổi bật: nâng sáng trên nền tối, dìm xuống trên nền sáng.
  Color get accent {
    final hsl = HSLColor.fromColor(_vivid);
    final l = Neo.isDark
        ? hsl.lightness.clamp(0.62, 0.8)
        : hsl.lightness.clamp(0.3, 0.44);
    return hsl.withLightness(l).withSaturation(hsl.saturation.clamp(0.25, 0.75)).toColor();
  }

  /// Màu nhuộm nền: rất trầm khi tối, rất nhạt khi sáng.
  Color get deep {
    final hsl = HSLColor.fromColor(Neo.isDark ? _dark : _vivid);
    final l = Neo.isDark ? hsl.lightness.clamp(0.06, 0.14) : 0.92;
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
        const Color(0xFFC9A96E);
    final dark =
        p.darkMutedColor?.color ?? p.darkVibrantColor?.color ?? const Color(0xFF1A1820);
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
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: const Alignment(0, 0.75),
          colors: [
            Color.lerp(ambient.deep, Neo.bg, 0.15)!,
            ambient.accent.withValues(alpha: 0.05),
            Neo.bg,
          ],
        ),
      ),
      child: child,
    );
  }
}
