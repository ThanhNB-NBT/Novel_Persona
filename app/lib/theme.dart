import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Hệ thiết kế "Thanh Tân" — sáng, trắng lạnh, nhấn XANH DƯƠNG, bo tròn nhiều.
/// Ban đêm dùng bộ "Dạ Lam": nền xanh đêm, nhấn xanh băng.
/// Một họ chữ Plus Jakarta Sans (dấu tiếng Việt chuẩn) + mono cho SỐ LIỆU;
/// phân cấp bằng đậm/cỡ. Tránh trắng/đen tuyền hoàn toàn.
class Pal {
  // sáng — Giấy Dó (2.0): nền giấy ngà, chữ mực nâu, nhấn son trầm
  static const bg = Color(0xFFF3EBDD); // giấy dó
  static const surface = Color(0xFFFAF5EB); // thẻ — giấy mới hơn nền một bậc
  static const surfaceAlt = Color(0xFFE9DFCB);
  static const ink = Color(0xFF2B2118); // mực nâu đen (không đen tuyền)
  static const inkSoft = Color(0xFF6E5A48); // chữ phụ (5,5:1 trên nền giấy)
  static const accent = Color(0xFF9A3B26); // son trầm — chữ giấy trên nút đạt 7:1
  static const accentDeep = Color(0xFF7A2C1A);
  static const accentSoft = Color(0xFFF0DCCD);
  static const gold = Color(0xFFE8913C); // streak / thành tựu (cam ấm) — CHỈ dùng làm NỀN (chữ ink đè lên: 6.6:1)
  static const goldDeep = Color(0xFFB16215); // gold khi làm CHỮ/ICON trên nền sáng (gold gốc chỉ 2.5:1)
  static const ok = Color(0xFF27864D); // thành công / positive (đã thêm, đã lưu…) — chữ trắng đè lên đạt 4.5:1
  static const line = Color(0xFFE2D5BD);
  // son (chu sa) của dấu triện — điểm nhấn cổ phong DUY NHẤT trên khung (GĐ7)
  static const seal = Color(0xFFB8322A);
  static const dSeal = Color(0xFFD0503F);

  // tối — Mực Đêm (2.0): nền mực ấm thay cho xanh đen lạnh, chữ màu giấy
  static const dBg = Color(0xFF14110E);
  static const dSurface = Color(0xFF1C1814);
  static const dSurfaceAlt = Color(0xFF26201A);
  static const dInk = Color(0xFFEDE3CF); // màu giấy
  static const dInkSoft = Color(0xFFA39381);
  static const dAccent = Color(0xFFE39A74); // son pha sáng cho nền tối
  static const dAccentDeep = Color(0xFFC07552);
  static const dAccentSoft = Color(0xFF33221A);
  static const dGold = Color(0xFFF2A65A);
  static const dOk = Color(0xFF3DBE76); // thành công — sáng hơn cho nền tối
  static const dLine = Color(0xFF2E2720);
}

/// Nhịp chuyển động chuẩn — dùng thay cho Duration/Curve rải rác, cho nhất quán.
/// Chỉ animate transform/opacity; motion là gia vị, cắt trước khi thêm.
/// Bo góc thống nhất (GĐ7): khung chỉ dùng 4 bậc này, không tự chế số lẻ.
class Rad {
  static const sm = 10.0; // chip, nút chữ
  static const md = 14.0; // ô nhập, snackbar, thẻ nhỏ
  static const lg = 18.0; // thẻ, menu, FAB
  static const xl = 22.0; // sheet, hộp thoại, thẻ hero
}

class Motion {
  static const fast = Duration(milliseconds: 150); // phản hồi chạm, đổi trạng thái nhỏ
  static const base = Duration(milliseconds: 240); // chuyển cảnh trong khung
  static const slow = Duration(milliseconds: 400); // nhấn mạnh
  static const easeOut = Curves.easeOutCubic;
  static const easeInOut = Curves.easeInOutCubic;
}

