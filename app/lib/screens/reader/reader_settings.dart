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

/// Các font đã Việt hoá, dễ đọc (serif cho đỡ mỏi mắt + vài sans).
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

/// Độ sáng hiệu lực của app: theo Cài đặt app (0=hệ thống→OS, 1=sáng, 2=tối).
/// Reader lấy cái này làm mốc cho chế độ màu "Hệ thống".
Brightness appBrightness(WidgetRef ref, BuildContext context) {
  final mode = ref.watch(appThemeModeProvider);
  final sysDark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
  final dark = switch (mode) { 1 => false, 2 => true, _ => sysDark };
  return dark ? Brightness.dark : Brightness.light;
}

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
    this.fontKey = 'lora',
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
        fontKey: prefs.getString('rd_font') ?? 'lora',
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
    NotifierProvider<ReaderSettingsNotifier, ReaderSettings>(ReaderSettingsNotifier.new);

/// Mở bảng cài đặt đọc (bottom sheet). Cao tối đa 60% màn hình, cuộn trong nếu tràn.
void showReaderSettingsSheet(BuildContext context, WidgetRef ref,
    {VoidCallback? onRetranslate}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Consumer(builder: (context, ref, _) {
      final s = ref.watch(readerSettingsProvider);
      final n = ref.read(readerSettingsProvider.notifier);
      final cs = Theme.of(context).colorScheme;
      final t = Theme.of(context).textTheme;
      final maxH = MediaQuery.of(context).size.height * 0.6;

      Widget label(String x) => Padding(
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 6),
            child: Text(x, style: t.labelSmall),
          );

      // Một ô trong hàng ghép đôi: nhãn nhỏ + widget.
      Widget field(String lbl, Widget child) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(lbl, style: t.labelSmall)),
              child,
            ],
          );

      final col = s.resolve(appBrightness(ref, context));

      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Cài đặt đọc', style: t.headlineSmall),

              label('Chế độ đọc'),
              seg(context, ['Cuộn dọc', 'Lật trang'], s.pageMode ? 1 : 0,
                  (i) => n.update(s.copyWith(pageMode: i == 1))),

              // Màu nền → mở màn phụ (nền sáng/tối + chế độ). Ở đây chỉ 1 hàng gọn.
              label('Màu nền & chế độ'),
              _colorRow(context, col, () {
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const ReaderColorScreen()));
              }),

              // Cỡ chữ + Độ giãn dòng ghép 1 hàng.
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
                            color: s.fontKey == e.key ? cs.primary : cs.surface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: s.fontKey == e.key ? cs.primary : cs.outlineVariant),
                          ),
                          child: Text(e.value,
                              style: readerFontStyle(e.key,
                                  fontSize: 14,
                                  height: 1,
                                  color: s.fontKey == e.key ? cs.onPrimary : cs.onSurface)),
                        ),
                      ),
                    ),
                ]),
              ),

              // Căn lề + Viền 2 bên ghép 1 hàng.
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
            ]),
          ),
        ),
      );
    }),
  );
}

/// Segmented control dùng lại ở cả sheet và màn phụ.
Widget seg(BuildContext context, List<String> labels, int value, ValueChanged<int> onCh) {
  final cs = Theme.of(context).colorScheme;
  final t = Theme.of(context).textTheme;
  return Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant)),
    child: Row(children: [
      for (var i = 0; i < labels.length; i++)
        Expanded(
          child: GestureDetector(
            onTap: () => onCh(i),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 9),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: i == value ? cs.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(labels[i],
                  style: t.labelMedium?.copyWith(
                      color: i == value ? cs.onPrimary : cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600)),
            ),
          ),
        ),
    ]),
  );
}

Widget stepper(BuildContext context, String unit, VoidCallback dec, VoidCallback inc) {
  final t = Theme.of(context).textTheme;
  return Row(children: [
    IconButton.outlined(
        visualDensity: VisualDensity.compact,
        onPressed: dec,
        icon: const Icon(Icons.remove, size: 16)),
    Expanded(child: Center(child: Text(unit, style: t.titleMedium))),
    IconButton.outlined(
        visualDensity: VisualDensity.compact,
        onPressed: inc,
        icon: const Icon(Icons.add, size: 16)),
  ]);
}

/// Hàng "Màu nền & chế độ": xem trước nền/chữ hiện tại + chevron mở màn phụ.
Widget _colorRow(BuildContext context, ReaderColor col, VoidCallback onTap) {
  final cs = Theme.of(context).colorScheme;
  final t = Theme.of(context).textTheme;
  return Material(
    color: cs.surface,
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(children: [
          Container(
            width: 30, height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: col.bg,
              shape: BoxShape.circle,
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Text('A', style: TextStyle(color: col.fg, fontWeight: FontWeight.w700, fontSize: 15)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text('Nền sáng, nền tối, chế độ mặc định', style: t.bodyMedium)),
          Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
        ]),
      ),
    ),
  );
}

/// Màn phụ: chọn nền cho chế độ sáng, nền cho chế độ tối, và chế độ mặc định.
class ReaderColorScreen extends ConsumerWidget {
  const ReaderColorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(readerSettingsProvider);
    final n = ref.read(readerSettingsProvider.notifier);
    final t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Màu nền')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Text('Chế độ mặc định', style: t.labelSmall),
          const SizedBox(height: 8),
          seg(context, ['Hệ thống', 'Sáng', 'Tối'], s.colorMode,
              (i) => n.update(s.copyWith(colorMode: i))),
          const SizedBox(height: 24),
          Text('Nền màn sáng', style: t.labelSmall),
          const SizedBox(height: 10),
          _swatches(context, s.lightColor, (i) => n.update(s.copyWith(lightColor: i))),
          const SizedBox(height: 24),
          Text('Nền màn tối', style: t.labelSmall),
          const SizedBox(height: 10),
          _swatches(context, s.darkColor, (i) => n.update(s.copyWith(darkColor: i))),
        ],
      ),
    );
  }
}

/// Lưới ô màu — chỉ hiển thị màu (chữ "A" xem trước tương phản), không có tên.
Widget _swatches(BuildContext context, int selected, ValueChanged<int> onPick) {
  final cs = Theme.of(context).colorScheme;
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
              shape: BoxShape.circle,
              border: Border.all(
                  color: i == selected ? cs.primary : cs.outlineVariant,
                  width: i == selected ? 2.6 : 1),
            ),
            child: Text('A',
                style: TextStyle(
                    color: readerColors[i].fg, fontSize: 18, fontWeight: FontWeight.w700)),
          ),
        ),
    ],
  );
}
