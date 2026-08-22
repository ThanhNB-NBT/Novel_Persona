import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

/// Header editorial đồng bộ các tab (kiểu Khám phá): nhãn nhỏ tracking rộng
/// màu nhấn + tiêu đề display, actions dồn phải. Thay AppBar phẳng.
class PageHeader extends StatelessWidget {
  final String eyebrow, title;
  final List<Widget> actions;
  const PageHeader(this.eyebrow, this.title, {super.key, this.actions = const []});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 8, 10),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              // vạch nhấn nhỏ trước eyebrow — nét bút điểm nhãn
              Container(
                  width: 16,
                  height: 2,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                      color: cs.primary, borderRadius: BorderRadius.circular(1))),
              Text(eyebrow.toUpperCase(),
                  style: t.labelSmall?.copyWith(color: cs.primary, letterSpacing: 3)),
            ]),
            const SizedBox(height: 2),
            Text(title,
                style: t.headlineMedium?.copyWith(color: cs.onSurface)),
          ]),
        ),
        ...actions,
      ]),
    );
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

/// Trạng thái lỗi toàn màn: thông báo THÂN THIỆN (không đập exception thô vào mặt
/// user) + nút Thử lại. Phân biệt mất mạng với lỗi khác. Thay cho `Text('Lỗi: $e')`
/// rải khắp — màn lỗi trước đây là ngõ cụt (list có RefreshIndicator nhưng nhánh
/// error trả Center không cuộn được nên không kéo làm mới được).
class AppError extends StatelessWidget {
  final Object error;
  final VoidCallback? onRetry;
  const AppError(this.error, {super.key, this.onRetry});

  /// Lỗi mạng → nói "mất kết nối" thay vì phơi SocketException/ClientException.
  static bool _isOffline(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('socketexception') ||
        s.contains('clientexception') ||
        s.contains('failed host lookup') ||
        s.contains('connection') ||
        s.contains('network');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final offline = _isOffline(error);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(offline ? Icons.wifi_off_rounded : Icons.error_outline_rounded,
              size: 44, color: cs.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(offline ? 'Mất kết nối mạng' : 'Có lỗi xảy ra',
              style: t.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(
              offline
                  ? 'Kiểm tra mạng rồi thử lại.'
                  : 'Vui lòng thử lại sau ít phút.',
              style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Thử lại'),
            ),
          ],
        ]),
      ),
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

/// Tiêu đề một mục (rail) — kiểu editorial: tiêu đề đậm + link "Xem tất cả".
class SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onMore;
  const SectionHeader(this.title, {super.key, this.onMore});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // vạch nhấn CHỈ ở header trang (PageHeader/_Brand) — rải xuống từng mục là loãng
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
            // pill "Xem tất cả" chữ + mũi tên — rõ nghĩa hơn chevron trơ
            TextButton(
              onPressed: onMore,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                foregroundColor: cs.primary,
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('Xem tất cả',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: cs.primary, fontWeight: FontWeight.w600)),
                const Icon(Icons.chevron_right_rounded, size: 16),
              ]),
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
    return Semantics(
      label: 'Tiến độ đọc',
      value: '${(value.clamp(0, 1) * 100).round()}%',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: LinearProgressIndicator(
          value: value.clamp(0, 1),
          minHeight: 5,
          backgroundColor: cs.outlineVariant.withValues(alpha: 0.5),
          valueColor: AlwaysStoppedAnimation(cs.primary),
        ),
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
