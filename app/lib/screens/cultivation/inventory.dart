import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../cultivation.dart';
import '../../data.dart';
import '../../widgets.dart' show loiDeHieu;
import 'pixel.dart';

// ponytail: cờ toàn cục chống double-tap dùng/trang bị đồ — app 1 user, 1 màn Tu Tiên
// mở cùng lúc; nếu sau này có nhiều màn song song thì chuyển sang state cục bộ.
bool _cultItemBusy = false;

/// 6 slot trang bị GỌN trên 1 hàng: chỉ icon + bonus (đang đeo) hoặc tên loại
/// (trống) — tên món, mô tả đầy đủ nằm ở popup khi tap. Trước là 2 hàng ô to
/// (icon + tên + bonus) chiếm gấp đôi chỗ.
class EquipRow extends ConsumerWidget {
  final Rec st;
  const EquipRow({super.key, required this.st});

  /// Bonus ngắn gọn: công pháp ×N, pháp bảo +N%, pháp chú +N% ĐP, đồ chỉ số +N.
  static String _bonus(Rec it) {
    final e = (it['effect'] as Map?) ?? const {};
    if (e['rate_pct'] != null) return '+${e['rate_pct']}%';
    if (e['bt_pct'] != null) return '+${e['bt_pct']}% ĐP';
    if (e['atk'] != null) return '+${e['atk']} Công';
    if (e['def'] != null) return '+${e['def']} Thủ';
    if (e['agi'] != null) return '+${e['agi']} Thân';
    return '×${const {1: 1.5, 2: 3, 3: 6, 4: 12, 5: 24}[it['grade']] ?? 1}';
  }

