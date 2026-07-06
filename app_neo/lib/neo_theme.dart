import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// AMBIENT design tokens — "mỗi truyện một thế giới".
/// Nền trung tính trầm, khí quyển màu lấy từ bìa truyện (ambient.dart);
/// chữ display editorial lớn, mọi khối bo mềm, ánh sáng loãng thay neon.
///
/// Giữ tên class/member cũ (Neo, cyan, plasma, mono, display, glow, cut…)
/// để không phải sửa hàng loạt màn — chỉ đổi GIÁ TRỊ và chất liệu.
abstract final class Neo {
  // Nền trung tính ấm, không xanh lạnh
  static const bg = Color(0xFF0D0D10);
  static const surface = Color(0xFF16161B); // panel nổi nhẹ
  static const surface2 = Color(0xFF1E1E25); // input / khối lồng

  // Accent tĩnh mặc định (khi chưa có màu bìa): vàng giấy cũ + tím khói.
  // Tên giữ nguyên từ bản terminal — cyan = accent chính, plasma = phụ.
  static const cyan = Color(0xFFE0C9A6);
  static const plasma = Color(0xFFB6A8D4);
  static const danger = Color(0xFFE57388);

  static const text = Color(0xFFEDE9E3); // trắng ấm
  static const dim = Color(0xFF8E8B93);
  static const faint = Color(0xFF2A2A32); // hairline

  /// Bán kính bo chuẩn (tên "cut" giữ từ bản cũ).
  static const cut = 22.0;
  static const cutSm = 14.0;

  /// Nhãn nhỏ giãn cách — thay cho mono terminal, cùng chữ ký hàm.
  static TextStyle mono(double size,
          {Color color = dim, FontWeight weight = FontWeight.w500, double? spacing}) =>
      GoogleFonts.beVietnamPro(
          fontSize: size, color: color, fontWeight: weight, letterSpacing: spacing ?? 0.6);

  /// Display editorial — Bricolage Grotesque, đậm, sát dòng.
  static TextStyle display(double size,
          {Color color = text, FontWeight weight = FontWeight.w700}) =>
      GoogleFonts.bricolageGrotesque(
          fontSize: size, color: color, fontWeight: weight, height: 1.08, letterSpacing: -0.3);

  /// Ánh sáng loãng (ambient) — mềm, lan rộng, không phải neon.
  static List<BoxShadow> glow(Color c, {double blur = 36, double alpha = 0.25}) =>
      [BoxShadow(color: c.withValues(alpha: alpha), blurRadius: blur, spreadRadius: 2)];
}

final neoTheme = ThemeData(
  brightness: Brightness.dark,
  useMaterial3: true,
  scaffoldBackgroundColor: Neo.bg,
  colorScheme: const ColorScheme.dark(
    surface: Neo.bg,
    primary: Neo.cyan,
    onPrimary: Color(0xFF1C1710),
    secondary: Neo.plasma,
    error: Neo.danger,
    onSurface: Neo.text,
    outline: Neo.faint,
  ),
  textTheme: TextTheme(
    displaySmall: Neo.display(34),
    headlineMedium: Neo.display(25),
    titleMedium: Neo.display(17, weight: FontWeight.w600),
    bodyLarge: GoogleFonts.beVietnamPro(fontSize: 16, color: Neo.text),
    bodyMedium: GoogleFonts.beVietnamPro(fontSize: 14, color: Neo.text.withValues(alpha: 0.8)),
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
        borderSide: const BorderSide(color: Neo.faint)),
    focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Neo.cutSm),
        borderSide: const BorderSide(color: Neo.cyan)),
    errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Neo.cutSm),
        borderSide: const BorderSide(color: Neo.danger)),
    focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Neo.cutSm),
        borderSide: const BorderSide(color: Neo.danger)),
  ),
  splashFactory: InkSparkle.splashFactory,
);
