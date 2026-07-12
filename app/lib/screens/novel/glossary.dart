import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data.dart';
import '../../hanviet.dart';

const _typeLabels = {
  'person': 'Nhân vật',
  'place': 'Địa danh',
  'sect': 'Môn phái',
  'item': 'Vật phẩm',
  'skill': 'Chiêu thức',
  'other': 'Khác',
};

class GlossaryScreen extends ConsumerStatefulWidget {
  final int novelId;
  const GlossaryScreen({super.key, required this.novelId});
  @override
  ConsumerState<GlossaryScreen> createState() => _GlossaryScreenState();
}

class _GlossaryScreenState extends ConsumerState<GlossaryScreen> {
  // chế độ chọn hàng loạt để xoá (LLM có thể gợi ý cả trăm term sai — xoá tay từng cái quá cực)
  bool _selecting = false;
  final Set<int> _sel = {};
  // hai mục có thể cả trăm dòng — cho thu gọn để khỏi kéo mệt
  bool _openPending = true;
  bool _openApproved = true;

  int get novelId => widget.novelId;

  @override
  Widget build(BuildContext context) {
    final terms = ref.watch(glossaryProvider(novelId));
    void refresh() => ref.invalidate(glossaryProvider(novelId));

    return Scaffold(
      appBar: _selecting
          ? _selectAppBar(terms.value ?? const [])
          : AppBar(
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
                IconButton(
                  tooltip: 'Chọn để xoá hàng loạt',
                  icon: const Icon(Icons.checklist_rounded),
                  onPressed: () => setState(() {
                    _selecting = true;
                    _sel.clear();
                  }),
                ),
              ],
            ),
      floatingActionButton: _selecting
          ? null
          : FloatingActionButton(
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
                _toggleHeader('Gợi ý chờ duyệt (${pending.length})', _openPending,
                    () => setState(() => _openPending = !_openPending)),
                if (_openPending)
                  for (final t in pending)
                    if (_selecting)
                      _checkTile(t)
                    else
                      _PendingTile(
                        term: t,
                        onChanged: refresh,
                        onEdit: () =>
                            _showTermDialog(context, term: t, onDone: refresh),
                      ),
              ],
              _toggleHeader('Đã áp dụng (${approved.length})', _openApproved,
                  () => setState(() => _openApproved = !_openApproved)),
              if (_openApproved)
              for (final t in approved)
                if (_selecting)
                  _checkTile(t)
                else
                ListTile(
                  title: Text('${t['term_zh'] ?? '(?)'} → ${t['correct_vi']}'),
                  subtitle: Text([
                    _typeLabels[t['term_type']] ?? t['term_type'],
                    if (t['wrong_vi'] != null) 'không dịch: "${t['wrong_vi']}"',
                    if (t['narrator_term'] != null) 'kể: ${t['narrator_term']}',
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

  /// Tiêu đề mục bấm được để thu gọn/mở (danh sách dài cả trăm dòng).
  Widget _toggleHeader(String title, bool open, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 12, 10),
          child: Row(children: [
            Expanded(
                child: Text(title,
                    style: Theme.of(context).textTheme.headlineSmall)),
            Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ]),
        ),
      );

  /// AppBar chế độ chọn: đếm số đã chọn + Chọn tất cả + Xoá.
  AppBar _selectAppBar(List<Rec> all) => AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => setState(() {
            _selecting = false;
            _sel.clear();
          }),
        ),
        title: Text('Đã chọn ${_sel.length}'),
        actions: [
          IconButton(
            tooltip: 'Chọn tất cả',
            icon: const Icon(Icons.select_all_rounded),
            onPressed: () =>
                setState(() => _sel.addAll(all.map((t) => t['id'] as int))),
          ),
          IconButton(
            tooltip: 'Xoá đã chọn',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: _sel.isEmpty ? null : _deleteSelected,
          ),
        ],
      );

  Widget _checkTile(Rec t) {
    final id = t['id'] as int;
    return CheckboxListTile(
      value: _sel.contains(id),
      onChanged: (_) => setState(
          () => _sel.contains(id) ? _sel.remove(id) : _sel.add(id)),
      controlAffinity: ListTileControlAffinity.leading,
      title: Text('${t['term_zh'] ?? '(?)'} → ${t['correct_vi']}'),
      subtitle: Text(_typeLabels[t['term_type']] ?? '${t['term_type']}'),
      dense: true,
    );
  }

