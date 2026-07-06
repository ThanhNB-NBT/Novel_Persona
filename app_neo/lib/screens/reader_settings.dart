import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data.dart';
import '../neo_theme.dart';

/// Bảng màu nền/chữ khi đọc — sci-fi ở khung, KHÔNG hành hạ mắt người đọc:
/// giữ nguyên bộ màu đọc của app cũ (cùng prefs key nghĩa là cùng index).
class ReaderColor {
  final String name;
  final Color bg, fg;
  const ReaderColor(this.name, this.bg, this.fg);
}

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
  // riêng NEO: nền terminal — thêm CUỐI để không đổi nghĩa index đã lưu
  ReaderColor('NEO', Color(0xFF05070D), Color(0xFFB8C7D9)),
];

const readerFonts = {
  'lora': 'Lora',
  'notoserif': 'Noto Serif',
  'bitter': 'Bitter',
  'merriweather': 'Merriweather',
  'literata': 'Literata',
  'robotoslab': 'Roboto Slab',
  'bevietnam': 'Be Vietnam Pro',
  'jakarta': 'Plus Jakarta Sans',
  'nunitosans': 'Nunito Sans',
  'sarabun': 'Sarabun',
};

TextStyle readerFontStyle(String key,
    {required double fontSize, required double height, required Color color}) {
  final f = switch (key) {
    'notoserif' => GoogleFonts.notoSerif,
    'bitter' => GoogleFonts.bitter,
    'merriweather' => GoogleFonts.merriweather,
    'literata' => GoogleFonts.literata,
    'robotoslab' => GoogleFonts.robotoSlab,
    'bevietnam' => GoogleFonts.beVietnamPro,
    'jakarta' => GoogleFonts.plusJakartaSans,
    'nunitosans' => GoogleFonts.nunitoSans,
    'sarabun' => GoogleFonts.sarabun,
    _ => GoogleFonts.lora,
  };
  return f(fontSize: fontSize, height: height, color: color);
}

class ReaderSettings {
  final double fontSize;
  final String fontKey;
  final int lightColor;
  final int darkColor;
  final int colorMode; // 0 = hệ thống, 1 = sáng, 2 = tối
  final bool justify;
  final double lineHeight;
  final double sideMargin;
  final bool pageMode;

