import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// AMBIENT design tokens — "mỗi truyện một thế giới".
/// 2 palette sáng/tối; Neo.* là getter đọc palette hiện hành nên mọi màn
/// tự đổi theo chế độ mà không phải sửa từng chỗ.
class NeoPalette {
  final Color bg, surface, surface2, accent, accent2, danger, text, dim, faint;
  const NeoPalette({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.accent,
    required this.accent2,
    required this.danger,
    required this.text,
    required this.dim,
    required this.faint,
  });
}

/// Đêm — nền trung tính ấm.
const neoDark = NeoPalette(
  bg: Color(0xFF0D0D10),
  surface: Color(0xFF16161B),
  surface2: Color(0xFF1E1E25),
  accent: Color(0xFFE0C9A6), // vàng giấy cũ
  accent2: Color(0xFFB6A8D4), // tím khói
  danger: Color(0xFFE57388),
  text: Color(0xFFEDE9E3),
  dim: Color(0xFF8E8B93),
  faint: Color(0xFF2A2A32),
);

/// Ngày — giấy ấm, cùng ngôn ngữ, accent trầm xuống để đủ tương phản.
const neoLight = NeoPalette(
  bg: Color(0xFFF7F4EE),
  surface: Color(0xFFFFFFFF),
  surface2: Color(0xFFEFEBE2),
  accent: Color(0xFF8F6E35),
  accent2: Color(0xFF6C5CA8),
  danger: Color(0xFFBF3F58),
  text: Color(0xFF25211B),
  dim: Color(0xFF837D73),
  faint: Color(0xFFE4E0D6),
);

abstract final class Neo {
  /// Palette hiện hành — NeoApp gán khi đổi chế độ rồi rebuild cả cây.
  static NeoPalette p = neoDark;
  static bool get isDark => identical(p, neoDark);

  static Color get bg => p.bg;
  static Color get surface => p.surface;
  static Color get surface2 => p.surface2;
  // tên cũ giữ nguyên: cyan = accent chính, plasma = accent phụ
  static Color get cyan => p.accent;
  static Color get plasma => p.accent2;
  static Color get danger => p.danger;
  static Color get text => p.text;
  static Color get dim => p.dim;
  static Color get faint => p.faint;

  static const cut = 22.0;
  static const cutSm = 14.0;

  /// Màu chữ đặt TRÊN một màu accent bất kỳ (kể cả màu trích từ bìa).
  static Color onAccent(Color c) =>
      c.computeLuminance() > 0.45 ? const Color(0xFF211C14) : Colors.white;

  static TextStyle mono(double size,
          {Color? color, FontWeight weight = FontWeight.w500, double? spacing}) =>
      GoogleFonts.beVietnamPro(
          fontSize: size, color: color ?? dim, fontWeight: weight, letterSpacing: spacing ?? 0.6);

  static TextStyle display(double size,
          {Color? color, FontWeight weight = FontWeight.w700}) =>
      GoogleFonts.bricolageGrotesque(
          fontSize: size, color: color ?? text, fontWeight: weight, height: 1.08, letterSpacing: -0.3);

  /// Ánh sáng loãng — ban ngày dịu bớt.
  static List<BoxShadow> glow(Color c, {double blur = 36, double alpha = 0.25}) => [
        BoxShadow(
            color: c.withValues(alpha: isDark ? alpha : alpha * 0.55),
            blurRadius: blur,
            spreadRadius: 2)
      ];
}

/// ThemeData dựng từ palette hiện hành — gọi lại mỗi lần đổi chế độ.
ThemeData buildNeoTheme() => ThemeData(
      brightness: Neo.isDark ? Brightness.dark : Brightness.light,
      useMaterial3: true,
      scaffoldBackgroundColor: Neo.bg,
      colorScheme: ColorScheme(
        brightness: Neo.isDark ? Brightness.dark : Brightness.light,
        surface: Neo.bg,
        onSurface: Neo.text,
        primary: Neo.cyan,
        onPrimary: Neo.onAccent(Neo.cyan),
        secondary: Neo.plasma,
        onSecondary: Neo.onAccent(Neo.plasma),
        error: Neo.danger,
        onError: Colors.white,
        outline: Neo.faint,
      ),
      textTheme: TextTheme(
        displaySmall: Neo.display(34),
        headlineMedium: Neo.display(25),
        titleMedium: Neo.display(17, weight: FontWeight.w600),
        bodyLarge: GoogleFonts.beVietnamPro(fontSize: 16, color: Neo.text),
        bodyMedium:
            GoogleFonts.beVietnamPro(fontSize: 14, color: Neo.text.withValues(alpha: 0.8)),
        bodySmall: Neo.mono(12),
        labelSmall: Neo.mono(10, spacing: 1.2),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Neo.surface2,
        labelStyle: Neo.mono(13),
        prefixIconColor: Neo.dim,
        suffixIconColor: Neo.dim,
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(Neo.cutSm),
            borderSide: BorderSide(color: Neo.faint)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(Neo.cutSm),
            borderSide: BorderSide(color: Neo.cyan)),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(Neo.cutSm),
            borderSide: BorderSide(color: Neo.danger)),
        focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(Neo.cutSm),
            borderSide: BorderSide(color: Neo.danger)),
      ),
      splashFactory: InkSparkle.splashFactory,
    );
