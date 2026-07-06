import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data.dart';
import '../neo_theme.dart';
import '../neo_widgets.dart';

/// Tab Hệ thống — hồ sơ + số liệu đọc + lối vào quản trị.
/// ponytail: NEO dark-only, bỏ segment chọn theme của app cũ; light mode
/// "hologram trắng" cần token hoá lại toàn bộ Neo.* — làm khi thật sự cần.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = sb.auth.currentUser;
    ref.watch(authStateProvider);
    final stats = ref.watch(readStatsProvider).value;
    final profile = ref.watch(profileProvider).value;

    if (user == null) {
      return SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const _Header(),
          Expanded(
            child: Center(
              child: SizedBox(
                width: 240,
                child: NeoButton(label: 'ĐĂNG NHẬP', onPressed: () => context.push('/login')),
              ),
            ),
          ),
        ]),
      );
    }

    final name = profile?['display_name'] ?? user.email?.split('@').first ?? 'Bạn đọc';
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
        children: [
          const _Header(),
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
          const SizedBox(height: 14),
          _ReadingPanel(
            novels: stats?['novels'] ?? 0,
            chapters: stats?['chapters'] ?? 0,
            streak: liveStreak(profile),
          ),
          const _SectionLabel('Thư viện'),
          _TileGroup(children: [
            _Tile(Icons.download_done, 'Bản offline', onTap: () => context.push('/offline')),
          ]),
          if (ref.watch(isAdminProvider).value == true) ...[
            const _SectionLabel('Quản trị'),
            _TileGroup(children: [
              _Tile(Icons.admin_panel_settings_outlined, 'Bảng quản trị',
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

class _Header extends StatelessWidget {
  const _Header();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('NEO // HỆ THỐNG', style: Neo.mono(10, color: Neo.cyan, spacing: 3)),
        const SizedBox(height: 2),
        Text('Điều khiển', style: Neo.display(28)),
      ]),
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
    final initial = name.isNotEmpty ? name.characters.first.toUpperCase() : '?';
    final hasEmoji = avatar != null && avatar!.isNotEmpty;
    return NeoPanel(
      glowColor: Neo.cyan,
      borderColor: Neo.cyan.withValues(alpha: 0.3),
      child: Row(children: [
        Container(
          width: 56, height: 56,
          decoration: ShapeDecoration(
            color: Neo.surface2,
            shape: NeoCutBorder(
                cut: Neo.cutSm, side: BorderSide(color: Neo.cyan.withValues(alpha: 0.4))),
          ),
          alignment: Alignment.center,
          child: hasEmoji
              ? Text(avatar!, style: const TextStyle(fontSize: 28))
              : Text(initial, style: Neo.display(24, color: Neo.cyan)),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: Neo.display(18, weight: FontWeight.w600),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(email, style: Neo.mono(10), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
        IconButton(
          tooltip: 'Đăng xuất',
          icon: const Icon(Icons.logout, size: 22, color: Neo.danger),
          onPressed: onLogout,
        ),
      ]),
    );
  }
}

/// Bảng số liệu đọc: 3 cột + dải streak 7 ô.
class _ReadingPanel extends StatelessWidget {
  final int novels, chapters, streak;
  const _ReadingPanel(
      {required this.novels, required this.chapters, required this.streak});

  @override
  Widget build(BuildContext context) {
    Widget cell(String v, String label, {Color c = Neo.text}) => Expanded(
          child: Column(children: [
            Text(v, style: Neo.mono(22, color: c, weight: FontWeight.w600)),
            const SizedBox(height: 3),
            Text(label.toUpperCase(), style: Neo.mono(8, spacing: 2)),
          ]),
        );
    return NeoPanel(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
      child: Column(children: [
        Row(children: [
          cell('$novels', 'đang đọc'),
          Container(width: 1, height: 34, color: Neo.faint),
          cell('$chapters', 'chương đã đọc'),
          Container(width: 1, height: 34, color: Neo.faint),
          cell('$streak', 'ngày streak', c: streak > 0 ? Neo.plasma : Neo.text),
        ]),
        const SizedBox(height: 14),
        Container(height: 1, color: Neo.faint),
        const SizedBox(height: 12),
        Row(children: [
          Icon(Icons.local_fire_department,
              size: 16, color: streak > 0 ? Neo.plasma : Neo.dim),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
                streak > 0 ? 'CHUỖI $streak NGÀY LIÊN TIẾP' : 'CHƯA CÓ CHUỖI ĐỌC',
                style: Neo.mono(9, spacing: 1.5)),
          ),
          for (var i = 0; i < 7; i++)
            Container(
              margin: const EdgeInsets.only(left: 5),
              width: 13, height: 13,
              color: i < streak ? Neo.plasma.withValues(alpha: 0.85) : Neo.faint,
            ),
        ]),
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
        child: Text('// ${text.toUpperCase()}',
            style: Neo.mono(9, color: Neo.cyan, spacing: 3)),
      );
}

class _TileGroup extends StatelessWidget {
  final List<Widget> children;
  const _TileGroup({required this.children});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Neo.surface,
      clipBehavior: Clip.antiAlias,
      shape: const NeoCutBorder(cut: Neo.cutSm, side: BorderSide(color: Neo.faint)),
      child: Column(children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0)
            Divider(height: 1, thickness: 1, indent: 52,
                color: Neo.faint.withValues(alpha: 0.8)),
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
    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(vertical: 1),
      leading: Icon(icon, size: 21, color: Neo.dim),
      title: Text(label, style: const TextStyle(color: Neo.text, fontSize: 15)),
      trailing: const Icon(Icons.chevron_right, size: 18, color: Neo.dim),
      onTap: onTap,
    );
  }
}