  Future<void> _deleteSelected() async {
    final n = _sel.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Xoá $n thuật ngữ?'),
        content: const Text(
            'Chương đã dịch giữ nguyên; các chương dịch sau sẽ không dùng những term này nữa.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xoá'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await deleteTerms(_sel.toList());
    if (!mounted) return;
    setState(() {
      _selecting = false;
      _sel.clear();
    });
    ref.invalidate(glossaryProvider(novelId));
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Đã xoá $n thuật ngữ')));
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
    final narr = TextEditingController(text: term?['narrator_term'] ?? '');
    String type = term?['term_type'] ?? 'other';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(term == null ? 'Thêm thuật ngữ' : 'Sửa thuật ngữ'),
        content: StatefulBuilder(builder: (_, setState) {
          // phiên âm Hán-Việt tra bảng từ ô chữ Trung — như form sửa ở màn đọc,
          // người không biết tiếng Trung bấm chip là điền được bản chuẩn
          final z = zh.text.trim();
          String? hanFill;
          if (z.isNotEmpty) {
            final filled = z.replaceAllMapped(
                RegExp(r'[㐀-䶿一-鿿]+'), (m) => hanVietOf(m.group(0)!) ?? m.group(0)!);
            if (filled != z) hanFill = filled;
          }
          return Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: zh,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Từ gốc (tiếng Trung)'),
            ),
            TextField(
              controller: vi,
              decoration: const InputDecoration(labelText: 'Bản dịch đúng *'),
              autofocus: term != null,
            ),
            if (hanFill case final hf?)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: ActionChip(
                    visualDensity: VisualDensity.compact,
                    side: BorderSide(
                        color: Theme.of(ctx).colorScheme.primary.withValues(alpha: 0.6)),
                    label: Text('tra bảng ⇒ $hf',
                        style: Theme.of(ctx).textTheme.labelMedium?.copyWith(
                            color: Theme.of(ctx).colorScheme.primary)),
                    onPressed: () => setState(() {
                      vi.text = hf;
                      vi.selection =
                          TextSelection.collapsed(offset: vi.text.length);
                    }),
                  ),
                ),
              ),
            TextField(
              controller: wrong,
              decoration: const InputDecoration(
                  labelText: 'Bản dịch sai (nếu có)',
                  helperText: 'Dùng để vá chương cũ: sai → đúng'),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: type,
              decoration: const InputDecoration(labelText: 'Loại'),
              items: [
                for (final e in _typeLabels.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => type = v ?? 'other'),
            ),
            // narrator reference (Q1): worker đọc cột này khi dịch — chỉ có nghĩa với nhân vật
            if (type == 'person') ...[
              const SizedBox(height: 8),
              TextField(
                controller: narr,
                decoration: const InputDecoration(
                    labelText: 'Người kể gọi (không bắt buộc)',
                    hintText: 'hắn / nàng / y / lão / tên riêng',
                    helperText: 'Cách LỜI KỂ gọi nhân vật này — bỏ trống = mặc định'),
              ),
            ],
          ]);
        }),
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
                // đổi loại khỏi person thì xoá luôn cách gọi cũ
                'narrator_term': type == 'person' && narr.text.trim().isNotEmpty
                    ? narr.text.trim()
                    : null,
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

/// Term do LLM gợi ý (approved=false): duyệt nhanh hoặc bỏ; bấm vào dòng để sửa.
class _PendingTile extends StatelessWidget {
  final Rec term;
  final VoidCallback onChanged;
  final VoidCallback onEdit;
  const _PendingTile(
      {required this.term, required this.onChanged, required this.onEdit});

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
          onTap: onEdit, // sửa trước rồi mới duyệt — khỏi duyệt bản LLM phiên sai
          title: Text('${term['term_zh'] ?? '(?)'} → ${term['correct_vi']}'),
          // kèm phiên âm tra bảng khi LỆCH với gợi ý — người không biết tiếng Trung
          // vẫn phát hiện được LLM phiên sai trước khi duyệt
          subtitle: Text([
            _typeLabels[term['term_type']] ?? '${term['term_type']}',
            if (hanVietOf('${term['term_zh'] ?? ''}') case final hv?
                when hv != '${term['correct_vi']}')
              'tra bảng: $hv',
          ].join(' · ')),
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