  Widget _slot(BuildContext context, WidgetRef ref, String type) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final it = ((st['equipped'] as Rec?) ?? const {})[type] as Rec?;
    final grade = (it?['grade'] as int?) ?? 1;
    final gc = gradeColor(grade);
    return Builder(
      builder: (slotCtx) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: it == null ? null : () => _showItemPopup(slotCtx, ref, it, null),
        child: Container(
          height: 58,
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: it != null
                  ? gc.withValues(alpha: 0.65)
                  : cs.outlineVariant,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              it != null
                  ? PixelIcon(
                      it['pixel'] as String,
                      grade: it['grade'] as int,
                      size: 28,
                    )
                  : Icon(Icons.add_rounded, size: 22, color: cs.outlineVariant),
              const SizedBox(height: 2),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  it != null ? _bonus(it) : cultTypeNames[type]!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: t.labelSmall?.copyWith(
                    fontSize: 8,
                    fontWeight: it != null ? FontWeight.w700 : FontWeight.w500,
                    color: it != null
                        ? gc
                        : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const types = ['congphap', 'vukhi', 'phapbao', 'phapchu', 'yphuc', 'giay'];
    return Row(
      children: [
        for (final type in types) ...[
          Expanded(child: _slot(context, ref, type)),
          if (type != types.last) const SizedBox(width: 6),
        ],
      ],
    );
  }
}

/// Lưới kho đồ: ô nhỏ chỉ icon + số lượng (màu viền = phẩm), đồ ĐANG TRANG BỊ
/// được ẩn (đã hiện ở mục Trang bị); tap → popup nhỏ ngay cạnh ô.
/// Lưới kho đồ: ô nhỏ chỉ icon + số lượng (màu viền = phẩm), đồ ĐANG TRANG BỊ
/// được ẩn (đã hiện ở mục Trang bị); tap → popup nhỏ ngay cạnh ô.
class InventoryGrid extends ConsumerStatefulWidget {
  const InventoryGrid({super.key});

  @override
  ConsumerState<InventoryGrid> createState() => _InventoryGridState();
}

class _InventoryGridState extends ConsumerState<InventoryGrid> {
  String? _selectedType;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final inv = ref.watch(cultInventoryProvider).value ?? const <Rec>[];
    // ẩn món đang đeo — nhìn túi là biết còn gì CHƯA dùng
    final st = ref.watch(cultStateProvider).value;
    final wearing = {
      for (final e in ((st?['equipped'] as Rec?) ?? const {}).values)
        if (e != null) (e as Map)['id'] as int,
    };
    final items = [
      for (final r in inv)
        if (!wearing.contains((r['cult_items'] as Rec)['id'])) r,
    ];
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: Text(
            inv.isEmpty
                ? 'Kho trống — đọc truyện để gặp cơ duyên nhận bảo vật.'
                : 'Bao nhiêu bảo vật đều đã trang bị cả.',
            style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
      );
    }

    final availableTypes = <String>{};
    for (final r in items) {
      final it = r['cult_items'] as Rec;
      final type = it['type'] as String?;
      if (type != null) availableTypes.add(type);
    }

    // quý nhất lên đầu (phẩm cao → nhiều bản), cùng loại đứng cạnh nhau
    int grade(Rec r) => (r['cult_items'] as Rec)['grade'] as int;
    final displayedItems = [
      for (final r in items)
        if (_selectedType == null || (r['cult_items'] as Rec)['type'] == _selectedType) r,
    ]..sort((a, b) {
        final g = grade(b).compareTo(grade(a));
        return g != 0 ? g : (b['qty'] as int).compareTo(a['qty'] as int);
      });
    final hasSpare = items.any((r) => (r['qty'] as int) > 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (availableTypes.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('Tất cả'),
                    selected: _selectedType == null,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => setState(() => _selectedType = null),
                  ),
                  for (final type in availableTypes) ...[
                    const SizedBox(width: 6),
                    ChoiceChip(
                      label: Text(cultTypeNames[type] ?? type),
                      selected: _selectedType == type,
                      visualDensity: VisualDensity.compact,
                      onSelected: (sel) {
                        setState(() {
                          _selectedType = sel ? type : null;
                        });
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        GridView.builder(
          shrinkWrap: true,
          primary: false,
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 6, // khớp 6 cột hàng Trang bị → ô cùng bề rộng
            mainAxisExtent:
                58, // ponytail: khớp chiều cao ô Trang bị (_slot height 58)
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
          ),
          itemCount: displayedItems.length,
          itemBuilder: (context, i) {
            final it = displayedItems[i]['cult_items'] as Rec;
            final qty = displayedItems[i]['qty'] as int;
            final grade = it['grade'] as int;
            final gc = gradeColor(grade);
            // Builder: cần context CỦA Ô để popup neo đúng cạnh ô được bấm
            return Builder(
              builder: (tileCtx) {
                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _showItemPopup(tileCtx, ref, it, qty),
                  child: Container(
                    decoration: BoxDecoration(
                      color: cs.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: gc.withValues(alpha: 0.55),
                      ),
                    ),
                    child: Stack(
                      children: [
                        Center(
                          child: PixelIcon(
                            it['pixel'] as String,
                            grade: grade,
                            size: 32,
                          ),
                        ),
                        if (qty > 1)
                          Positioned(
                            right: 3,
                            bottom: 2,
                            child: Text(
                              '×$qty',
                              style: t.labelSmall?.copyWith(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: gc,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
        if (hasSpare)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _recycleAll(context, items),
              icon: const Icon(Icons.local_fire_department_rounded, size: 16),
              label: const Text('Luyện hóa hàng loạt'),
            ),
          ),
      ],
    );
  }

  /// Chọn phẩm cao nhất được đốt (mặc định an toàn: chỉ đồ thường), thấy trước tu vi nhận được.
  /// Luôn giữ 1 bản mỗi món — server cult_recycle_all (124) cũng chỉ đốt qty-1.
  Future<void> _recycleAll(BuildContext context, List<Rec> items) async {
    final messenger = ScaffoldMessenger.of(context);
    int spare(int gMax) => items.fold(0, (s, r) {
          final g = (r['cult_items'] as Rec)['grade'] as int;
          return g <= gMax ? s + (r['qty'] as int) - 1 : s;
        });
    int gain(int gMax) => items.fold(0, (s, r) {
          final g = (r['cult_items'] as Rec)['grade'] as int;
          return g <= gMax ? s + ((r['qty'] as int) - 1) * cultRecycleGain(g) : s;
        });
    final gMax = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Luyện hóa bản dư'),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text('Mỗi món giữ lại 1 bản. Chọn phẩm cao nhất được luyện:'),
          ),
          for (var g = 1; g <= gradeNames.length; g++)
            if (spare(g) > 0)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, g),
                child: Text(g == 1
                    ? 'Chỉ phẩm ${gradeNames[0]} · ${spare(g)} bản → +${gonSo(gain(g))} tu vi'
                    : '${gradeNames[0]} → ${gradeNames[g - 1]} · ${spare(g)} bản → +${gonSo(gain(g))} tu vi'),
              ),
        ],
      ),
    );
    if (gMax == null) return;
    try {
      final r = await cultRecycleAll(gMax);
      ref.invalidate(cultStateProvider);
      ref.invalidate(cultInventoryProvider);
      messenger.showSnackBar(SnackBar(
          content: Text('Luyện hóa ${r['recycled']} bản → +${gonSo(r['linh_khi'] as num)} tu vi')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(loiDeHieu(e))));
    }
  }
}

/// Popup chi tiết vật phẩm neo NGAY CẠNH ô vừa bấm (thay bottom sheet cũ chiếm
/// cả đáy màn): tên + phẩm + hiệu ứng + mô tả, kèm dòng hành động khi mở từ túi.
/// qty null = mở từ slot đang đeo → chỉ xem.
Future<void> _showItemPopup(
  BuildContext tileCtx,
  WidgetRef ref,
  Rec it,
  int? qty,
) async {
  final cs = Theme.of(tileCtx).colorScheme;
  final t = Theme.of(tileCtx).textTheme;
  final grade = it['grade'] as int;
  // đồ tiêu hao (uống/kích hoạt): đan dược + linh thạch
  final isDan = it['type'] == 'danduoc' || it['type'] == 'linhthach';

  // vị trí ô trên màn → popup mọc từ cạnh ô
  final box = tileCtx.findRenderObject() as RenderBox;
  final overlay = Overlay.of(tileCtx).context.findRenderObject() as RenderBox;
  final rect = RelativeRect.fromRect(
    Rect.fromPoints(
      box.localToGlobal(Offset.zero, ancestor: overlay),
      box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
    ),
    Offset.zero & overlay.size,
  );

  final action = await showMenu<String>(
    context: tileCtx,
    position: rect,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    items: [
      PopupMenuItem(
        enabled: false,
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 216),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  PixelIcon(it['pixel'] as String, grade: grade, size: 30),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          it['name'] as String,
                          style: t.labelLarge?.copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${cultTypeNames[it['type']]} · ${gradeNames[grade - 1]}'
                          '${(qty ?? 0) > 1 ? ' · ×$qty' : ''}',
                          style: t.labelSmall?.copyWith(
                            color: gradeColor(grade),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                cultEffectText(it),
                style: t.labelMedium?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if ((it['descr'] as String?)?.isNotEmpty ?? false) ...[
                const SizedBox(height: 4),
                Text(
                  it['descr'] as String,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
      if (qty != null)
        PopupMenuItem(
          value: 'use',
          height: 40,
          child: Row(
            children: [
              Icon(
                isDan
                    ? Icons.local_drink_rounded
                    : it['type'] == 'congphap'
                    ? Icons.menu_book_rounded
                    : Icons.shield_moon_rounded,
                size: 18,
                color: cs.primary,
              ),
              const SizedBox(width: 8),
              Text(
                isDan
                    ? 'Dùng'
                    : it['type'] == 'congphap'
                    ? 'Tu học'
                    : 'Trang bị',
                style: t.labelLarge?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      // Bản dư (qty > 1) → luyện hóa thành tu vi; luôn chừa 1 bản
      if ((qty ?? 0) > 1)
        PopupMenuItem(
          value: 'recycle',
          height: 40,
          child: Row(
            children: [
              Icon(Icons.auto_awesome_rounded, size: 18, color: cs.tertiary),
              const SizedBox(width: 8),
              Text(
                'Luyện hóa ${qty! - 1} bản (+${cultRecycleGain(grade) * (qty - 1)} tu vi)',
                style: t.labelLarge?.copyWith(
                  color: cs.tertiary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
    ],
  );

  if (action == null) return;
  if (_cultItemBusy) return; // đang xử lý món trước → bỏ qua tap lặp
  _cultItemBusy = true;
  try {
    if (action == 'recycle') {
      final r = await cultRecycle(it['id'] as int);
      if (tileCtx.mounted) {
        ScaffoldMessenger.of(tileCtx).showSnackBar(
          SnackBar(
            content: Text(
              'Luyện hóa ${r['recycled']} bản → +${gonSo(r['linh_khi'] as num)} tu vi',
            ),
          ),
        );
      }
    } else {
      isDan
          ? await cultUseItem(it['id'] as int)
          : await cultEquip(it['id'] as int);
    }
    ref.invalidate(cultStateProvider);
    ref.invalidate(cultInventoryProvider);
  } catch (e) {
    if (tileCtx.mounted) {
      ScaffoldMessenger.of(tileCtx).showSnackBar(SnackBar(content: Text(loiDeHieu(e))));
    }
  } finally {
    _cultItemBusy = false;
  }
}
