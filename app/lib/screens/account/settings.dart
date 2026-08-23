import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:package_info_plus/package_info_plus.dart';

import '../../data.dart';
import '../../theme.dart';
import '../../update.dart';
import '../../widgets.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = sb.auth.currentUser;
    final stats = ref.watch(readStatsProvider).value;
    final profile = ref.watch(profileProvider).value;
    final mode = ref.watch(appThemeModeProvider);

    if (user == null) {
      return Scaffold(
        body: SafeArea(
          child: Column(children: [
            const PageHeader('CÁ NHÂN', 'Cài đặt'),
            Expanded(
              child: Center(
                child: FilledButton(
                    onPressed: () => context.push('/login'),
                    child: const Text('Đăng nhập')),
              ),
            ),
          ]),
        ),
      );
    }

    final name = profile?['display_name'] ?? user.email?.split('@').first ?? 'Bạn đọc';
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          // header editorial đồng bộ các tab (thay AppBar phẳng)
          const PageHeader('CÁ NHÂN', 'Cài đặt'),
          Expanded(
              child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 110), // chừa chỗ dock nổi
            children: [
          _ProfileCard(
              name: name,
              email: user.email ?? '',
              avatar: profile?['avatar_url'] as String?,
              onLogout: () async {
                await sb.auth.signOut();
                ref.invalidate(profileProvider);
                ref.invalidate(readStatsProvider);
                if (context.mounted) context.go('/');
              }),
          const SizedBox(height: 16),
          // Bảng số liệu đọc kiểu dashboard: 3 cột mono + dải streak 7 ngày.
          // Streak = số ngày đọc liên tiếp (RPC touch_reading_streak, tính giờ VN).
          _ReadingPanel(
            novels: stats?['novels'] ?? 0,
            chapters: stats?['chapters'] ?? 0,
            streak: liveStreak(profile),
          ),
          const _SectionLabel('Giao diện'),
          _Segmented(
            value: mode,
            labels: const ['Hệ thống', 'Sáng', 'Tối'],
            onChanged: (i) => ref.read(appThemeModeProvider.notifier).set(i),
          ),
          const _SectionLabel('Thư viện'),
          _TileGroup(children: [
            _Tile(Icons.download_done_rounded, 'Bản offline',
                subtitle: 'Truyện đã tải để đọc không cần mạng',
                onTap: () => context.push('/offline')),
          ]),
          if (ref.watch(isAdminProvider).value == true) ...[
            const _SectionLabel('Quản trị'),
            _TileGroup(children: [
              _Tile(Icons.admin_panel_settings_outlined, 'Quản lí',
                  subtitle: 'Hàng đợi dịch và kho truyện',
                  onTap: () => context.push('/admin')),
              _Tile(Icons.dns_outlined, 'Theo dõi VPS',
                  subtitle: 'CPU, RAM, ổ đĩa của máy chủ chạy worker',
                  onTap: () => context.push('/admin/vps')),
              _Tile(Icons.bug_report_outlined, 'Nhật ký lỗi',
                  subtitle: 'Sự cố của ứng dụng và worker',
                  onTap: () => context.push('/errors')),
            ]),
          ],
          const _SectionLabel('Tài khoản'),
          _TileGroup(children: [
            _Tile(Icons.person_outline, 'Sửa thông tin',
                subtitle: 'Tên hiển thị và ảnh đại diện',
                onTap: () => context.push('/profile/edit')),
          ]),
          const _SectionLabel('Ứng dụng'),
          _TileGroup(children: [
            _Tile(Icons.menu_book_outlined, 'Hướng dẫn sử dụng',
                subtitle: 'Mẹo đọc, lưu và yêu cầu dịch',
                onTap: () => context.push('/guide')),
            _Tile(Icons.system_update_alt_rounded, 'Kiểm tra cập nhật',
                subtitle: 'Tìm phiên bản mới nhất',
                onTap: () => _checkUpdate(context, ref)),
          ]),
            ],
          )),
        ]),
      ),
    );
  }
}

/// Kiểm tra chủ động: có bản mới → dialog tải; đã mới nhất → snackbar kèm version.
Future<void> _checkUpdate(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final info = await ref.refresh(updateProvider.future);
  if (info != null) {
    if (context.mounted) showUpdateDialog(context, info);
    return;
  }
  final v = (await PackageInfo.fromPlatform()).version;
  messenger.showSnackBar(
      SnackBar(content: Text('Đang dùng bản mới nhất ($v)')));
}

class _ProfileCard extends StatelessWidget {
  final String name, email;
  final String? avatar;
  final VoidCallback onLogout;
  const _ProfileCard(
      {required this.name, required this.email, this.avatar, required this.onLogout});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final initial = name.isNotEmpty ? name.characters.first.toUpperCase() : '?';
    final hasEmoji = avatar != null && avatar!.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Stack(children: [
        Positioned(
          right: -24,
          top: -38,
          child: Icon(Icons.auto_stories_rounded,
              size: 150, color: cs.primary.withValues(alpha: 0.07)),
        ),
        Padding(
          padding: const EdgeInsets.all(18),
        child: Row(children: [
          // avatar phẳng kiểu tech: nền nhấn nhạt + viền 1px, bo vuông mềm (không gradient)
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.primary.withValues(alpha: 0.35)),
            ),
            alignment: Alignment.center,
            child: hasEmoji
                // height:1 — bỏ leading font emoji, không thì glyph lệch lên trên
                ? Text(avatar!, style: const TextStyle(fontSize: 28, height: 1))
                : Text(initial,
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(color: cs.primary)),
          ),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('THƯ CÁC CỦA BẠN', style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: cs.primary, letterSpacing: 1.2)),
              const SizedBox(height: 3),
              Text(name, style: Theme.of(context).textTheme.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(email, style: monoStyle(context), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
          // đăng xuất ngay trên thẻ tài khoản — khỏi phải cuộn xuống tìm
          IconButton(
            tooltip: 'Đăng xuất',
            icon: Icon(Icons.logout_rounded, size: 22, color: cs.error),
            onPressed: onLogout,
          ),
          ]),
        ),
      ]),
    );
  }
}

