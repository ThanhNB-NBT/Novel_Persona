import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data.dart';

/// Sửa hồ sơ: tên hiển thị + chọn avatar preset (emoji, không cần upload ảnh).
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
}
