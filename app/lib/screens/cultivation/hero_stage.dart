import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../cultivation.dart';
import '../../data.dart';
import 'pixel.dart';
import 'preview.dart';

/// Pill "tầng N" nhỏ cạnh tên cảnh giới. Nền kính surface đậm (không tô rc)
/// vì trời phía sau giờ CÙNG màu cảnh giới — rc trên rc là chìm nghỉm.
Widget _tangPill(BuildContext context, int stage, Color rc) {
  final cs = Theme.of(context).colorScheme;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: cs.surface.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: rc.withValues(alpha: 0.65)),
      boxShadow: [BoxShadow(color: rc.withValues(alpha: 0.30), blurRadius: 10)],
    ),
    child: Text(
      'Tầng $stage',
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: rc,
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.2,
      ),
    ),
  );
}

/// Sân khấu nhân vật tràn viền (hero stage): trời loang màu cảnh giới, cảnh
/// tu luyện phóng to ~2x bản card cũ, tên cảnh giới chữ lớn phát quang neo
/// đáy — không khung, không viền, hoà thẳng vào nền màn hình.
class HeroStage extends ConsumerWidget {
  final Rec st;
  final double topPad; // chiều cao status bar — trời loang phủ luôn dải này
  const HeroStage({super.key, required this.st, this.topPad = 0});

