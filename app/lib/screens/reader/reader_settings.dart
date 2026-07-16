import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../data.dart';

/// Bảng màu nền/chữ khi đọc.
class ReaderColor {
  final String name;
  final Color bg, fg;
  const ReaderColor(this.name, this.bg, this.fg);
}

// Mới thêm ở CUỐI danh sách để index đã lưu (rd_light/rd_dark) không đổi nghĩa.
const readerColors = [
  ReaderColor('Sáng', Color(0xFFFAF6EF), Color(0xFF2B2620)),
  ReaderColor('Trắng', Color(0xFFFFFFFF), Color(0xFF1F1F1F)),
  ReaderColor('Sepia', Color(0xFFF1E4CB), Color(0xFF4A3B28)),
  ReaderColor('Xanh dịu', Color(0xFFE0EBE1), Color(0xFF23312A)),
  ReaderColor('Xám', Color(0xFFE9E9EC), Color(0xFF2A2A2E)),
  ReaderColor('Tối', Color(0xFF181A1B), Color(0xFFCAC7BF)),
  ReaderColor('Đen', Color(0xFF0B0B0C), Color(0xFFB4B4B6)),
  ReaderColor('Kem', Color(0xFFF3ECDD), Color(0xFF3E3524)),
  ReaderColor('Hồng phấn', Color(0xFFF7EAEA), Color(0xFF4A3335)),
  ReaderColor('Vàng nhạt', Color(0xFFF8F1D8), Color(0xFF443E27)),
  ReaderColor('Bạc hà', Color(0xFFE4EFEA), Color(0xFF213330)),
  ReaderColor('Dạ Lam', Color(0xFF0F151E), Color(0xFFBEC6D1)),
  ReaderColor('Nâu trầm', Color(0xFF1B1611), Color(0xFFCDBDA7)),
];

/// Các font đã Việt hoá, dễ đọc — TOÀN sans (user bỏ serif 2026-07-16).
/// Key cũ (lora/serif…) đã xoá: notifier fallback về 'bevietnam' khi gặp key lạ.
const readerFonts = {
  'bevietnam': 'Be Vietnam Pro',
  'jakarta': 'Plus Jakarta Sans',
  'inter': 'Inter',
  'manrope': 'Manrope',
  'nunitosans': 'Nunito Sans',
  'mulish': 'Mulish',
  'sarabun': 'Sarabun',
  'lexend': 'Lexend',
  'opensans': 'Open Sans',
  'notosans': 'Noto Sans',
  'montserrat': 'Montserrat',
  'worksans': 'Work Sans',
  'quicksand': 'Quicksand',
};

/// Độ sáng hiệu lực của app: theo Cài đặt app (0=hệ thống→OS, 1=sáng, 2=tối).
/// Reader lấy cái này làm mốc cho chế độ màu "Hệ thống".
Brightness appBrightness(WidgetRef ref, BuildContext context) {
  final mode = ref.watch(appThemeModeProvider);
  final sysDark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
  final dark = switch (mode) {
    1 => false,
    2 => true,
    _ => sysDark,
  };
  return dark ? Brightness.dark : Brightness.light;
}

TextStyle readerFontStyle(
  String key, {
  required double fontSize,
  required double height,
  required Color color,
}) {
  final f = switch (key) {
    'jakarta' => GoogleFonts.plusJakartaSans,
    'inter' => GoogleFonts.inter,
    'manrope' => GoogleFonts.manrope,
    'nunitosans' => GoogleFonts.nunitoSans,
    'mulish' => GoogleFonts.mulish,
    'sarabun' => GoogleFonts.sarabun,
    'lexend' => GoogleFonts.lexend,
    'opensans' => GoogleFonts.openSans,
    'notosans' => GoogleFonts.notoSans,
    'montserrat' => GoogleFonts.montserrat,
    'worksans' => GoogleFonts.workSans,
    'quicksand' => GoogleFonts.quicksand,
    _ => GoogleFonts.beVietnamPro, // gồm key serif cũ đã bỏ
  };
  return f(fontSize: fontSize, height: height, color: color);
}