  const ReaderSettings({
    this.fontSize = 18,
    this.fontKey = 'lora',
    this.lightColor = 0,
    this.darkColor = 13, // NEO mặc định nền terminal
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
  }) =>
      ReaderSettings(
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

/// App NEO dark-first: chế độ "hệ thống" của reader coi app là tối
/// (chế độ sáng của app là chuyện Phase 5).
Brightness appBrightness(WidgetRef ref, BuildContext context) => Brightness.dark;

class ReaderSettingsNotifier extends Notifier<ReaderSettings> {
  @override
  ReaderSettings build() => ReaderSettings(
        fontSize: prefs.getDouble('rd_size') ?? 18,
        fontKey: prefs.getString('rd_font') ?? 'lora',
        lightColor: prefs.getInt('rd_light') ?? 0,
        darkColor: prefs.getInt('rd_dark') ?? 13,
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
    NotifierProvider<ReaderSettingsNotifier, ReaderSettings>(ReaderSettingsNotifier.new);

/// Bảng cài đặt đọc (bottom sheet HUD).
void showReaderSettingsSheet(BuildContext context, WidgetRef ref,
    {VoidCallback? onRetranslate}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Neo.surface,
    shape: const Border(top: BorderSide(color: Neo.cyan, width: 1)),
    builder: (_) => Consumer(builder: (context, ref, _) {
      final s = ref.watch(readerSettingsProvider);
      final n = ref.read(readerSettingsProvider.notifier);
      final maxH = MediaQuery.of(context).size.height * 0.6;

      Widget label(String x) => Padding(
            padding: const EdgeInsets.fromLTRB(0, 14, 0, 6),
            child: Text(x.toUpperCase(), style: Neo.mono(9, spacing: 3)),
          );

      Widget field(String lbl, Widget child) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(lbl.toUpperCase(), style: Neo.mono(9, spacing: 2))),
              child,
            ],
          );

      final col = s.resolve(appBrightness(ref, context));

      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('// CÀI ĐẶT ĐỌC',
                      style: Neo.mono(13, color: Neo.cyan, weight: FontWeight.w700, spacing: 2)),

                  label('Chế độ đọc'),
                  seg(context, ['Cuộn dọc', 'Lật trang'], s.pageMode ? 1 : 0,
                      (i) => n.update(s.copyWith(pageMode: i == 1))),

                  label('Màu nền & chế độ'),
                  _colorRow(context, col, () {
                    Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const ReaderColorScreen()));
                  }),

                  const SizedBox(height: 12),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: field('Cỡ chữ (${s.fontSize.round()})',
                          stepper(context, '${s.fontSize.round()}',
                              () => n.update(s.copyWith(fontSize: (s.fontSize - 1).clamp(15, 28))),
                              () => n.update(s.copyWith(fontSize: (s.fontSize + 1).clamp(15, 28))))),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: field('Giãn dòng (${s.lineHeight.toStringAsFixed(1)})',
                          stepper(context, '${s.lineHeight.toStringAsFixed(1)}×',
                              () => n.update(s.copyWith(lineHeight: (s.lineHeight - 0.1).clamp(1.3, 2.2))),
                              () => n.update(s.copyWith(lineHeight: (s.lineHeight + 0.1).clamp(1.3, 2.2))))),
                    ),
                  ]),

                  label('Font chữ'),
                  SizedBox(
                    height: 36,
                    child: ListView(scrollDirection: Axis.horizontal, children: [
                      for (final e in readerFonts.entries)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () => n.update(s.copyWith(fontKey: e.key)),
                            child: Container(
                              alignment: Alignment.center,
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              decoration: BoxDecoration(
                                color: s.fontKey == e.key
                                    ? Neo.cyan.withValues(alpha: 0.12)
                                    : Neo.surface2,
                                border: Border.all(
                                    color: s.fontKey == e.key ? Neo.cyan : Neo.faint),
                              ),
                              child: Text(e.value,
                                  style: readerFontStyle(e.key,
                                      fontSize: 14,
                                      height: 1,
                                      color: s.fontKey == e.key ? Neo.cyan : Neo.text)),
                            ),
                          ),
                        ),
                    ]),
                  ),

                  const SizedBox(height: 12),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: field('Căn lề',
                          seg(context, ['Trái', 'Đều'], s.justify ? 1 : 0,
                              (i) => n.update(s.copyWith(justify: i == 1)))),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: field('Viền 2 bên (${s.sideMargin.round()})',
                          stepper(context, '${s.sideMargin.round()}',
                              () => n.update(s.copyWith(sideMargin: (s.sideMargin - 4).clamp(8, 48))),
                              () => n.update(s.copyWith(sideMargin: (s.sideMargin + 4).clamp(8, 48))))),
                    ),
                  ]),

                  if (onRetranslate != null) ...[
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Neo.plasma,
                          side: const BorderSide(color: Neo.plasma),
                          shape: const RoundedRectangleBorder(),
                        ),
                        icon: const Icon(Icons.refresh, size: 18),
                        label: Text('DỊCH LẠI CHƯƠNG NÀY', style: Neo.mono(11, color: Neo.plasma, spacing: 2)),
                        onPressed: () {
                          Navigator.pop(context);
                          onRetranslate();
                        },
                      ),
                    ),
                  ],
                ]),
          ),
        ),
      );
    }),
  );
}