/// Bảng số liệu đọc — streak là "nhân vật chính": dải hero nền vàng gradient (ngọn lửa
/// + số ngày lớn) ở trên, hai số phụ (đang đọc / chương đã đọc) ở dưới.
/// Bỏ dải 7 ô cũ: không có dữ liệu đọc theo NGÀY nên nó chỉ lặp lại con số streak.
class _ReadingPanel extends StatelessWidget {
  final int novels, chapters, streak;
  const _ReadingPanel(
      {required this.novels, required this.chapters, required this.streak});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final hot = streak > 0;
    final gold = cs.secondary; // Pal.gold/dGold — màu dành riêng cho streak/thành tựu

    Widget stat(String v, String label) => Expanded(
          child: Column(children: [
            Text(v, style: monoStyle(context, size: 22, w: FontWeight.w600)),
            const SizedBox(height: 3),
            Text(label.toUpperCase(),
                style: t.labelSmall?.copyWith(letterSpacing: 0.8, fontSize: 10.5)),
          ]),
        );

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias, // dải gradient bo theo góc thẻ
      child: Column(children: [
        // Hero streak: nền vàng gradient nhạt khi còn chuỗi, phẳng lặng khi đã đứt.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: hot
                  ? [gold.withValues(alpha: 0.22), gold.withValues(alpha: 0.05)]
                  : [Colors.transparent, Colors.transparent],
            ),
          ),
          child: Row(children: [
            Icon(Icons.local_fire_department_rounded,
                size: 42, color: hot ? gold : cs.onSurfaceVariant),
            const SizedBox(width: 14),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$streak', style: monoStyle(context, size: 34, w: FontWeight.w700,
                  color: hot ? gold : cs.onSurface)),
              const SizedBox(height: 1),
              Text(hot ? 'ngày đọc liên tiếp' : 'chưa có chuỗi — đọc hôm nay để bắt đầu',
                  style: t.labelMedium?.copyWith(
                      letterSpacing: 0.4, color: cs.onSurfaceVariant)),
            ]),
          ]),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(children: [
            stat('$novels', 'đang đọc'),
            Container(width: 1, height: 30,
                color: cs.outlineVariant.withValues(alpha: 0.7)),
            stat('$chapters', 'chương đã đọc'),
          ]),
        ),
      ]),
    );
  }
}

class _Segmented extends StatelessWidget {
  final int value;
  final List<String> labels;
  final ValueChanged<int> onChanged;
  const _Segmented({required this.value, required this.labels, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // nang chọn TRƯỢT giữa các ô (không nhảy màu từng ô như bản cũ) — cùng ngôn
    // ngữ chuyển động với pill dock.
    return Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant)),
      child: SizedBox(
        height: 42,
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
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          Row(children: [
            for (var i = 0; i < labels.length; i++)
              Expanded(
                child: GestureDetector(
                  onTap: () => onChanged(i),
                  behavior: HitTestBehavior.opaque,
                  child: Center(
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: Theme.of(context).textTheme.labelMedium!.copyWith(
                          // onPrimary chứ không phải trắng cứng — dark mode nền nhấn sáng
                          color: i == value ? cs.onPrimary : cs.onSurfaceVariant,
                          fontWeight: FontWeight.w600),
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
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 26, 0, 10),
      child: Text(text.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
              letterSpacing: 1.5, color: cs.primary)),
    );
  }
}

/// Nhóm tile kiểu Linear/Vercel: 1 khối viền hairline, kẻ mảnh giữa các dòng —
/// gọn và "tech" hơn card-per-row.
class _TileGroup extends StatelessWidget {
  final List<Widget> children;
  const _TileGroup({required this.children});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Material chứ không phải Container-có-màu: ListTile vẽ splash lên Material gần
    // nhất — bọc DecoratedBox sẽ che splash + Flutter bắn warning mỗi lần build.
    return Material(
      color: cs.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Column(children: children),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
  const _Tile(this.icon, this.label, {this.subtitle, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      leading: Container(
        width: 38, height: 38,
        decoration: BoxDecoration(color: cs.primaryContainer.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, size: 20, color: cs.primary),
      ),
      title: Text(label, style: Theme.of(context).textTheme.titleMedium),
      subtitle: subtitle == null ? null : Text(subtitle!,
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall),
      trailing: Container(
        width: 28, height: 28,
        decoration: BoxDecoration(color: cs.surface,
            shape: BoxShape.circle, border: Border.all(color: cs.outlineVariant)),
        child: Icon(Icons.chevron_right_rounded, size: 18, color: cs.onSurfaceVariant),
      ),
      onTap: onTap,
    );
  }
}
