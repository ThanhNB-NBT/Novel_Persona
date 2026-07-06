import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:palette_generator/palette_generator.dart';

import 'neo_theme.dart';

/// Khí quyển của một truyện: màu trích từ bìa, dùng nhuộm nền/viền/nút.
class Ambient {
  final Color accent; // màu nổi bật của bìa (đã nâng sáng để đọc được trên nền tối)
  final Color deep; // màu trầm của bìa — nhuộm nền
  const Ambient(this.accent, this.deep);

  static const fallback = Ambient(Neo.cyan, Color(0xFF1A1820));
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
        Neo.cyan;
    final dark = p.darkMutedColor?.color ?? p.darkVibrantColor?.color ?? Ambient.fallback.deep;
    // accent phải đủ sáng trên nền tối
    final hsl = HSLColor.fromColor(vivid);
    final accent = hsl.withLightness(hsl.lightness.clamp(0.62, 0.8)).toColor();
    final deep = HSLColor.fromColor(dark)
        .withLightness(HSLColor.fromColor(dark).lightness.clamp(0.06, 0.14))
        .toColor();
    return Ambient(accent, deep);
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
