import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data.dart';
import '../neo_theme.dart';
import '../neo_widgets.dart';

const _typeLabels = {
  'person': 'Nhân vật',
  'place': 'Địa danh',
  'sect': 'Môn phái',
  'item': 'Vật phẩm',
  'skill': 'Chiêu thức',
  'other': 'Khác',
};

/// Glossary Hán-Việt — logic port nguyên từ app cũ.
class GlossaryScreen extends ConsumerWidget {
  final int novelId;
  const GlossaryScreen({super.key, required this.novelId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final terms = ref.watch(glossaryProvider(novelId));
    void refresh() => ref.invalidate(glossaryProvider(novelId));

    return NeoScaffold(
      body: SafeArea(
        child: Column(children: [
          NeoAppBar(title: 'Thuật ngữ', actions: [
            IconButton(
              tooltip: 'Vá các chương đã dịch bằng thuật ngữ mới',
              icon: const Icon(Icons.healing_outlined, color: Neo.text, size: 22),
              onPressed: () async {
                await requestPatch(novelId);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Đã xếp hàng vá chương — worker sẽ xử lý sớm')));
                }
              },
            ),
            IconButton(
              tooltip: 'Thêm thuật ngữ',
              icon: const Icon(Icons.add, color: Neo.cyan, size: 24),
              onPressed: () => _showTermDialog(context, onDone: refresh),
            ),
          ]),
          Expanded(
            child: terms.when(
              loading: () => const NeoLoading(label: 'NẠP TỪ ĐIỂN'),
              error: (e, _) => NeoMessage('Lỗi: $e', error: true),
              data: (list) {
                if (sb.auth.currentUser == null) {
                  return Center(
                    child: SizedBox(
                      width: 260,
                      child: NeoButton(
                          label: 'ĐĂNG NHẬP ĐỂ QUẢN LÝ',
                          onPressed: () => context.push('/login')),
                    ),
                  );
                }
                final pending = list.where((t) => t['approved'] != true).toList();
                final approved = list.where((t) => t['approved'] == true).toList();
                if (list.isEmpty) {
                  return const NeoMessage('CHƯA CÓ THUẬT NGỮ NÀO\nBẤM + ĐỂ THÊM');
                }
                return ListView(
                  padding: const EdgeInsets.only(bottom: 40),
                  children: [
                    if (pending.isNotEmpty) ...[
                      NeoSectionHeader('Gợi ý chờ duyệt (${pending.length})'),
                      for (final t in pending) _PendingTile(term: t, onChanged: refresh),
                    ],
                    NeoSectionHeader('Đã áp dụng (${approved.length})'),
                    for (final t in approved)
                      ListTile(
                        title: Text('${t['term_zh'] ?? '(?)'} → ${t['correct_vi']}',
                            style: const TextStyle(color: Neo.text, fontSize: 15)),
                        subtitle: Text(
                            [
                              _typeLabels[t['term_type']] ?? t['term_type'],
                              if (t['wrong_vi'] != null) 'không dịch: "${t['wrong_vi']}"',
                              if (t['scope'] == 'global') 'toàn cục',
                            ].join(' · '),
                            style: Neo.mono(10)),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                            tooltip: 'Báo cáo dịch sai',
                            icon: const Icon(Icons.flag_outlined, size: 20, color: Neo.dim),
                            onPressed: () => _reportTerm(context, t['id']),
                          ),
                          IconButton(
                            tooltip: 'Sửa',
                            icon: const Icon(Icons.edit_outlined, size: 20, color: Neo.dim),
                            onPressed: () =>
                                _showTermDialog(context, term: t, onDone: refresh),
                          ),
                        ]),
                      ),
                  ],
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  void _reportTerm(BuildContext context, int termId) {
    if (sb.auth.currentUser == null) {
      context.push('/login');
      return;
    }
    final reason = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Neo.surface,
        shape: const NeoCutBorder(side: BorderSide(color: Neo.faint)),
        title: Text('BÁO CÁO DỊCH SAI',
            style: Neo.mono(13, color: Neo.text, weight: FontWeight.w700)),
        content: TextField(
          controller: reason,
          autofocus: true,
          style: const TextStyle(color: Neo.text),
          decoration: const InputDecoration(
              labelText: 'Lý do (không bắt buộc)',
              hintText: 'vd: dịch sai nghĩa, sai tên nhân vật…'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: Text('HUỶ', style: Neo.mono(11, color: Neo.dim))),
          TextButton(
            onPressed: () async {
              await reportTerm(termId, novelId, reason.text.trim());
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Đã gửi báo cáo — admin sẽ xem lại')));
              }
            },
            child: Text('GỬI', style: Neo.mono(11, color: Neo.cyan, weight: FontWeight.w700)),
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
        backgroundColor: Neo.surface,
        shape: const NeoCutBorder(side: BorderSide(color: Neo.faint)),
        title: Text(term == null ? 'THÊM THUẬT NGỮ' : 'SỬA THUẬT NGỮ',
            style: Neo.mono(13, color: Neo.cyan, weight: FontWeight.w700, spacing: 2)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: zh,
            style: const TextStyle(color: Neo.text),
            decoration: const InputDecoration(labelText: 'Từ gốc (tiếng Trung)'),
          ),
          TextField(
            controller: vi,
            style: const TextStyle(color: Neo.text),
            decoration: const InputDecoration(labelText: 'Bản dịch đúng *'),
            autofocus: term != null,
          ),
          TextField(
            controller: wrong,
            style: const TextStyle(color: Neo.text),
            decoration: const InputDecoration(
                labelText: 'Bản dịch sai (nếu có)',
                helperText: 'Dùng để vá chương cũ: sai → đúng'),
          ),
          const SizedBox(height: 8),
          StatefulBuilder(
            builder: (_, setState) => DropdownButtonFormField<String>(
              initialValue: type,
              dropdownColor: Neo.surface2,
              style: const TextStyle(color: Neo.text),
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
              onPressed: () async {
                await deleteTerm(term['id']);
                if (ctx.mounted) Navigator.pop(ctx);
                onDone();
              },
              child: Text('XÓA', style: Neo.mono(11, color: Neo.danger)),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: Text('HỦY', style: Neo.mono(11, color: Neo.dim))),
          TextButton(
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
            child: Text('LƯU', style: Neo.mono(11, color: Neo.cyan, weight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

/// Term LLM gợi ý (approved=false): duyệt nhanh hoặc bỏ.
class _PendingTile extends StatelessWidget {
  final Rec term;
  final VoidCallback onChanged;
  const _PendingTile({required this.term, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        decoration: ShapeDecoration(
          color: Neo.plasma.withValues(alpha: 0.08),
          shape: NeoCutBorder(
              cut: Neo.cutSm,
              side: BorderSide(color: Neo.plasma.withValues(alpha: 0.4))),
        ),
        child: ListTile(
          title: Text('${term['term_zh'] ?? '(?)'} → ${term['correct_vi']}',
              style: const TextStyle(color: Neo.text, fontSize: 15)),
          subtitle: Text(_typeLabels[term['term_type']] ?? '${term['term_type']}',
              style: Neo.mono(10)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              tooltip: 'Duyệt — dùng cho các chương dịch sau',
              icon: const Icon(Icons.check_circle_outline, color: Neo.cyan),
              onPressed: () async {
                await updateTerm(term['id'], {'approved': true});
                onChanged();
              },
            ),
            IconButton(
              tooltip: 'Bỏ gợi ý',
              icon: const Icon(Icons.close, color: Neo.dim),
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
