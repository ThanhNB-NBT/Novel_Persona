import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data.dart';
import '../cultivation/pixel.dart';

/// Sửa hồ sơ: tên hiển thị + chọn avatar preset (emoji, không cần upload ảnh)
/// + chọn biểu tượng xoay của tab Tu Tiên (lưu cục bộ, đổi ngay tức thì).
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});
  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _name = TextEditingController();
  String? _avatar;
  bool _init = false;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tên hiển thị không được để trống')));
      return;
    }
    setState(() => _saving = true);
    await updateProfile(displayName: name, avatarUrl: _avatar ?? '');
    ref.invalidate(profileProvider);
    if (mounted) {
      context.pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Đã lưu hồ sơ')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Sửa thông tin')),
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (p) {
          // nạp giá trị hiện tại 1 lần (không đè khi user đang gõ)
          if (!_init) {
            _name.text = (p?['display_name'] as String?) ??
                sb.auth.currentUser?.email?.split('@').first ??
                '';
            final a = p?['avatar_url'] as String?;
            _avatar = (a != null && avatarPresets.contains(a)) ? a : null;
            _init = true;
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              Center(child: _bigAvatar(cs)),
              const SizedBox(height: 24),
              Text('Tên hiển thị', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              TextField(
                controller: _name,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _save(),
                decoration: const InputDecoration(
                    hintText: 'Ví dụ: Bạn đọc', isDense: true),
              ),
              const SizedBox(height: 24),
              Text('Ảnh đại diện', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [for (final e in avatarPresets) _avatarChoice(e, cs)],
              ),
              const SizedBox(height: 24),
              Text('Biểu tượng tab Tu Tiên',
                  style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              Text('Đĩa xoay giữa thanh điều hướng — đổi là thấy ngay.',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              // đổi ngay (lưu cục bộ) — không đợi nút Lưu như tên/avatar (server)
              Consumer(builder: (context, ref, _) {
                final cur = ref.watch(tabEmblemProvider);
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final e in tabEmblems) _emblemChoice(e, cur, cs, ref),
                  ],
                );
              }),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Lưu'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _bigAvatar(ColorScheme cs) {
    final name = _name.text.trim();
    final initial = name.isNotEmpty ? name.characters.first.toUpperCase() : '?';
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: [cs.primary, cs.tertiary]),
      ),
      alignment: Alignment.center,
      child: _avatar != null
          ? Text(_avatar!, style: const TextStyle(fontSize: 48))
          : Text(initial,
              style: Theme.of(context)
                  .textTheme
                  .displaySmall
                  ?.copyWith(color: Colors.white)),
    );
  }

  Widget _avatarChoice(String emoji, ColorScheme cs) {
    final sel = _avatar == emoji;
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: () => setState(() => _avatar = sel ? null : emoji),
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: sel ? cs.primaryContainer : cs.surface,
          border: Border.all(
              color: sel ? cs.primary : cs.outlineVariant, width: sel ? 2 : 1),
        ),
        alignment: Alignment.center,
        child: Text(emoji, style: const TextStyle(fontSize: 26)),
      ),
    );
  }

  /// Ô chọn emblem: đĩa nhấn giống hệt dock (xem trước), vòng nhấn khi chọn.
  Widget _emblemChoice(String key, String cur, ColorScheme cs, WidgetRef ref) {
    final sel = cur == key;
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: () => ref.read(tabEmblemProvider.notifier).set(key),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
              color: sel ? cs.primary : Colors.transparent, width: 2),
        ),
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [cs.primary, cs.primary.withValues(alpha: 0.8)]),
            border: Border.all(color: cs.surface.withValues(alpha: 0.9), width: 2),
          ),
          alignment: Alignment.center,
          child: PixelIcon(key, grade: 5, size: 26),
        ),
      ),
    );
  }
}
