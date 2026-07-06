import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data.dart';
import '../../widgets.dart';

const _typeLabels = {
  'person': 'Nhân vật',
  'place': 'Địa danh',
  'sect': 'Môn phái',
  'item': 'Vật phẩm',
  'skill': 'Chiêu thức',
  'other': 'Khác',
};

class GlossaryScreen extends ConsumerWidget {
  final int novelId;
  const GlossaryScreen({super.key, required this.novelId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final terms = ref.watch(glossaryProvider(novelId));
    void refresh() => ref.invalidate(glossaryProvider(novelId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Thuật ngữ'),
        actions: [
          IconButton(
            tooltip: 'Vá các chương đã dịch bằng thuật ngữ mới',
            icon: const Icon(Icons.healing_outlined),
            onPressed: () async {
              await requestPatch(novelId);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Đã xếp hàng vá chương — worker sẽ xử lý sớm')));
              }
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Thêm thuật ngữ',
        onPressed: () => _showTermDialog(context, onDone: refresh),
        child: const Icon(Icons.add),
      ),
      body: terms.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (list) {
          if (sb.auth.currentUser == null) {
            return Center(
              child: FilledButton(
                onPressed: () => context.push('/login'),
                child: const Text('Đăng nhập để quản lý thuật ngữ'),
              ),
            );
          }
          final pending = list.where((t) => t['approved'] != true).toList();
          final approved = list.where((t) => t['approved'] == true).toList();
          if (list.isEmpty) {
            return const Center(
                child: Text('Chưa có thuật ngữ nào.\nBấm + để thêm.',
                    textAlign: TextAlign.center));
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              if (pending.isNotEmpty) ...[
                SectionHeader('Gợi ý chờ duyệt (${pending.length})'),
                for (final t in pending) _PendingTile(term: t, onChanged: refresh),
              ],
              SectionHeader('Đã áp dụng (${approved.length})'),
              for (final t in approved)
                ListTile(
                  title: Text('${t['term_zh'] ?? '(?)'} → ${t['correct_vi']}'),
                  subtitle: Text([
                    _typeLabels[t['term_type']] ?? t['term_type'],
                    if (t['wrong_vi'] != null) 'không dịch: "${t['wrong_vi']}"',
                    if (t['scope'] == 'global') 'toàn cục',
                  ].join(' · ')),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      tooltip: 'Báo cáo dịch sai',
                      icon: const Icon(Icons.flag_outlined, size: 20),
                      onPressed: () => _reportTerm(context, t['id']),
                    ),
                    IconButton(
                      tooltip: 'Sửa',
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      onPressed: () =>
                          _showTermDialog(context, term: t, onDone: refresh),
                    ),
                  ]),
                ),
            ],
          );
        },
      ),
    );
  }

  /// Báo cáo term dịch sai (góp ý auto-duyệt; admin chỉ soi khi có báo cáo).
  void _reportTerm(BuildContext context, int termId) {
    if (sb.auth.currentUser == null) {
      context.push('/login');
      return;
    }
    final reason = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Báo cáo dịch sai'),
        content: TextField(
          controller: reason,
          autofocus: true,
          decoration: const InputDecoration(
              labelText: 'Lý do (không bắt buộc)',
              hintText: 'vd: dịch sai nghĩa, sai tên nhân vật…'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Huỷ')),
          FilledButton(
            onPressed: () async {
              await reportTerm(termId, novelId, reason.text.trim());
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Đã gửi báo cáo — admin sẽ xem lại')));
              }
            },
            child: const Text('Gửi'),
          ),
        ],
      ),
    );
  }

  void _showTermDialog(BuildContext context, {Rec? term, required VoidCallback onDone}) {
    final zh = TextEditingController(text: term?['term_zh'] ?? '');
    final vi = TextEditingController(text: term?['correct_vi'] ?? '');
    final wrong = TextEditingController(text: term?['wrong_vi'] ?? '');
    String type = term?['term_type'] ?? 'other';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(term == null ? 'Thêm thuật ngữ' : 'Sửa thuật ngữ'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: zh,
            decoration: const InputDecoration(labelText: 'Từ gốc (tiếng Trung)'),
          ),
          TextField(
            controller: vi,
            decoration: const InputDecoration(labelText: 'Bản dịch đúng *'),
            autofocus: term != null,
          ),
          TextField(
            controller: wrong,
            decoration: const InputDecoration(
                labelText: 'Bản dịch sai (nếu có)',
                helperText: 'Dùng để vá chương cũ: sai → đúng'),
          ),
          const SizedBox(height: 8),
          StatefulBuilder(
            builder: (_, setState) => DropdownButtonFormField<String>(
              initialValue: type,
              decoration: const InputDecoration(labelText: 'Loại'),
              items: [
                for (final e in _typeLabels.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => type = v ?? 'other'),
            ),
          ),
        ]),
        actions: [
          if (term != null)
            TextButton(
              style: TextButton.styleFrom(
                  foregroundColor: Theme.of(ctx).colorScheme.error),
              onPressed: () async {
                await deleteTerm(term['id']);
                if (ctx.mounted) Navigator.pop(ctx);
                onDone();
              },
              child: const Text('Xóa'),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          FilledButton(
            onPressed: () async {
              if (vi.text.trim().isEmpty) return;
              final fields = {
                'term_zh': zh.text.trim().isEmpty ? null : zh.text.trim(),
                'correct_vi': vi.text.trim(),
                'wrong_vi': wrong.text.trim().isEmpty ? null : wrong.text.trim(),
                'term_type': type,
              };
              if (term == null) {
                await sb.from('glossary_terms').insert({
                  ...fields,
                  'novel_id': novelId,
                  'approved': true,
                  'created_by': sb.auth.currentUser!.id,
                });
              } else {
                await updateTerm(term['id'], fields);
              }
              if (ctx.mounted) Navigator.pop(ctx);
              onDone();
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }
}

/// Term do LLM gợi ý (approved=false): duyệt nhanh hoặc bỏ.
class _PendingTile extends StatelessWidget {
  final Rec term;
  final VoidCallback onChanged;
  const _PendingTile({required this.term, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        decoration: BoxDecoration(
          color: cs.primaryContainer.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(16),
        ),
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('${term['term_zh'] ?? '(?)'} → ${term['correct_vi']}'),
          subtitle: Text(_typeLabels[term['term_type']] ?? '${term['term_type']}'),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              tooltip: 'Duyệt — dùng cho các chương dịch sau',
              icon: Icon(Icons.check_circle_outline, color: cs.primary),
              onPressed: () async {
                await updateTerm(term['id'], {'approved': true});
                onChanged();
              },
            ),
            IconButton(
              tooltip: 'Bỏ gợi ý',
              icon: Icon(Icons.close, color: cs.onSurfaceVariant),
              onPressed: () async {
                await deleteTerm(term['id']);
                onChanged();
              },
            ),
          ]),
        ),
      ),
    );
  }
}