/// Segmented control HUD.
Widget seg(BuildContext context, List<String> labels, int value, ValueChanged<int> onCh) {
  return Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
        color: Neo.surface2, border: Border.all(color: Neo.faint)),
    child: Row(children: [
      for (var i = 0; i < labels.length; i++)
        Expanded(
          child: GestureDetector(
            onTap: () => onCh(i),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              alignment: Alignment.center,
              color: i == value ? Neo.cyan.withValues(alpha: 0.15) : Colors.transparent,
              child: Text(labels[i].toUpperCase(),
                  style: Neo.mono(10,
                      color: i == value ? Neo.cyan : Neo.dim,
                      weight: FontWeight.w600, spacing: 1)),
            ),
          ),
        ),
    ]),
  );
}

Widget stepper(BuildContext context, String unit, VoidCallback dec, VoidCallback inc) {
  Widget btn(IconData ic, VoidCallback f) => InkWell(
        onTap: f,
        child: Container(
          width: 32, height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(border: Border.all(color: Neo.faint), color: Neo.surface2),
          child: Icon(ic, size: 15, color: Neo.text),
        ),
      );
  return Row(children: [
    btn(Icons.remove, dec),
    Expanded(child: Center(child: Text(unit, style: Neo.mono(14, color: Neo.cyan)))),
    btn(Icons.add, inc),
  ]);
}

Widget _colorRow(BuildContext context, ReaderColor col, VoidCallback onTap) {
  return InkWell(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: Neo.surface2, border: Border.all(color: Neo.faint)),
      child: Row(children: [
        Container(
          width: 30, height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: col.bg,
            border: Border.all(color: Neo.faint),
          ),
          child: Text('A',
              style: TextStyle(color: col.fg, fontWeight: FontWeight.w700, fontSize: 15)),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text('NỀN SÁNG · NỀN TỐI · CHẾ ĐỘ', style: Neo.mono(10, spacing: 1.5))),
        const Icon(Icons.chevron_right, color: Neo.dim),
      ]),
    ),
  );
}

/// Màn phụ chọn màu nền.
class ReaderColorScreen extends ConsumerWidget {
  const ReaderColorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(readerSettingsProvider);
    final n = ref.read(readerSettingsProvider.notifier);

    Widget label(String x) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(x.toUpperCase(), style: Neo.mono(9, spacing: 3)),
        );

    return Scaffold(
      backgroundColor: Neo.bg,
      appBar: AppBar(
        backgroundColor: Neo.bg,
        foregroundColor: Neo.text,
        title: Text('MÀU NỀN', style: Neo.mono(13, color: Neo.text, weight: FontWeight.w700, spacing: 2)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          label('Chế độ mặc định'),
          seg(context, ['Hệ thống', 'Sáng', 'Tối'], s.colorMode,
              (i) => n.update(s.copyWith(colorMode: i))),
          const SizedBox(height: 24),
          label('Nền màn sáng'),
          _swatches(s.lightColor, (i) => n.update(s.copyWith(lightColor: i))),
          const SizedBox(height: 24),
          label('Nền màn tối'),
          _swatches(s.darkColor, (i) => n.update(s.copyWith(darkColor: i))),
        ],
      ),
    );
  }
}

Widget _swatches(int selected, ValueChanged<int> onPick) {
  return Wrap(
    spacing: 14, runSpacing: 14,
    children: [
      for (var i = 0; i < readerColors.length; i++)
        GestureDetector(
          onTap: () => onPick(i),
          child: Container(
            width: 46, height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: readerColors[i].bg,
              border: Border.all(
                  color: i == selected ? Neo.cyan : Neo.faint,
                  width: i == selected ? 2 : 1),
              boxShadow: i == selected ? Neo.glow(Neo.cyan, blur: 12, alpha: 0.35) : null,
            ),
            child: Text('A',
                style: TextStyle(
                    color: readerColors[i].fg, fontSize: 18, fontWeight: FontWeight.w700)),
          ),
        ),
    ],
  );
}
