import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'data.dart';
import 'offline.dart';
import 'theme.dart' show monoStyle;

/// Tải truyện về máy (đọc offline) hoặc xoá bản đã tải. Dùng chung ở chi tiết truyện
/// và tủ truyện. Tải = chỉ các chương ĐÃ DỊCH hiện có.
Future<void> toggleOffline(
    BuildContext context, WidgetRef ref, Map<String, dynamic> novel, bool downloaded) async {
  final id = novel['id'] as int;
  final messenger = ScaffoldMessenger.of(context);
  void refresh() {
    ref.invalidate(isDownloadedProvider(id));
    ref.invalidate(offlineNovelsProvider);
  }

  if (downloaded) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xoá bản offline?'),
        content: const Text('Xoá các chương đã tải của truyện này khỏi máy.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Xoá')),
        ],
      ),
    );
    if (ok != true) return;
    await offlineStore.deleteNovel(id);
    refresh();
    messenger.showSnackBar(const SnackBar(content: Text('Đã xoá bản offline')));
    return;
  }

  // Tải: hiện vòng quay chặn thao tác tới khi xong (tải theo lô, vài giây).
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      content: Row(children: [
        SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
        SizedBox(width: 18),
        Expanded(child: Text('Đang tải chương về máy…')),
      ]),
    ),
  );
  try {
    final count = await offlineStore.downloadNovel(novel);
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop(); // đóng loading
    refresh();
    messenger.showSnackBar(SnackBar(
        content: Text(count > 0
            ? 'Đã tải $count chương để đọc offline'
            : 'Chưa có chương đã dịch nào để tải')));
  } catch (e) {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    messenger.showSnackBar(SnackBar(content: Text('Lỗi tải: $e')));
  }
}

/// Hộp thoại "yêu cầu dịch": chọn dịch tới đâu (chạy song song với tự-dịch khi đọc).
/// [translated]/[source] để tính preset "+N chương" và "đến hết".
void translateRangeDialog(BuildContext context, WidgetRef ref, int novelId,
    {required int translated, required int source, VoidCallback? onDone}) {
  if (sb.auth.currentUser == null) {
    context.push('/login');
    return;
  }
  final custom = TextEditingController();

  Future<void> submit(int upTo) async {
    if (upTo <= translated) return; // đã dịch tới đó rồi
    final n = await requestTranslation(novelId, upTo);
    ref.invalidate(chapterListProvider(novelId));
    ref.invalidate(translateQueueProvider);
    if (context.mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Đã xếp $n chương vào hàng đợi dịch')));
    }
    onDone?.call();
  }

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Yêu cầu dịch'),
      // maxFinite + scroll: bề ngang ổn định, bàn phím che thì cuộn thay vì tràn
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Đã dịch $translated/$source chương. Chọn dịch tới đâu:',
                style: Theme.of(ctx).textTheme.bodyMedium),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final step in [50, 100, 200])
                if (translated + step <= source || translated < source)
                  ActionChip(
                    label: Text('+$step chương'),
                    onPressed: () => submit((translated + step).clamp(0, source)),
                  ),
              if (translated < source)
                ActionChip(label: const Text('Đến hết'), onPressed: () => submit(source)),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: custom,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Hoặc dịch tới chương…', isDense: true),
              onSubmitted: (v) {
                final to = int.tryParse(v.trim());
                if (to != null) submit(to.clamp(0, source));
              },
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
        FilledButton(
          onPressed: () {
            final to = int.tryParse(custom.text.trim());
            if (to != null) submit(to.clamp(0, source));
          },
          child: const Text('Dịch'),
        ),
      ],
    ),
  );
}

/// Logo GT trong app: chữ trần không nền — mực đen khi sáng, mực sáng khi tối
/// (đen tuyền trên nền đêm sẽ tàng hình). Icon launcher lo phần nền trắng.
class BrandLogo extends StatelessWidget {
  final double height;
  const BrandLogo({super.key, this.height = 40});
  @override
  Widget build(BuildContext context) {
    return Image.asset('assets/icon/gt_white.png',
        height: height,
        color: Theme.of(context).colorScheme.onSurface,
        filterQuality: FilterQuality.medium);
  }
}