  /// Sheet admin: đổi tộc/giới tính tự do (server chỉ cho profiles.is_admin).
  void _avatarSheet(BuildContext context, WidgetRef ref) {
    var gender = (st['gender'] as String?) ?? 'nam';
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text(
              'Đổi dung mạo (admin)',
              style: Theme.of(
                ctx,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            SegmentedButton<String>(
              segments: [
                for (final g in genderNames.keys)
                  ButtonSegment(value: g, label: Text(genderNames[g]!)),
              ],
              selected: {gender},
              onSelectionChanged: (s) => setSheet(() => gender = s.first),
            ),
            const SizedBox(height: 6),
            for (final r in raceNames.keys)
              ListTile(
                dense: true,
                title: Text(raceNames[r]!),
                selected: r == st['race'],
                trailing: r == st['race']
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () async {
                  final messenger = ScaffoldMessenger.of(ctx);
                  final nav = Navigator.of(ctx);
                  try {
                    await cultSetAvatar(r, gender);
                    ref.invalidate(cultStateProvider);
                    nav.pop();
                  } catch (e) {
                    messenger.showSnackBar(SnackBar(content: Text('$e')));
                  }
                },
              ),
            // Công cụ test bậc — CHỈ trong debug build (flutter run), để soi hiệu ứng
            if (kDebugMode) ...[
              const Divider(height: 24),
              Text(
                'DEV · test hiệu ứng bậc',
                style: Theme.of(ctx).textTheme.labelLarge?.copyWith(
                  color: Theme.of(ctx).colorScheme.tertiary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _devChip(ctx, ref, 'Về Luyện Khí 1', 1, 1),
                  _devChip(
                    ctx,
                    ref,
                    'Đầy tu vi bậc này',
                    st['realm'] as int,
                    st['stage'] as int,
                  ),
                  _devChip(
                    ctx,
                    ref,
                    'Sẵn sàng đại cảnh giới',
                    st['realm'] as int,
                    9,
                  ),
                  _devChip(ctx, ref, 'Độ Kiếp 9 (Phi Thăng)', 9, 9),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 1 nút DEV: set realm/stage + đầy tu vi rồi refetch state (không đóng sheet
  /// để bấm liên tiếp). Chỉ dựng khi kDebugMode.
  Widget _devChip(
    BuildContext ctx,
    WidgetRef ref,
    String label,
    int realm,
    int stage,
  ) {
    return ActionChip(
      label: Text(label),
      onPressed: () async {
        final messenger = ScaffoldMessenger.of(ctx);
        try {
          await cultDebugSet(realm, stage);
          ref.invalidate(cultStateProvider);
          messenger.showSnackBar(
            SnackBar(content: Text('Đã đặt: cảnh giới $realm · tầng $stage')),
          );
        } catch (e) {
          messenger.showSnackBar(SnackBar(content: Text('$e')));
        }
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final realm = st['realm'] as int;
    final rc = gradeColor((realm + 1) ~/ 2);
    final isAdmin = ref.watch(isAdminProvider).value ?? false;
    // hậu Phi Thăng: hiện cấp bậc tiên thay cảnh giới + đạo hiệu cõi tiên + hào quang vàng
    final ascended = st['ascended_at'] != null;
    final tienTier = (st['tien_tier'] as num?)?.toInt() ?? 0;

    return SizedBox(
      height: 372 + topPad,
      width: double.infinity,
      child: Stack(
        children: [
          // cảnh nhân vật (halo + bóng chân + sương + người) phóng to theo khung;
          // truyền đồ ĐANG ĐEO có hiển thị: vòng sáng (pháp bảo halo) + vũ khí
          Positioned.fill(
            top: topPad,
            bottom: 62,
            child: FittedBox(
              fit: BoxFit.contain,
              child: Builder(
                builder: (_) {
                  final eq = (st['equipped'] as Rec?) ?? const {};
                  return AnimatedCultivator(
                    realm: realm,
                    race: st['race'] as String?,
                    gender: st['gender'] as String?,
                    cpCode: eq['congphap']?['code'] as String?,
                    cpElem: eq['congphap']?['effect']?['element'] as String?,
                    element: st['element'] as String?,
                    elements: (st['elements'] as List?)?.cast<String>() ?? const [],
                    halo: eq['phapbao']?['effect']?['halo'] as String?,
                    weaponSprite: eq['vukhi']?['pixel'] as String?,
                    phapbaoSprite: eq['phapbao']?['pixel'] as String?,
                    tienTier: ascended ? tienTier : -1,
                    haloWorn: st['halo_worn'] as String?,
                  );
                },
              ),
            ),
          ),
          // tên cảnh giới + tầng + đạo hiệu — neo đáy, căn giữa
          Positioned(
            left: 16,
            right: 16,
            bottom: 0,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  // căn đáy → pill nằm ngang chân chữ thay vì giữa dòng
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Flexible(
                      child: Text(
                        ascended ? tienTierNames[tienTier] : realmNames[realm - 1],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        // Agbalumo: display bo tròn đậm, có dấu tiếng Việt (Đ)
                        style: GoogleFonts.agbalumo(
                          textStyle: t.headlineMedium,
                          fontSize: 32,
                          letterSpacing: 0.5,
                          color: cs.onSurface,
                          // viền sáng surface ôm chữ cho TƯƠNG PHẢN, vòng ngoài
                          // là quầng phát quang màu cảnh giới
                          shadows: [
                            Shadow(color: cs.surface, blurRadius: 8),
                            Shadow(color: cs.surface, blurRadius: 8),
                            Shadow(
                              color: rc.withValues(alpha: 0.5),
                              blurRadius: 18,
                            ),
                          ],
                        ),
                      ),
                    ),
                    // hậu phi thăng vượt khỏi "tầng" → ẩn pill, tên bậc tiên đã đủ
                    if (!ascended) ...[
                      const SizedBox(width: 10),
                      // nhấc pill lên chút cho khớp chân chữ (line-box cao hơn baseline)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: _tangPill(context, st['stage'] as int, rc),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '「${ascended ? tienDaoTitles[tienTier] : daoTitles[realm - 1]}」',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  // serif nghiêng + viền kính surface (2 lớp bóng chồng) để nổi
                  // trên nền tranh, hết cảnh chữ trùng màu nền.
                  style: GoogleFonts.lora(
                    textStyle: t.labelMedium,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                    color: cs.onSurface,
                    shadows: [
                      Shadow(color: cs.surface, blurRadius: 6),
                      Shadow(color: cs.surface, blurRadius: 6),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // admin: đổi tộc/giới tính tự do — nút mờ góc phải trên
          if (isAdmin)
            Positioned(
              top: topPad + 4,
              right: 8,
              child: IconButton(
                icon: Icon(
                  Icons.face_retouching_natural_rounded,
                  size: 20,
                  color: cs.onSurfaceVariant,
                ),
                tooltip: 'Đổi dung mạo (admin)',
                onPressed: () => _avatarSheet(context, ref),
              ),
            ),
          // trận pháp hào quang — góc trái trên; Tiên Nhân (hoặc admin ở bản dev) mới hiện
          if (ascended || (isAdmin && kDebugMode))
            Positioned(
              top: topPad + 4,
              left: 8,
              child: IconButton(
                icon: Icon(
                  Icons.blur_circular_rounded,
                  size: 20,
                  color: cs.onSurfaceVariant,
                ),
                tooltip: 'Trận pháp hào quang',
                onPressed: () => showModalBottomSheet(
                  context: context,
                  showDragHandle: true,
                  isScrollControlled: true, // lưới trận cao → cho cuộn, khỏi tràn
                  builder: (_) => _HaloSheet(isAdmin: isAdmin),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Chọn trận pháp hào quang (hậu Phi Thăng). User thường chỉ thấy/đội trận ĐÃ sở hữu;
/// admin (bản dev) thấy trọn bộ + nút nhận hết. Cởi = ô "Không đội".
class _HaloSheet extends ConsumerWidget {
  final bool isAdmin;
  const _HaloSheet({required this.isAdmin});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final st = ref.watch(cultStateProvider).value ?? const {};
    final owned = ((st['halos'] as List?)?.cast<String>() ?? const <String>[]).toSet();
    final worn = st['halo_worn'] as String?;
    // admin dev thấy cả bộ để test; user thường chỉ trận đã sở hữu
    final codes = (isAdmin ? tienHalos.keys : tienHalos.keys.where(owned.contains))
        .toList();

    Future<void> wear(String? code) async {
      try {
        await cultWearHalo(code);
        ref.invalidate(cultStateProvider);
        if (context.mounted) Navigator.pop(context);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
        }
      }
    }

    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Trận pháp hào quang',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                if (isAdmin)
                  TextButton.icon(
                    icon: const Icon(Icons.card_giftcard_rounded, size: 18),
                    label: const Text('Nhận hết'),
                    onPressed: () async {
                      try {
                        await cultAdminGrantHalos();
                        ref.invalidate(cultStateProvider);
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(content: Text('$e')));
                        }
                      }
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (codes.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Chưa có trận pháp nào. Tiếp tục đọc truyện để nhận cơ duyên.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.82,
              children: [
                // ô "Không đội"
                _haloTile(context, null, worn == null, 'Không đội', cs.onSurface,
                    () => wear(null)),
                for (final code in codes)
                  _haloTile(
                    context,
                    code,
                    worn == code,
                    haloName(code),
                    Color(tienHalos[code]!.$2),
                    () => wear(code),
                  ),
              ],
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _haloTile(BuildContext context, String? code, bool active, String name,
      Color color, VoidCallback onTap) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? color : cs.outlineVariant,
            width: active ? 2 : 1,
          ),
          color: active ? color.withValues(alpha: 0.10) : null,
        ),
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: code == null
                  ? Icon(Icons.block_rounded, color: cs.onSurfaceVariant, size: 34)
                  : Image.asset('assets/cult_halo/$code.webp', fit: BoxFit.contain),
            ),
            const SizedBox(height: 4),
            Text(
              name,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: active ? color : cs.onSurfaceVariant,
                    fontWeight: active ? FontWeight.w700 : null,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