class ReaderSettings {
  final double fontSize; // 15..28
  final String fontKey;
  final int lightColor; // index readerColors dùng cho nền sáng
  final int darkColor; // index readerColors dùng cho nền tối
  final int colorMode; // 0 = hệ thống, 1 = sáng, 2 = tối
  final bool justify; // true = đều 2 bên
  final double lineHeight; // 1.3..2.2
  final double sideMargin; // 8..48
  final bool pageMode; // true = lật trang, false = cuộn dọc

  const ReaderSettings({
    this.fontSize = 18,
    this.fontKey = 'bevietnam',
    this.lightColor = 0,
    this.darkColor = 5,
    this.colorMode = 0,
    this.justify = true,
    this.lineHeight = 1.7,
    this.sideMargin = 20,
    this.pageMode = false,
  });

  ReaderSettings copyWith({
    double? fontSize,
    String? fontKey,
    int? lightColor,
    int? darkColor,
    int? colorMode,
    bool? justify,
    double? lineHeight,
    double? sideMargin,
    bool? pageMode,
  }) => ReaderSettings(
    fontSize: fontSize ?? this.fontSize,
    fontKey: fontKey ?? this.fontKey,
    lightColor: lightColor ?? this.lightColor,
    darkColor: darkColor ?? this.darkColor,
    colorMode: colorMode ?? this.colorMode,
    justify: justify ?? this.justify,
    lineHeight: lineHeight ?? this.lineHeight,
    sideMargin: sideMargin ?? this.sideMargin,
    pageMode: pageMode ?? this.pageMode,
  );

  /// Màu nền/chữ đã giải quyết: chế độ quyết định lấy nền sáng hay tối,
  /// "hệ thống" theo độ sáng máy.
  ReaderColor resolve(Brightness sys) {
    final dark = switch (colorMode) {
      1 => false,
      2 => true,
      _ => sys == Brightness.dark,
    };
    final i = (dark ? darkColor : lightColor).clamp(0, readerColors.length - 1);
    return readerColors[i];
  }
}

class ReaderSettingsNotifier extends Notifier<ReaderSettings> {
  @override
  ReaderSettings build() => ReaderSettings(
    fontSize: prefs.getDouble('rd_size') ?? 18,
    // key đã lưu có thể là serif cũ đã xoá → về mặc định cho chip chọn font khớp
    fontKey: readerFonts.containsKey(prefs.getString('rd_font'))
        ? prefs.getString('rd_font')!
        : 'bevietnam',
    lightColor: prefs.getInt('rd_light') ?? 0,
    darkColor: prefs.getInt('rd_dark') ?? 5,
    colorMode: prefs.getInt('rd_mode') ?? 0,
    justify: prefs.getBool('rd_justify') ?? true,
    lineHeight: prefs.getDouble('rd_lh') ?? 1.7,
    sideMargin: prefs.getDouble('rd_margin') ?? 20,
    pageMode: prefs.getBool('rd_page') ?? false,
  );

  void _save() {
    prefs.setDouble('rd_size', state.fontSize);
    prefs.setString('rd_font', state.fontKey);
    prefs.setInt('rd_light', state.lightColor);
    prefs.setInt('rd_dark', state.darkColor);
    prefs.setInt('rd_mode', state.colorMode);
    prefs.setBool('rd_justify', state.justify);
    prefs.setDouble('rd_lh', state.lineHeight);
    prefs.setDouble('rd_margin', state.sideMargin);
    prefs.setBool('rd_page', state.pageMode);
  }

  void update(ReaderSettings s) {
    state = s;
    _save();
  }
}

final readerSettingsProvider =
    NotifierProvider<ReaderSettingsNotifier, ReaderSettings>(
      ReaderSettingsNotifier.new,
    );