/// Trạng thái đang tải toàn màn: logo xoá nền + vòng quay.
class AppLoading extends StatelessWidget {
  const AppLoading({super.key});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const BrandLogo(height: 64),
        const SizedBox(height: 20),
        SizedBox(
            width: 22, height: 22,
            child: CircularProgressIndicator(
                strokeWidth: 2.5, color: Theme.of(context).colorScheme.primary)),
      ]),
    );
  }
}

/// Ô bấm được kiểu NEO: co nhẹ khi nhấn (spring press) + haptic.
class TapScale extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const TapScale({super.key, required this.child, required this.onTap});
  @override
  State<TapScale> createState() => _TapScaleState();
}

class _TapScaleState extends State<TapScale> {
  bool _held = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      onTapDown: (_) => setState(() => _held = true),
      onTapUp: (_) => setState(() => _held = false),
      onTapCancel: () => setState(() => _held = false),
      child: AnimatedScale(
        scale: _held && !MediaQuery.of(context).disableAnimations ? 0.965 : 1,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Ảnh bìa truyện: bo góc 14, đổ bóng mềm (chiều sâu), placeholder gradient.
class Cover extends StatelessWidget {
  final String? url;
  final double width;
  final double aspect; // cao / rộng
  final String? label; // chữ cái đầu cho placeholder khi thiếu bìa
  final bool flat; // true = tắt bóng đổ (thumbnail nhỏ sát nhau bóng nhìn rối)
  const Cover(
      {super.key, this.url, this.width = 108, this.aspect = 1.4, this.label, this.flat = false});

  @override
  Widget build(BuildContext context) {
    final h = width * aspect;
    final radius = BorderRadius.circular(8);
    final cs = Theme.of(context).colorScheme;
    final initial = (label ?? '').trim();
    // placeholder phẳng (tech-minimal): nền nhấn nhạt + chữ cái màu nhấn — không gradient
    Widget fallback = Container(
      width: width,
      height: h,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: radius,
        color: cs.primaryContainer.withValues(alpha: 0.55),
      ),
      child: initial.isEmpty
          ? Icon(Icons.auto_stories_outlined,
              color: cs.primary.withValues(alpha: 0.8), size: width * 0.32)
          : Text(initial.characters.first.toUpperCase(),
              style: TextStyle(
                  color: cs.primary,
                  fontSize: width * 0.42,
                  fontWeight: FontWeight.w800)),
    );
    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        // tech-minimal: viền 1px mờ + bóng rất nhẹ thay bóng nặng
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
        boxShadow: flat
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: (url == null || url!.isEmpty)
            ? fallback
            : Image.network(
                url!,
                width: width,
                height: h,
                fit: BoxFit.cover,
                // decode ở độ phân giải màn hình thật (gấp devicePixelRatio) cho nét,
                // + filterQuality medium để scale mượt thay vì rỗ/mờ.
                cacheWidth:
                    (width * MediaQuery.of(context).devicePixelRatio).round(),
                filterQuality: FilterQuality.medium,
                isAntiAlias: true,
                errorBuilder: (_, _, _) => fallback,
                loadingBuilder: (c, child, prog) => prog == null
                    ? child
                    : SizedBox(width: width, height: h, child: fallback),
              ),
      ),
    );
  }
}

/// Tiêu đề một mục (rail) — kiểu editorial: tiêu đề đậm + link "Xem tất cả".
class SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onMore;
  const SectionHeader(this.title, {super.key, this.onMore});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(title,
                style: Theme.of(context).textTheme.headlineSmall),
          ),
          if (onMore != null)
            IconButton(
              tooltip: 'Xem tất cả',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.chevron_right_rounded),
              onPressed: onMore,
            ),
        ],
      ),
    );
  }
}

/// Thanh tiến độ đọc mảnh (ruy-băng ngọc) — dấu ấn của app.
class ProgressRibbon extends StatelessWidget {
  final double value; // 0..1
  const ProgressRibbon(this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: LinearProgressIndicator(
        value: value.clamp(0, 1),
        minHeight: 5,
        backgroundColor: cs.outlineVariant.withValues(alpha: 0.5),
        valueColor: AlwaysStoppedAnimation(cs.primary),
      ),
    );
  }
}

