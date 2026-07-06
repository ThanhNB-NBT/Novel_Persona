import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// NEO TERMINAL design tokens — dark-first sci-fi HUD.
/// KHÔNG bo tròn mềm: mọi khối dùng góc vát (NeoClip trong neo_widgets.dart).
abstract final class Neo {
  // Nền
  static const bg = Color(0xFF05070D); // đen sâu
  static const surface = Color(0xFF0A0E18); // panel nổi nhẹ trên nền
  static const surface2 = Color(0xFF101624); // input / khối lồng nhau

  // Accent
  static const cyan = Color(0xFF00E5FF); // cyan điện — primary
  static const plasma = Color(0xFF7C4DFF); // tím plasma — secondary
  static const danger = Color(0xFFFF5370);

  // Chữ
  static const text = Color(0xFFDCE6F2);
  static const dim = Color(0xFF6B7A94); // label phụ, mono
  static const faint = Color(0xFF2A3448); // hairline border

  /// Cạnh vát chuẩn cho card/panel (px).
  static const cut = 12.0;
  static const cutSm = 7.0;

  static TextStyle mono(double size,
          {Color color = dim, FontWeight weight = FontWeight.w500, double? spacing}) =>
      GoogleFonts.jetBrainsMono(
          fontSize: size, color: color, fontWeight: weight, letterSpacing: spacing ?? 1.2);

  static TextStyle display(double size,
          {Color color = text, FontWeight weight = FontWeight.w700}) =>
      GoogleFonts.spaceGrotesk(fontSize: size, color: color, fontWeight: weight, height: 1.1);

  static List<BoxShadow> glow(Color c, {double blur = 18, double alpha = 0.45}) =>
      [BoxShadow(color: c.withValues(alpha: alpha), blurRadius: blur, spreadRadius: -2)];
}

final neoTheme = ThemeData(
  brightness: Brightness.dark,
  useMaterial3: true,
  scaffoldBackgroundColor: Neo.bg,
  colorScheme: const ColorScheme.dark(
    surface: Neo.bg,
    primary: Neo.cyan,
    onPrimary: Color(0xFF001318),
    secondary: Neo.plasma,
    error: Neo.danger,
    onSurface: Neo.text,
    outline: Neo.faint,
  ),
  textTheme: TextTheme(
    displaySmall: Neo.display(32),
    headlineMedium: Neo.display(24),
    titleMedium: Neo.display(17, weight: FontWeight.w600),
    bodyLarge: GoogleFonts.spaceGrotesk(fontSize: 16, color: Neo.text),
    bodyMedium: GoogleFonts.spaceGrotesk(fontSize: 14, color: Neo.text.withValues(alpha: 0.8)),
    bodySmall: Neo.mono(12),
    labelSmall: Neo.mono(10, spacing: 2.5),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Neo.surface2,
    labelStyle: Neo.mono(13),
    prefixIconColor: Neo.dim,
    suffixIconColor: Neo.dim,
    enabledBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.zero, borderSide: BorderSide(color: Neo.faint)),
    focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.zero, borderSide: BorderSide(color: Neo.cyan)),
    errorBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.zero, borderSide: BorderSide(color: Neo.danger)),
    focusedErrorBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.zero, borderSide: BorderSide(color: Neo.danger)),
  ),
  splashFactory: InkSparkle.splashFactory,
);
