import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data.dart';
import '../../theme.dart';

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
        appBar: AppBar(title: const Text('Cài đặt')),
        body: Center(
          child: FilledButton(
              onPressed: () => context.push('/login'), child: const Text('Đăng nhập')),
        ),
      );
    }

    final name = profile?['display_name'] ?? user.email?.split('@').first ?? 'Bạn đọc';
    return Scaffold(
      appBar: AppBar(title: const Text('Cài đặt')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 110), // chừa chỗ dock nổi
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
                onTap: () => context.push('/offline')),
          ]),
          if (ref.watch(isAdminProvider).value == true) ...[
            const _SectionLabel('Quản trị'),
            _TileGroup(children: [
              _Tile(Icons.admin_panel_settings_outlined, 'Quản lí',
                  onTap: () => context.push('/admin')),
              _Tile(Icons.bug_report_outlined, 'Nhật ký lỗi (app)',
                  onTap: () => context.push('/errors')),
            ]),
          ],
          const _SectionLabel('Tài khoản'),
          _TileGroup(children: [
            _Tile(Icons.person_outline, 'Sửa thông tin',
                onTap: () => context.push('/profile/edit')),
          ]),
        ],
      ),
    );
  }
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                ? Text(avatar!, style: const TextStyle(fontSize: 28))
                : Text(initial,
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(color: cs.primary)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
    );
  }
}

/// Bảng số liệu đọc — 1 khối viền hairline kiểu dashboard: 3 cột số mono
/// (đang đọc / chương / streak) + dải 7 ô vuông tuần này ở dưới.
class _ReadingPanel extends StatelessWidget {
  final int novels, chapters, streak;
  const _ReadingPanel(
      {required this.novels, required this.chapters, required this.streak});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    Widget cell(String v, String label, {Color? c}) => Expanded(
          child: Column(children: [
            Text(v, style: monoStyle(context, size: 24, w: FontWeight.w600,
                color: c ?? cs.onSurface)),
            const SizedBox(height: 3),
            Text(label.toUpperCase(),
                style: t.labelSmall?.copyWith(letterSpacing: 0.8, fontSize: 10.5)),
          ]),
        );
    final vline = Container(width: 1, height: 34,
        color: cs.outlineVariant.withValues(alpha: 0.7));

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
      child: Column(children: [
        Row(children: [
          cell('$novels', 'đang đọc'),
          vline,
          cell('$chapters', 'chương đã đọc'),
          vline,
          cell('$streak', 'ngày streak', c: streak > 0 ? cs.secondary : null),
        ]),
        const SizedBox(height: 14),
        Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.6)),
        const SizedBox(height: 12),
        // dải 7 ô vuông bo nhẹ (kiểu contribution graph): sáng = ngày có đọc
        Row(children: [
          Icon(Icons.local_fire_department_rounded,
              size: 16, color: streak > 0 ? cs.secondary : cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(streak > 0 ? 'Chuỗi $streak ngày đọc liên tiếp' : 'Chưa có chuỗi đọc',
              style: t.labelMedium),
          const Spacer(),
          for (var i = 0; i < 7; i++)
            Container(
              margin: const EdgeInsets.only(left: 5),
              width: 14, height: 14,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: i < streak
                    ? cs.secondary.withValues(alpha: 0.85)
                    : cs.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
        ]),
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
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant)),
      child: Row(children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(i),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: i == value ? cs.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                ),
                alignment: Alignment.center,
                child: Text(labels[i],
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        // onPrimary chứ không phải trắng cứng — dark mode nền nhấn sáng
                        color: i == value ? cs.onPrimary : cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ),
      ]),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 22, 0, 10),
        child: Text(text.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                letterSpacing: 1.5, color: Theme.of(context).colorScheme.primary)),
      );
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
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Column(children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0)
            Divider(height: 1, thickness: 1, indent: 52,
                color: cs.outlineVariant.withValues(alpha: 0.6)),
          children[i],
        ],
      ]),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _Tile(this.icon, this.label, {required this.onTap});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(vertical: 1),
      leading: Icon(icon, size: 21, color: cs.onSurfaceVariant),
      title: Text(label, style: Theme.of(context).textTheme.bodyLarge),
      trailing: Icon(Icons.chevron_right, size: 18, color: cs.onSurfaceVariant),
      onTap: onTap,
    );
  }
}