/// Một dòng truyện liền mạch (bìa + tiêu đề + tác giả + số chương/trạng thái).
/// Dùng cho danh sách tìm kiếm / lọc — không bọc Card để hiện nhiều truyện hơn.
class NovelListRow extends StatelessWidget {
  final Map<String, dynamic> n;
  final VoidCallback onTap;
  final Widget? trailing;
  const NovelListRow({super.key, required this.n, required this.onTap, this.trailing});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final title = n['title_vi'] ?? n['title_zh'] ?? '';
    final genres = (n['genres'] as List?)?.whereType<String>().toList() ?? const [];
    const coverW = 76.0; // bìa nhỉnh hơn khối chữ bên phải một chút cho cân mắt
    const coverH = coverW * 1.36; // ảnh to hơn + text căn theo chiều cao ảnh
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Hero cùng tag với trang thông tin → bìa bay mượt khi mở truyện
          Hero(
            tag: 'cover-${n['id']}',
            child: Cover(url: n['cover_url'], width: coverW, aspect: 1.36, label: title),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: SizedBox(
              height: coverH,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // trên: tiêu đề (ngang đỉnh ảnh) + tác giả
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.titleMedium),
                    const SizedBox(height: 3),
                    // tác giả chữ thường, cùng tông nhạt với dòng thể loại
                    Text(n['author_vi'] ?? n['author_zh'] ?? '',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: t.labelMedium?.copyWith(letterSpacing: 0)),
                  ]),
                  if (genres.isNotEmpty) GenreChips(genres, max: 3),
                  // đáy: ngang chân ảnh — số chương (bỏ chip trạng thái cho gọn)
                  IconStat(Icons.menu_book_rounded, '${n['chapter_count_source'] ?? 0}'),
                ],
              ),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ]),
      ),
    );
  }
}

/// Đường kẻ mảnh ngăn cách các dòng trong danh sách liền mạch.
class RowDivider extends StatelessWidget {
  const RowDivider({super.key});
  @override
  Widget build(BuildContext context) => Divider(
      height: 1, thickness: 1, indent: 16, endIndent: 16,
      color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6));
}

/// Thể loại kiểu NEO: "Huyền Huyễn · Đô Thị" — chữ nhạt, ngăn bằng chấm giữa.
/// Dùng chung ở danh sách + chi tiết cho nhất quán. [max] null = hiện hết (tự wrap).
class GenreChips extends StatelessWidget {
  final List<String> genres;
  final int? max;
  const GenreChips(this.genres, {super.key, this.max});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final show = max == null ? genres : genres.take(max!).toList();
    return Text(
      show.join(' · '),
      maxLines: max == null ? null : 1,
      overflow: TextOverflow.ellipsis,
      style: t.labelMedium?.copyWith(
          color: cs.onSurfaceVariant, fontWeight: FontWeight.w500, letterSpacing: 0),
    );
  }
}

/// "icon + số" gọn — thay cụm chữ "X chương" cho đỡ rườm.
class IconStat extends StatelessWidget {
  final IconData icon;
  final String value;
  const IconStat(this.icon, this.value, {super.key});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: cs.onSurfaceVariant),
      const SizedBox(width: 4),
      Text(value, style: monoStyle(context)), // số liệu dùng mono — chất "tech"
    ]);
  }
}

/// "vừa xong" / "5 phút trước" / "2 giờ trước" / "3 ngày trước" từ mốc ISO.
String timeAgo(Object? iso) {
  if (iso == null) return '';
  final d = DateTime.now().toUtc().difference(DateTime.parse('$iso').toUtc());
  if (d.inMinutes < 1) return 'vừa xong';
  if (d.inMinutes < 60) return '${d.inMinutes} phút trước';
  if (d.inHours < 24) return '${d.inHours} giờ trước';
  return '${d.inDays} ngày trước';
}

/// Chip trạng thái nhỏ (Hoàn thành / Đang ra…).
class TagChip extends StatelessWidget {
  final String label;
  final Color? color;
  const TagChip(this.label, {super.key, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: c, fontWeight: FontWeight.w600),
      ),
    );
  }
}
