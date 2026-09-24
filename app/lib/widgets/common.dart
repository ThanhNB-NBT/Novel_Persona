import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme.dart';

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
  /// Chữ trên dấu triện cạnh tiêu đề — mỗi trang một chữ (藏 Tủ truyện, 覽 Khám phá…).
  final String seal;
  const PageHeader(this.eyebrow, this.title,
      {super.key, this.actions = const [], this.seal = '閣'});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 8, 10),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // nhãn phụ chỉ khi NÓI THÊM được điều gì ('CÁ NHÂN' trên 'Tôi' là lặp) → '' thì bỏ
            if (eyebrow.isNotEmpty) ...[
              Text(eyebrow.toUpperCase(),
                  style: t.labelSmall?.copyWith(color: cs.primary, letterSpacing: 3)),
              const SizedBox(height: 2),
            ],
            // triện đóng sau tiêu đề như lạc khoản trên tranh — chữ ký thương hiệu (GĐ7)
            Row(children: [
              Flexible(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.headlineMedium?.copyWith(color: cs.onSurface)),
              ),
              const SizedBox(width: 10),
              Seal(char: seal, size: 22),
            ]),
          ]),
        ),
        ...actions,
      ]),
    );
  }
}

/// Dấu triện son — điểm nhấn cổ phong DUY NHẤT được phép trên khung (GĐ7). Chỉ đặt
/// cạnh tiêu đề trang/mục; [char] null = triện trơn (chấm đầu mục nhỏ, chữ đọc không ra).
class Seal extends StatelessWidget {
  final String? char;
  final double size;
  const Seal({super.key, this.char, this.size = 20});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = sealColor(context);
    final paper = dark ? Pal.dBg : Colors.white;
    return ExcludeSemantics(
      child: Transform.rotate(
        angle: -0.07, // đóng tay nên hơi lệch — thẳng tắp nhìn như icon
        child: Container(
          width: size,
          height: size,
          padding: EdgeInsets.all(size * 0.09),
          decoration: BoxDecoration(
              color: ink, borderRadius: BorderRadius.circular(size * 0.16)),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: paper.withValues(alpha: 0.8), width: size * 0.045),
              borderRadius: BorderRadius.circular(size * 0.1),
            ),
            child: char == null
                ? null
                : Text(char!,
                    textScaler: TextScaler.noScaling, // triện là hình, không phải chữ đọc
                    style: TextStyle(
                        color: paper, fontSize: size * 0.54, height: 1, fontWeight: FontWeight.w700)),
          ),
        ),
      ),
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
/// Đổi ngoại lệ thành MỘT câu người dùng hiểu được và biết phải làm gì.
///
/// Trước đây các màn Quản trị in thẳng `'Lỗi: $e'`, ra màn hình thành nguyên khối:
///   PostgrestException(message: duplicate key value violates unique constraint
///   "uq_job_meta_active", code: 23505, details: Key (novel_id, type)=(35833,
///   metadata) already exists., hint: null)
/// Đọc xong vẫn không biết chuyện gì. Gom về một chỗ để mọi nơi hiện lỗi nói
/// cùng một giọng, và luôn ưu tiên "chuyện gì xảy ra" thay vì "máy báo mã gì".
///
/// Lỗi chưa có mẫu thì KHÔNG nuốt mất: cắt lấy dòng đầu, gọn lại — vẫn tra được
/// mà không phủ kín màn hình.
String loiDeHieu(Object e) {
  final s = e.toString().toLowerCase();

  // Mạng xét trước mọi thứ: mất kết nối thì mã lỗi bên dưới đều vô nghĩa.
  if (s.contains('socketexception') ||
      s.contains('clientexception') ||
      s.contains('failed host lookup') ||
      s.contains('timeoutexception') ||
      s.contains('connection')) {
    return 'Mất kết nối — kiểm tra mạng rồi thử lại.';
  }

  if (e is AuthException) {
    if (s.contains('invalid login')) return 'Sai email hoặc mật khẩu.';
    if (s.contains('email not confirmed')) return 'Email chưa được xác nhận.';
    // App bỏ đăng ký và máy chủ khoá DISABLE_SIGNUP → nói rõ đường đi tiếp.
    if (s.contains('signup') && s.contains('disabled')) {
      return 'Đăng ký đã khoá — nhờ quản trị tạo tài khoản giúp.';
    }
    return 'Đăng nhập thất bại. Thử lại.';
  }

  if (e is PostgrestException) {
    final d = '${e.message} ${e.details ?? ''}'.toLowerCase();
    switch (e.code) {
      case '23505': // trùng khoá
        if (d.contains('uq_job_meta_active')) {
          return 'Truyện này đã có việc đang chờ trong hàng đợi — xong việc đó rồi hẵng thử lại.';
        }
        return 'Dữ liệu này đã có rồi.';
      case '23503': // khoá ngoại
        return 'Dữ liệu liên quan không còn — tải lại rồi thử lại.';
      case '42501': // RLS chặn
        return 'Không có quyền làm việc này.';
      case 'PGRST301':
        return 'Phiên đăng nhập hết hạn — đăng nhập lại.';
    }
    if (d.contains('admin only')) return 'Việc này cần quyền quản trị.';
    // Không khớp mẫu: chỉ lấy message, bỏ code/details/hint.
    return e.message;
  }

  final dongDau = e.toString().split('\n').first.trim();
  if (dongDau.isEmpty) return 'Có lỗi xảy ra. Thử lại sau ít phút.';
  return dongDau.length <= 120 ? dongDau : '${dongDau.substring(0, 117)}…';
}

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
              // Mất mạng thì câu trên đã đủ; còn lại nói RÕ lỗi gì thay vì
              // "thử lại sau ít phút" — câu đó không giúp ai quyết định gì.
              offline ? 'Kiểm tra mạng rồi thử lại.' : loiDeHieu(error),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // không chấm triện đầu mục: trang chủ 4–5 mục = 4–5 ô đỏ, rối mắt.
          // Triện chỉ còn ở PageHeader (một con dấu mỗi trang).
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


/// Hộp thoại có NỀN SAU MỜ DẦN (progressive blur — ColorOS 17) thay cho màn che
/// phẳng của [showDialog]. Trùng chữ ký với showDialog nên thay tại chỗ gọi là xong.
///
/// Sigma cố định chứ không chạy theo animation: blur là phép đắt, đổi sigma mỗi
/// khung làm giật máy yếu; fade + phóng nhẹ đã đủ cảm giác "trồi lên".
Future<T?> showBlurDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    // Màn che rất nhạt: phần "tách khỏi nền" do blur lo, tô đậm nữa thành đục.
    barrierColor: Colors.black.withValues(alpha: 0.18),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (ctx, _, _) => builder(ctx),
    transitionBuilder: (ctx, anim, _, child) {
      final t = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: t,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: ScaleTransition(
            scale: Tween(begin: 0.96, end: 1.0).animate(t),
            child: child,
          ),
        ),
      );
    },
  );
}
