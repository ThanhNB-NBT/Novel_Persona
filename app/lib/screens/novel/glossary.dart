import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data.dart';
import '../../hanviet.dart';
import '../../offline.dart';
import '../../widgets.dart';

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
                // sửa novels cần policy admin_write_novels → chỉ hiện cho admin
                if (ref.watch(isAdminProvider).value ?? false)
                  IconButton(
                    tooltip: 'Văn phong dịch (style bible)',
                    icon: const Icon(Icons.brush_outlined),
                    onPressed: _showStyleDialog,
                  ),
                IconButton(
                  tooltip: 'Vá chương cũ bằng cặp "bản dịch sai → đúng"',
                  icon: const Icon(Icons.healing_outlined),
                  onPressed: () => _confirmAndPatch(terms.value ?? const []),
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
      body: Column(children: [
        _PatchBanner(novelId),
        Expanded(child: terms.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AppError(e, onRetry: () => ref.invalidate(glossaryProvider(novelId))),
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
      )),
      ]),
    );
  }

  /// Xác nhận trước khi vá: hiện luôn "X/Y term đã duyệt có bản sai" — vì vá chỉ
  /// thay được từ CÓ bản dịch sai; term chỉ được duyệt (không bản sai) phải dịch lại
  /// chương mới đổi. Nêu rõ để khỏi tưởng duyệt term là chương cũ tự sửa.
  Future<void> _confirmAndPatch(List<Rec> terms) async {
    final approved = terms.where((t) => t['approved'] == true).length;
    final withWrong = terms
        .where((t) =>
            t['approved'] == true &&
            (t['wrong_vi'] as String?)?.trim().isNotEmpty == true)
        .length;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Vá chương đã dịch'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$withWrong/$approved thuật ngữ đã duyệt có "bản dịch sai".',
                style: tt.bodyLarge),
            const SizedBox(height: 10),
            Text(
              withWrong == 0
                  ? 'Vá chỉ thay từ CÓ bản dịch sai nên sẽ không đổi gì. Muốn chương cũ '
                      'theo thuật ngữ đã duyệt, hãy "Dịch lại" chương trong lúc đọc.'
                  : 'Chỉ $withWrong từ này được thay trong chương cũ. Term chỉ được duyệt '
                      '(không có bản sai) phải "Dịch lại" chương mới đổi theo.',
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(withWrong == 0 ? 'Vẫn vá' : 'Vá $withWrong từ'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await requestPatch(novelId);
    if (!mounted) return;
    ref.invalidate(latestPatchProvider(novelId));
    _pollPatch();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Đã xếp hàng vá — theo dõi tiến trình ở thanh trên')));
  }

  /// Poll trạng thái job vá vài lần sau khi bấm để thanh trên tự cập nhật
  /// pending → running → done (job vá chạy <2s nhưng có thể chờ hàng đợi chút).
  Future<void> _pollPatch() async {
    for (var i = 0; i < 12; i++) {
      await Future.delayed(const Duration(milliseconds: 1500));
      if (!mounted) return;
      ref.invalidate(latestPatchProvider(novelId));
      final rec = await ref.read(latestPatchProvider(novelId).future);
      final st = rec?['status'];
      if (st == 'failed') return;
      if (st == 'done') {
        await _syncOfflineAfterPatch();
        return;
      }
    }
  }

  /// Vá chạy trên SERVER, nhưng bản đã tải OFFLINE đọc từ máy (chapterProvider
  /// offline-first) nên vẫn là chữ cũ. Truyện có bản offline → tải lại để khớp bản
  /// vừa vá; chương online tự tươi khi mở lại nên không cần đụng.
  Future<void> _syncOfflineAfterPatch() async {
    if (!mounted || !await offlineStore.hasNovel(novelId)) return;
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
        const SnackBar(content: Text('Đang cập nhật bản offline theo thuật ngữ mới…')));
    try {
      final novel = await ref.read(novelProvider(novelId).future);
      await offlineStore.downloadNovel(novel);
      if (!mounted) return;
      ref.invalidate(chapterProvider); // reader (nếu đang mở) đọc lại bản local mới
      messenger.showSnackBar(
          const SnackBar(content: Text('Đã cập nhật bản offline')));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Vá xong nhưng chưa cập nhật được bản offline — thử tải lại ở mục Offline')));
    }
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

  /// Form sửa style bible (novels.translation_style) — giọng dịch của MỌI chương sau.
  /// Worker sinh tự động từ chương đầu được dịch; user sửa ở đây khi nó đoán sai.
  Future<void> _showStyleDialog() async {
    final messenger = ScaffoldMessenger.of(context);
    final Rec novel;
    try {
      novel = await ref.read(novelProvider(novelId).future);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Lỗi tải truyện: $e')));
      return;
    }
    if (!mounted) return;
    final raw = novel['translation_style'];
    final style = raw is Map ? raw : const {};
    String? pov = const ['ngôi ba', 'ngôi nhất'].contains(style['pov']) ? style['pov'] : null;
    String? hanViet = const ['đậm', 'vừa', 'nhạt'].contains(style['han_viet']) ? style['han_viet'] : null;
    final setting = TextEditingController(text: style['setting'] is String ? style['setting'] : '');
    final tone = TextEditingController(text: style['tone'] is String ? style['tone'] : '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Văn phong dịch'),
        content: StatefulBuilder(builder: (_, setState) {
          // scroll: bàn phím bật lên trên màn nhỏ thì cuộn thay vì tràn/cắt ô nhập
          return SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              initialValue: pov,
              decoration: const InputDecoration(labelText: 'Ngôi kể'),
              items: const [
                DropdownMenuItem(value: 'ngôi ba', child: Text('Ngôi ba')),
                DropdownMenuItem(value: 'ngôi nhất', child: Text('Ngôi nhất')),
              ],
              onChanged: (v) => setState(() => pov = v),
            ),
            TextField(
              controller: setting,
              maxLength: 80, // contract worker _clean_style: mỗi giá trị ≤80 ký tự
              decoration: const InputDecoration(
                  labelText: 'Bối cảnh', counterText: '',
                  hintText: 'tu tiên cổ đại / đô thị hiện đại / võng du...'),
            ),
            DropdownButtonFormField<String>(
              initialValue: hanViet,
              decoration: const InputDecoration(labelText: 'Mức Hán-Việt'),
              items: const [
                DropdownMenuItem(value: 'đậm', child: Text('Đậm — tu tiên/cổ trang')),
                DropdownMenuItem(value: 'vừa', child: Text('Vừa')),
                DropdownMenuItem(value: 'nhạt', child: Text('Nhạt — đô thị hiện đại')),
              ],
              onChanged: (v) => setState(() => hanViet = v),
            ),
            TextField(
              controller: tone,
              maxLength: 80,
              decoration: const InputDecoration(
                  labelText: 'Nhịp văn', counterText: '',
                  hintText: 'gọn / hài / lạnh / trang trọng / khẩu ngữ...'),
            ),
            const SizedBox(height: 10),
            Text('Để trống tất cả rồi Lưu → xoá hồ sơ, worker tự sinh lại từ chương 1.',
                style: Theme.of(ctx).textTheme.labelSmall?.copyWith(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
          ]));
        }),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Lưu')),
        ],
      ),
    );
    if (ok != true) return;
    // lưu tay thì BỎ src_chapter — còn giữ là housekeeping tưởng bản máy sinh
    // từ chương giữa và tái tạo đè mất (docs/ke-hoach-dich-chong-troi.md G4)
    final next = <String, dynamic>{
      'pov': ?pov,
      if (setting.text.trim().isNotEmpty) 'setting': setting.text.trim(),
      'han_viet': ?hanViet,
      if (tone.text.trim().isNotEmpty) 'tone': tone.text.trim(),
    };
    try {
      await updateNovelFields(novelId, {'translation_style': next.isEmpty ? null : next});
      if (mounted) ref.invalidate(novelProvider(novelId));
      messenger.showSnackBar(SnackBar(content: Text(next.isEmpty
          ? 'Đã xoá hồ sơ văn phong — worker sẽ sinh lại từ chương 1'
          : 'Đã lưu văn phong — áp dụng cho các chương dịch mới')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    }
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
          // scroll: form dài + bàn phím → cuộn thay vì tràn/cắt ô nhập
          return SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
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
          ]));
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
              // Khi chỉ sửa "Bản đúng", giữ lại bản cũ làm vế trái để job Vá
              // truyện biết chính xác phải thay chuỗi nào. Trước đây để trống ô
              // này khiến vá không làm gì với lỗi Việt cũ.
              final newCorrect = vi.text.trim();
              final oldCorrect = term == null ? '' : '${term['correct_vi'] ?? ''}'.trim();
              final typedWrong = wrong.text.trim();
              final fields = {
                'term_zh': zh.text.trim().isEmpty ? null : zh.text.trim(),
                'correct_vi': newCorrect,
                'wrong_vi': typedWrong.isNotEmpty
                    ? typedWrong
                    : oldCorrect.isNotEmpty && oldCorrect != newCorrect
                        ? oldCorrect
                        : null,
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

/// Thanh trạng thái vá trên đầu màn Thuật ngữ: hiện job vá gần nhất (đang vá /
/// đã vá N/M chương / lỗi). Ẩn khi truyện chưa vá lần nào.
class _PatchBanner extends ConsumerWidget {
  final int novelId;
  const _PatchBanner(this.novelId);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(latestPatchProvider(novelId)).value;
    if (s == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final status = s['status'];
    final running = status == 'pending' || status == 'running';
    final (IconData icon, Color color, String text) = switch (status) {
      'pending' || 'running' => (Icons.healing_outlined, cs.primary, 'Đang vá chương…'),
      'failed' => (Icons.error_outline, cs.error, 'Vá lỗi — thử lại'),
      _ => (
          Icons.check_circle_outline,
          cs.primary,
          'Đã vá ${s['result'] ?? 'xong'} · ${timeAgo(s['done_at'])}'
        ),
    };
    return Container(
      width: double.infinity,
      color: color.withValues(alpha: 0.10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color)),
        ),
        if (running)
          SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2, color: color)),
      ]),
    );
  }
}
