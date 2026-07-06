import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Hệ thiết kế "Thanh Tân" — sáng, trắng lạnh, nhấn XANH DƯƠNG, bo tròn nhiều.
/// Ban đêm dùng bộ "Dạ Lam": nền xanh đêm, nhấn xanh băng.
/// Một họ chữ Be Vietnam Pro (dấu tiếng Việt chuẩn), phân cấp bằng đậm/cỡ.
/// Tránh trắng/đen tuyền hoàn toàn.
class Pal {
  // sáng — Thanh Tân
  static const bg = Color(0xFFF5F7FA); // nền trắng lạnh (ngả xanh nhẹ)
  static const surface = Color(0xFFFFFFFF); // thẻ
  static const surfaceAlt = Color(0xFFE9EDF2);
  static const ink = Color(0xFF1D2129); // chữ chính (không đen tuyền)
  static const inkSoft = Color(0xFF848B96); // chữ phụ
  static const accent = Color(0xFF3576F5); // xanh dương thanh tân
  static const accentDeep = Color(0xFF2A5BC7);
  static const accentSoft = Color(0xFFE1EBFE);
  static const gold = Color(0xFFE8913C); // streak / thành tựu (cam ấm)
  static const line = Color(0xFFE6EAF0);

  // tối — Dạ Lam, bản OLED "tech-minimal": nền gần đen (tiết kiệm pin, chất công nghệ),
  // phân lớp bằng VIỀN 1px mờ thay vì nâng độ sáng nền.
  static const dBg = Color(0xFF0A0E14);
  static const dSurface = Color(0xFF10151D);
  static const dSurfaceAlt = Color(0xFF161D27);
  static const dInk = Color(0xFFE6EAF0); // không trắng tinh
  static const dInkSoft = Color(0xFF7E8898);
  static const dAccent = Color(0xFF5CC8E8); // xanh băng
  static const dAccentDeep = Color(0xFF3A93B5);
  static const dAccentSoft = Color(0xFF14262F);
  static const dGold = Color(0xFFF2A65A);
  static const dLine = Color(0xFF1D2530); // hairline kiểu Vercel/Linear
}

/// Plus Jakarta Sans — sans hình học hiện đại, hỗ trợ dấu tiếng Việt.
/// Tiêu đề lớn: đậm + tracking âm cho cảm giác "premium".
TextTheme _text(Color ink, Color soft) {
  TextStyle f(double size, FontWeight w, {double sp = 0, double h = 1.2, Color? c}) =>
      GoogleFonts.plusJakartaSans(
          fontSize: size, fontWeight: w, letterSpacing: sp, height: h, color: c ?? ink);
  return TextTheme(
    displaySmall: f(30, FontWeight.w800, sp: -0.9, h: 1.05),
    headlineMedium: f(24, FontWeight.w800, sp: -0.6),
    headlineSmall: f(20, FontWeight.w700, sp: -0.4),
    titleLarge: f(18, FontWeight.w700, sp: -0.3),
    titleMedium: f(15.5, FontWeight.w600, sp: -0.1),
    bodyLarge: f(15.5, FontWeight.w400, h: 1.5),
    bodyMedium: f(14, FontWeight.w400, h: 1.55, c: soft),
    bodySmall: f(12.5, FontWeight.w400, h: 1.4, c: soft),
    labelLarge: f(14, FontWeight.w600),
    labelMedium: f(13, FontWeight.w500, c: soft),
    labelSmall: f(11.5, FontWeight.w700, sp: 0.6, c: soft),
  );
}

/// Font mono cho SỐ LIỆU (số chương, %, thời gian) — chi tiết "tech" của app.
/// Chữ thường vẫn Plus Jakarta Sans; chỉ dùng mono cho con số/giá trị đo được.
TextStyle monoStyle(BuildContext context, {double size = 12, FontWeight w = FontWeight.w500, Color? color}) =>
    GoogleFonts.jetBrainsMono(
        fontSize: size,
        fontWeight: w,
        letterSpacing: -0.3,
        height: 1.2, // mono mặc định line-height cao → tràn các ô cố định chiều cao
        color: color ?? Theme.of(context).colorScheme.onSurfaceVariant);