/// Plus Jakarta Sans — sans hình học hiện đại, hỗ trợ dấu tiếng Việt.
/// Tiêu đề lớn: đậm + tracking âm cho cảm giác "premium".
TextTheme _text(Color ink, Color soft) {
  TextStyle f(double size, FontWeight w, {double sp = 0, double h = 1.2, Color? c}) =>
      GoogleFonts.plusJakartaSans(
          fontSize: size, fontWeight: w, letterSpacing: sp, height: h, color: c ?? ink);
  // 2.0: tiêu đề lớn dùng chữ có chân (Noto Serif — đủ dấu tiếng Việt), thân chữ giữ sans
  TextStyle serif(double size, {double sp = 0, double h = 1.2}) => GoogleFonts.notoSerif(
      fontSize: size, fontWeight: FontWeight.w700, letterSpacing: sp, height: h, color: ink);
  return TextTheme(
    // bậc hero — khoảnh khắc lớn (brand, tên truyện): cú nhảy rõ so với body
    displayMedium: serif(36, sp: -0.8, h: 1.05),
    displaySmall: serif(29, sp: -0.6, h: 1.1),
    headlineMedium: serif(25, sp: -0.4),
    headlineSmall: serif(20.5, sp: -0.2),
    titleLarge: serif(18, sp: -0.1, h: 1.25),
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

/// Sợi viền ôm mép tấm nổi (hộp thoại/menu/sheet). Nền tối là ánh sáng hắt lên
/// rìa kính; nền sáng thì đổi vai thành nét mảnh cho cạnh dứt khoát.
/// Tấm nổi tự dựng (không qua dialogTheme) gọi [panelRim] để lấy đúng màu này.
Color _rim(bool dark, Color line) => dark
    ? Colors.white.withValues(alpha: 0.16)
    : line.withValues(alpha: 0.75);

/// Bộ màu nhấn người dùng chọn (Tôi → Giao diện, kiểu ColorOS). Chỉ đổi màu NHẤN
/// và triện; giấy/mực/vàng/xanh-ok giữ nguyên để chất giấy dó không đổi.
/// Màu nhấn sáng: chữ giấy (Pal.surface) đè lên phải ≥ 4.5:1. Bản tối pha sáng NHƯNG
/// ngả xám (tông khoáng/mực) — bản rực kiểu 93AEE3 ra xanh 'công nghệ', lạc nền mực ấm.
class Accent {
  final String name;
  final Color accent, deep, soft, seal, dAccent, dSoft, dSeal;
  const Accent(this.name, this.accent, this.deep, this.soft, this.seal,
      this.dAccent, this.dSoft, this.dSeal);
}

const accents = [
  Accent('Son', Pal.accent, Pal.accentDeep, Pal.accentSoft, Pal.seal,
      Pal.dAccent, Pal.dAccentSoft, Pal.dSeal),
  Accent('Ngọc', Color(0xFF2E6B55), Color(0xFF1F4D3D), Color(0xFFD7E6DC), Color(0xFF2F7A5E),
      Color(0xFF8DBBA3), Color(0xFF1A2A23), Color(0xFF4F9A7A)),
  Accent('Chàm', Color(0xFF34508A), Color(0xFF243A68), Color(0xFFDCE2EF), Color(0xFF3A5AA0),
      Color(0xFFA2B1D0), Color(0xFF1E2230), Color(0xFF6A7FB0)),
  Accent('Hoàng', Color(0xFF8A5A12), Color(0xFF6B440A), Color(0xFFF1E1C4), Color(0xFFB0761C),
      Color(0xFFE3B46A), Color(0xFF33281A), Color(0xFFD29A45)),
  Accent('Tử', Color(0xFF6E3A6E), Color(0xFF522A52), Color(0xFFEADAE8), Color(0xFF8A3F86),
      Color(0xFFC6A4C3), Color(0xFF2B1F2A), Color(0xFFA0689C)),
];

/// Màu triện theo bộ màu đang chọn — Seal/Silk đọc qua đây thay vì Pal.seal cứng.
class SealTone extends ThemeExtension<SealTone> {
  final Color seal;
  const SealTone(this.seal);
  @override
  SealTone copyWith({Color? seal}) => SealTone(seal ?? this.seal);
  @override
  SealTone lerp(SealTone? other, double t) =>
      other == null ? this : SealTone(Color.lerp(seal, other.seal, t)!);
}

Color sealColor(BuildContext context) {
  final t = Theme.of(context);
  return t.extension<SealTone>()?.seal ??
      (t.brightness == Brightness.dark ? Pal.dSeal : Pal.seal);
}

final _themes = <(bool, int), ThemeData>{};

/// Theme theo sáng/tối + bộ màu (chỉ số trong [accents]); dựng một lần rồi nhớ.
ThemeData appTheme({required bool dark, int accent = 0}) => _themes.putIfAbsent(
    (dark, accent),
    () => _build(dark: dark, a: accents[accent.clamp(0, accents.length - 1)]));

ThemeData _build({required bool dark, required Accent a}) {
  final bg = dark ? Pal.dBg : Pal.bg;
  final surface = dark ? Pal.dSurface : Pal.surface;
  final ink = dark ? Pal.dInk : Pal.ink;
  final soft = dark ? Pal.dInkSoft : Pal.inkSoft;
  final accent = dark ? a.dAccent : a.accent;
  final ok = dark ? Pal.dOk : Pal.ok;
  final line = dark ? Pal.dLine : Pal.line;
  final onAccent = dark ? const Color(0xFF2A140B) : Pal.surface;

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
    extensions: [SealTone(dark ? a.dSeal : a.seal)],
    colorScheme: ColorScheme(
      brightness: dark ? Brightness.dark : Brightness.light,
      primary: accent,
      onPrimary: onAccent,
      primaryContainer: dark ? a.dSoft : a.soft,
      onPrimaryContainer: dark ? a.dAccent : a.deep,
      secondary: dark ? Pal.dGold : Pal.gold,
      // gold/cam sáng → chữ TỐI mới đủ tương phản (white trên gold tụt dưới AA)
      onSecondary: Pal.ink,
      // nền vàng NHẠT + chữ vàng ĐẬM: dùng cho chip/badge. Đừng lấy `secondary`
      // làm chữ trên nền sáng — gold gốc chỉ 2,5:1.
      secondaryContainer: (dark ? Pal.dGold : Pal.gold).withValues(alpha: 0.14),
      onSecondaryContainer: dark ? Pal.dGold : Pal.goldDeep,
      // tertiary = màu THÀNH CÔNG/positive (đã thêm, đã lưu) — trước phải hardcode xanh
      tertiary: ok,
      onTertiary: Colors.white,
      error: dark ? const Color(0xFFD1544A) : const Color(0xFFCE493F),
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
        borderRadius: BorderRadius.circular(Rad.lg),
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
        // PHẲNG, không hào quang. Đối chiếu ảnh ColorOS 17 thật: nút hành động
        // (FAB xanh lá, nút play xanh dương) đều là khối đặc phẳng, không đổ sáng.
        elevation: 0,
      ),
    ),
    // Chip: trước đây để mặc định Material nên lạc hẳn khỏi hệ pill của app
    // (hộp bo góc + viền xám). Giờ pill như FilledButton/dock, chọn thì nhuộm
    // màu nhấn. Cố ý KHÔNG thêm hào quang: chip lọc đứng thành hàng, mỗi cái
    // phát sáng là rối.
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(),
      side: BorderSide(color: line),
      backgroundColor: Colors.transparent,
      selectedColor: accent.withValues(alpha: dark ? 0.28 : 0.14),
      checkmarkColor: accent,
      labelStyle: GoogleFonts.plusJakartaSans(
          fontSize: 13, fontWeight: FontWeight.w600, color: soft),
      secondaryLabelStyle: GoogleFonts.plusJakartaSans(
          fontSize: 13, fontWeight: FontWeight.w700, color: accent),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      showCheckmark: true,
      elevation: 0,
      pressElevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? Pal.dSurfaceAlt : Pal.surface,
      labelStyle: TextStyle(color: soft),
      // label nổi lên khi focus → nhuộm màu nhấn, form "phản hồi" theo thao tác
      floatingLabelStyle: TextStyle(color: accent, fontWeight: FontWeight.w600),
      hintStyle: TextStyle(color: soft.withValues(alpha: 0.55)),
      prefixIconColor: soft,
      helperStyle: TextStyle(color: soft, fontSize: 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Rad.md),
        borderSide: BorderSide(color: line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Rad.md),
        borderSide: BorderSide(color: line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Rad.md),
        borderSide: BorderSide(color: accent, width: 1.6),
      ),
    ),
    // ---- Contour glow (ColorOS 17) cho HỘP THOẠI / MENU / BOTTOM SHEET ----
    // Đây mới là chỗ của viền phát sáng — KHÔNG phải thanh điều hướng (đối chiếu
    // video thật: thanh menu trơn, không viền sáng, không màu nhấn).
    // Nền tối: sợi trắng mờ ôm mép = ánh sáng hắt lên rìa tấm kính.
    // Nền sáng: tấm nổi trên nền trắng nên "sáng" không đọc được, dùng nét mảnh
    // cho cạnh dứt khoát — cùng vai trò, khác cách thể hiện.
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent, // tắt nhuộm-theo-elevation của M3
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: dark ? 0.6 : 0.22),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Rad.xl),
        side: BorderSide(color: _rim(dark, line), width: 1),
      ),
      titleTextStyle: GoogleFonts.plusJakartaSans(
        color: ink,
        fontSize: 19,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 10,
      shadowColor: Colors.black.withValues(alpha: dark ? 0.6 : 0.22),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Rad.lg),
        side: BorderSide(color: _rim(dark, line), width: 1),
      ),
      textStyle: GoogleFonts.plusJakartaSans(
          color: ink, fontSize: 14, fontWeight: FontWeight.w500),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: dark ? 0.6 : 0.22),
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(Rad.xl)),
        side: BorderSide(color: _rim(dark, line), width: 1),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: accent,
      foregroundColor: onAccent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rad.lg)),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accent,
        textStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, letterSpacing: -0.1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rad.sm)),
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
      // nền snackbar TỐI ở cả 2 theme → action phải là màu nhấn SÁNG; mặc định
      // (inversePrimary) ra chữ tối trên nền tối, nút "Áp cả truyện" tàng hình
      actionTextColor: dark ? a.dAccent : a.soft,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rad.md)),
    ),
  );
}

final lightTheme = appTheme(dark: false);
final darkTheme = appTheme(dark: true);


/// Màu viền contour cho tấm nổi TỰ DỰNG bằng Material/Container — form sửa bản
/// dịch trong trình đọc chẳng hạn, nó không đi qua dialogTheme/bottomSheetTheme.
Color panelRim(BuildContext context) {
  final t = Theme.of(context);
  return _rim(t.brightness == Brightness.dark, t.colorScheme.outlineVariant);
}
