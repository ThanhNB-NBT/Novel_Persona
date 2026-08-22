import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data.dart';
import '../../widgets.dart';
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
    if (_saving) return; // chặn double-tap: 2 lần updateProfile chồng nhau
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tên hiển thị không được để trống')));
      return;
    }
    setState(() => _saving = true);
    try {
      await updateProfile(displayName: name, avatarUrl: _avatar ?? '');
      ref.invalidate(profileProvider);
      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Đã lưu hồ sơ')));
      }
    } catch (e) {
      // lỗi mạng/RLS phải báo ra chứ không nuốt — nếu không nút Lưu kẹt vĩnh viễn
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Lỗi lưu hồ sơ: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Hồ sơ của bạn')),
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AppError(e, onRetry: () => ref.invalidate(profileProvider)),
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
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(children: [
                  _bigAvatar(cs),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('HỒ SƠ CÁ NHÂN', style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: cs.primary, letterSpacing: 1.2)),
                    Text('Chọn một diện mạo hợp với bạn',
                        style: Theme.of(context).textTheme.titleMedium),
                  ])),
                ]),
              ),
              const SizedBox(height: 16),
              Text('Tên hiển thị', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              TextField(
                controller: _name,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _save(),
                decoration: const InputDecoration(
                    hintText: 'Ví dụ: Bạn đọc', isDense: true),
              ),
              const SizedBox(height: 18),
              Text('Ảnh đại diện', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 12),
              SizedBox(
                height: 48,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: avatarPresets.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => _avatarChoice(avatarPresets[i], cs),
                ),
              ),
              const SizedBox(height: 18),
              Text('Biểu tượng tab Tu Tiên',
                  style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              // đổi ngay (lưu cục bộ) — không đợi nút Lưu như tên/avatar (server)
              Consumer(builder: (context, ref, _) {
                final cur = ref.watch(tabEmblemProvider);
                return SizedBox(
                  height: 48,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: tabEmblems.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (_, i) => _emblemChoice(tabEmblems[i], cur, cs, ref),
                  ),
                );
              }),
              const SizedBox(height: 24),
              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check_rounded),
                  label: Text(_saving ? 'Đang lưu' : 'Lưu thay đổi'),
                ),
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
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: cs.surface,
        border: Border.all(color: cs.primary.withValues(alpha: 0.35)),
      ),
      alignment: Alignment.center,
      // height:1 — bỏ leading của font emoji (mặc định đẩy glyph lệch lên trên)
      child: _avatar != null
          ? Text(_avatar!, style: const TextStyle(fontSize: 32, height: 1))
          : Text(initial,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(color: cs.primary)),
    );
  }

  Widget _avatarChoice(String emoji, ColorScheme cs) {
    final sel = _avatar == emoji;
    return InkWell(
      customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onTap: () => setState(() => _avatar = sel ? null : emoji),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: sel ? cs.primaryContainer : cs.surface,
          border: Border.all(
              color: sel ? cs.primary : cs.outlineVariant, width: sel ? 2 : 1),
        ),
        alignment: Alignment.center,
        child: Text(emoji, style: const TextStyle(fontSize: 23, height: 1)),
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
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
              color: sel ? cs.primary : Colors.transparent, width: 2),
        ),
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [cs.primary, cs.primary.withValues(alpha: 0.8)]),
            border: Border.all(color: cs.surface.withValues(alpha: 0.9), width: 2),
          ),
          alignment: Alignment.center,
          child: PixelIcon(key, grade: 5, size: 23),
        ),
      ),
    );
  }
}