ThemeData _build({required bool dark}) {
  final bg = dark ? Pal.dBg : Pal.bg;
  final surface = dark ? Pal.dSurface : Pal.surface;
  final ink = dark ? Pal.dInk : Pal.ink;
  final soft = dark ? Pal.dInkSoft : Pal.inkSoft;
  final accent = dark ? Pal.dAccent : Pal.accent;
  final line = dark ? Pal.dLine : Pal.line;
  final onAccent = dark ? const Color(0xFF0F2630) : Colors.white;

  return ThemeData(
    useMaterial3: true,
    brightness: dark ? Brightness.dark : Brightness.light,
    // Chuyển trang kiểu iOS: trượt ngang + vuốt từ mép trái để back (cả Android)
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
    scaffoldBackgroundColor: bg,
    canvasColor: bg,
    colorScheme: ColorScheme(
      brightness: dark ? Brightness.dark : Brightness.light,
      primary: accent,
      onPrimary: onAccent,
      primaryContainer: dark ? Pal.dAccentSoft : Pal.accentSoft,
      onPrimaryContainer: dark ? Pal.dAccent : Pal.accentDeep,
      secondary: dark ? Pal.dGold : Pal.gold,
      onSecondary: Colors.white,
      error: const Color(0xFFD1544A),
      onError: Colors.white,
      surface: surface,
      onSurface: ink,
      onSurfaceVariant: soft,
      outline: line,
      outlineVariant: line,
    ),
    textTheme: _text(ink, soft),
    dividerColor: line,
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      foregroundColor: ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.plusJakartaSans(
        color: ink,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: line),
      ),
      margin: EdgeInsets.zero,
    ),
    navigationBarTheme: NavigationBarThemeData(
      // bán trong suốt — shell bọc BackdropFilter blur (extendBody) → nav "kính mờ"
      backgroundColor: surface.withValues(alpha: dark ? 0.72 : 0.85),
      elevation: 0,
      height: 68,
      // Không đổi màu cả vùng (pill) — chỉ đổi màu icon: đậm khi chọn, xám khi không.
      indicatorColor: Colors.transparent,
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => GoogleFonts.plusJakartaSans(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: s.contains(WidgetState.selected) ? ink : soft,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          color: s.contains(WidgetState.selected) ? ink : soft,
          size: 24,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: onAccent,
        textStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 15, letterSpacing: -0.1),
        // pill (StadiumBorder) — ăn khớp dock pill + hệ bo tròn của app,
        // bo 15 nửa vời nhìn "sao sao" đúng như cảm giác
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? Pal.dSurfaceAlt : Pal.surface,
      labelStyle: TextStyle(color: soft),
      helperStyle: TextStyle(color: soft, fontSize: 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: accent, width: 1.6),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      titleTextStyle: GoogleFonts.plusJakartaSans(
        color: ink,
        fontSize: 19,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: accent,
      foregroundColor: onAccent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accent,
        textStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, letterSpacing: -0.1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    // TabBar (quản trị, trang truyện): chỉ thanh indicator chạy, tắt màu lan ra khi bấm
    tabBarTheme: const TabBarThemeData(
      overlayColor: WidgetStatePropertyAll(Colors.transparent),
      splashFactory: NoSplash.splashFactory,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      // nổi lên trên dock (dock cao ~76 + lề 14) để không che menu bar
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      backgroundColor: dark ? Pal.dSurfaceAlt : Pal.ink,
      contentTextStyle: TextStyle(color: dark ? Pal.dInk : Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}

final lightTheme = _build(dark: false);
final darkTheme = _build(dark: true);