/// Mở bảng cài đặt đọc (bottom sheet). Điểm nhấn: KHUNG XEM TRƯỚC trang đọc thật
/// ở đầu sheet — mọi chỉnh (font/cỡ/giãn/màu/lề) thấy ngay trên đó, không phải
/// đóng sheet ra xem. Màu chỉnh INLINE theo chế độ đang hiệu lực (đổi chế độ ở
/// segment là chuyển sang chỉnh nền của chế độ đó).
void showReaderSettingsSheet(
  BuildContext context,
  WidgetRef ref, {
  VoidCallback? onRetranslate,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Consumer(
      builder: (context, ref, _) {
        final s = ref.watch(readerSettingsProvider);
        final n = ref.read(readerSettingsProvider.notifier);
        final cs = Theme.of(context).colorScheme;
        final t = Theme.of(context).textTheme;
        final maxH = MediaQuery.sizeOf(context).height * 0.72;
        final col = s.resolve(appBrightness(ref, context));
        // Swatch strip chỉnh nền của chế độ ĐANG hiệu lực — thấy ngay trên preview.
        final editingDark = switch (s.colorMode) {
          1 => false,
          2 => true,
          _ => appBrightness(ref, context) == Brightness.dark,
        };

        Widget label(String x, [String? hint]) => Padding(
          padding: const EdgeInsets.fromLTRB(2, 14, 0, 8),
          child: Row(children: [
            Text(x.toUpperCase(),
                style: t.labelSmall?.copyWith(
                    letterSpacing: 1.2, color: cs.primary,
                    fontWeight: FontWeight.w700)),
            if (hint != null) ...[
              const SizedBox(width: 8),
              Expanded(
                child: Text(hint,
                    style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
          ]),
        );

        // Slider gọn: nhãn + giá trị mono cùng hàng, track mảnh.
        Widget slider(String lbl, String value, double v, double min, double max,
                int divisions, ValueChanged<double> onCh) =>
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(children: [
                SizedBox(
                    width: 86,
                    child: Text(lbl,
                        style: t.labelMedium?.copyWith(color: cs.onSurfaceVariant))),
                Expanded(
                  child: SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 3,
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                    ),
                    child: Slider(
                      value: v, min: min, max: max, divisions: divisions,
                      onChanged: onCh,
                    ),
                  ),
                ),
                SizedBox(
                    width: 40,
                    child: Text(value,
                        textAlign: TextAlign.right,
                        style: t.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()]))),
              ]),
            );

        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tiêu đề + chế độ đọc chung một hàng cho sheet mở màn là vào việc.
                  Row(children: [
                    Text('Cài đặt đọc', style: t.titleLarge),
                    const Spacer(),
                    SizedBox(
                      width: 172,
                      child: seg(
                        context,
                        ['Cuộn', 'Lật trang'],
                        s.pageMode ? 1 : 0,
                        (i) => n.update(s.copyWith(pageMode: i == 1)),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),

                  // ===== SIGNATURE: trang đọc thu nhỏ, phản chiếu MỌI cài đặt =====
                  _PreviewCard(s: s, col: col),

                  label('Màu nền', editingDark ? 'đang chỉnh nền tối' : 'đang chỉnh nền sáng'),
                  Row(children: [
                    SizedBox(
                      width: 150,
                      child: seg(
                        context,
                        ['Auto', 'Sáng', 'Tối'],
                        s.colorMode,
                        (i) => n.update(s.copyWith(colorMode: i)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: 38,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            for (var i = 0; i < readerColors.length; i++)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: _Swatch(
                                  color: readerColors[i],
                                  selected:
                                      i == (editingDark ? s.darkColor : s.lightColor),
                                  onTap: () => n.update(editingDark
                                      ? s.copyWith(darkColor: i)
                                      : s.copyWith(lightColor: i)),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ]),

                  label('Chữ'),
                  SizedBox(
                    height: 38,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final e in readerFonts.entries)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            // chip tự vẽ: nền nhấn NHẠT + viền primary khi chọn —
                            // ChoiceChip mặc định nền đặc quá chói giữa sheet dịu
                            child: GestureDetector(
                              onTap: () => n.update(s.copyWith(fontKey: e.key)),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                alignment: Alignment.center,
                                padding: const EdgeInsets.symmetric(horizontal: 14),
                                decoration: BoxDecoration(
                                  color: s.fontKey == e.key
                                      ? cs.primary.withValues(alpha: 0.10)
                                      : cs.surface,
                                  borderRadius: BorderRadius.circular(19),
                                  border: Border.all(
                                    color: s.fontKey == e.key
                                        ? cs.primary.withValues(alpha: 0.65)
                                        : cs.outlineVariant,
                                    width: s.fontKey == e.key ? 1.4 : 1,
                                  ),
                                ),
                                child: Text(
                                  e.value,
                                  style: readerFontStyle(
                                    e.key,
                                    fontSize: 13.5,
                                    height: 1,
                                    color: s.fontKey == e.key
                                        ? cs.primary
                                        : cs.onSurface,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  slider('Cỡ chữ', '${s.fontSize.round()}', s.fontSize, 15, 28, 13,
                      (v) => n.update(s.copyWith(fontSize: v))),
                  slider('Giãn dòng', '${s.lineHeight.toStringAsFixed(1)}×',
                      s.lineHeight, 1.3, 2.2, 9,
                      (v) => n.update(s.copyWith(
                          lineHeight: (v * 10).roundToDouble() / 10))),
                  slider('Viền 2 bên', '${s.sideMargin.round()}', s.sideMargin, 8, 48,
                      10, (v) => n.update(s.copyWith(sideMargin: v))),
                  Row(children: [
                    SizedBox(
                        width: 86,
                        child: Text('Căn lề',
                            style:
                                t.labelMedium?.copyWith(color: cs.onSurfaceVariant))),
                    Expanded(
                      child: seg(
                        context,
                        ['Trái', 'Đều 2 bên'],
                        s.justify ? 1 : 0,
                        (i) => n.update(s.copyWith(justify: i == 1)),
                      ),
                    ),
                  ]),

                  if (onRetranslate != null) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Dịch lại chương này'),
                        onPressed: () {
                          Navigator.pop(context);
                          onRetranslate();
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

/// Trang đọc thu nhỏ: nền/chữ/font/cỡ/giãn/lề đều là giá trị THẬT đang chọn.
class _PreviewCard extends StatelessWidget {
  final ReaderSettings s;
  final ReaderColor col;
  const _PreviewCard({required this.s, required this.col});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: col.bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
      ),
      // lề ngang = đúng sideMargin đang chọn (chia 1.6 vì khung nhỏ hơn màn thật)
      padding: EdgeInsets.fromLTRB(s.sideMargin / 1.6, 12, s.sideMargin / 1.6, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          'Lục Trầm khẽ nhắm mắt, linh khí quanh thân tụ lại như sương sớm. '
          '“Đạo hữu, mời.”',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          textAlign: s.justify ? TextAlign.justify : TextAlign.left,
          style: readerFontStyle(
            s.fontKey,
            fontSize: s.fontSize,
            height: s.lineHeight,
            color: col.fg,
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Text(col.name,
              style: TextStyle(
                  fontSize: 10.5,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w600,
                  color: col.fg.withValues(alpha: 0.45))),
          const Spacer(),
          Text('${readerFonts[s.fontKey]} · ${s.fontSize.round()}',
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: col.fg.withValues(alpha: 0.45))),
        ]),
      ]),
    );
  }
}

/// Ô màu tròn nhỏ trong strip inline — chữ "A" xem trước tương phản.
class _Swatch extends StatelessWidget {
  final ReaderColor color;
  final bool selected;
  final VoidCallback onTap;
  const _Swatch({required this.color, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.bg,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? cs.primary : cs.outlineVariant,
            width: selected ? 2.4 : 1,
          ),
        ),
        child: Text('A',
            style: TextStyle(
                color: color.fg, fontSize: 14, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

/// Segmented control dùng lại ở cả sheet và màn phụ.
Widget seg(
  BuildContext context,
  List<String> labels,
  int value,
  ValueChanged<int> onCh,
) {
  final cs = Theme.of(context).colorScheme;
  final t = Theme.of(context).textTheme;
  // nang chọn TRƯỢT giữa các ô — đồng bộ với _Segmented bên Cài đặt app
  return Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: cs.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: cs.outlineVariant),
    ),
    child: SizedBox(
      height: 34,
      child: Stack(children: [
        AnimatedAlign(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: Alignment(
              labels.length == 1 ? 0 : -1 + 2 * value / (labels.length - 1), 0),
          child: FractionallySizedBox(
            widthFactor: 1 / labels.length,
            heightFactor: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: cs.primary,
                borderRadius: BorderRadius.circular(9),
              ),
            ),
          ),
        ),
        Row(children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onCh(i),
                behavior: HitTestBehavior.opaque,
                child: Center(
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    style: t.labelMedium!.copyWith(
                      color: i == value ? cs.onPrimary : cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                    child: Text(labels[i]),
                  ),
                ),
              ),
            ),
        ]),
      ]),
    ),
  );
}
