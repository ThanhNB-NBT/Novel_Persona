import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data.dart';
import '../neo_theme.dart';
import '../neo_widgets.dart';

/// Sửa hồ sơ: tên hiển thị + avatar preset (logic port từ app cũ).
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

    return NeoScaffold(
      body: SafeArea(
        child: Column(children: [
          const NeoAppBar(title: 'Sửa thông tin'),
          Expanded(
            child: profile.when(
              loading: () => const NeoLoading(),
              error: (e, _) => NeoMessage('Lỗi: $e', error: true),
              data: (p) {
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
                    Center(child: _bigAvatar()),
                    const SizedBox(height: 24),
                    Text('TÊN HIỂN THỊ', style: Neo.mono(9, spacing: 3)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _name,
                      textInputAction: TextInputAction.done,
                      style: TextStyle(color: Neo.text),
                      onSubmitted: (_) => _save(),
                      decoration: const InputDecoration(
                          hintText: 'Ví dụ: Bạn đọc', isDense: true),
                    ),
                    const SizedBox(height: 24),
                    Text('ẢNH ĐẠI DIỆN', style: Neo.mono(9, spacing: 3)),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [for (final e in avatarPresets) _avatarChoice(e)],
                    ),
                    const SizedBox(height: 32),
                    NeoButton(label: 'Lưu', busy: _saving, onPressed: _save),
                  ],
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  Widget _bigAvatar() {
    final name = _name.text.trim();
    final initial = name.isNotEmpty ? name.characters.first.toUpperCase() : '?';
    return Container(
      width: 96, height: 96,
      decoration: ShapeDecoration(
        color: Neo.surface2,
        shape: NeoCutBorder(side: BorderSide(color: Neo.cyan)),
        shadows: Neo.glow(Neo.cyan, blur: 14, alpha: 0.18),
      ),
      alignment: Alignment.center,
      child: _avatar != null
          ? Text(_avatar!, style: const TextStyle(fontSize: 48))
          : Text(initial, style: Neo.display(40, color: Neo.cyan)),
    );
  }

  Widget _avatarChoice(String emoji) {
    final sel = _avatar == emoji;
    return InkWell(
      onTap: () => setState(() => _avatar = sel ? null : emoji),
      child: Container(
        width: 56, height: 56,
        decoration: ShapeDecoration(
          color: sel ? Neo.cyan.withValues(alpha: 0.12) : Neo.surface,
          shape: NeoCutBorder(
              cut: Neo.cutSm,
              side: BorderSide(color: sel ? Neo.cyan : Neo.faint, width: sel ? 1.6 : 1)),
        ),
        alignment: Alignment.center,
        child: Text(emoji, style: const TextStyle(fontSize: 26)),
      ),
    );
  }
}
