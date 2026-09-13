import 'package:flutter/material.dart';

import '../../../data.dart';
import '../../../theme.dart';
import '../../../widgets.dart';
import 'shared.dart';

/// Loại chuỗi model đang chọn — quyết định danh mục + có kèm trần hay không.
enum ModelListKind {
  gemini, // gemini_models: tên + trần RPM/TPM/RPD
  geminiMeta, // gemini_metadata_models: chỉ tên, trần lấy theo gemini_models
  nvidia, // llm_model: chỉ tên
}

ModelListKind? modelListKindOf(String key) => switch (key) {
      'gemini_models' => ModelListKind.gemini,
      'gemini_metadata_models' => ModelListKind.geminiMeta,
      'llm_model' => ModelListKind.nvidia,
      _ => null,
    };

typedef _Pick = ({String id, int rpm, int tpm, int rpd});

/// Bảng chọn chuỗi model: kéo để đổi thứ tự ưu tiên, bấm − để bỏ, bấm + để thêm từ danh mục
/// (có ghi chú + trần theo nhà cung cấp), bấm trần để sửa số. Trả chuỗi đúng định dạng worker
/// đọc (ngăn phẩy; gemini kèm `RPM/TPM/RPD`) hoặc null nếu huỷ.
Future<String?> showModelPicker(BuildContext context,
    {required ModelListKind kind, required String title, required String value}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.92,
      child: _ModelPicker(kind: kind, title: title, value: value),
    ),
  );
}

class _ModelPicker extends StatefulWidget {
  final ModelListKind kind;
  final String title, value;
  const _ModelPicker({required this.kind, required this.title, required this.value});

  @override
  State<_ModelPicker> createState() => _ModelPickerState();
}

class _ModelPickerState extends State<_ModelPicker> {
  late final List<_Pick> _picked;

  bool get _withLimits => widget.kind == ModelListKind.gemini;

  @override
  void initState() {
    super.initState();
    _picked = [
      for (final m in parseGeminiModels(widget.value))
        // chuỗi chỉ-tên (metadata/nvidia) parse ra trần mặc định — không dùng tới
        (id: m.name, rpm: m.rpm, tpm: m.tpm, rpd: m.rpd),
    ];
  }

  // danh mục theo loại: (id, ghi chú, trần nếu là Gemini)
  List<({String id, String note, LlmCatalogItem? g})> get _catalog => switch (widget.kind) {
        ModelListKind.nvidia => [for (final m in nvidiaCatalog) (id: m.id, note: m.note, g: null)],
        _ => [for (final m in geminiCatalog) (id: m.id, note: m.note, g: m)],
      };

  String? _noteOf(String id) => _catalog.where((c) => c.id == id).firstOrNull?.note;

  String _encode() => _picked
      .map((p) => _withLimits ? '${p.id} ${p.rpm}/${p.tpm}/${p.rpd}' : p.id)
      .join(',');

  void _add(String id) {
    final g = geminiCatalog.where((c) => c.id == id).firstOrNull;
    setState(() => _picked.add((
          id: id,
          rpm: g?.rpm ?? 5,
          tpm: g?.tpm ?? 250000,
          rpd: g?.rpd ?? 20,
        )));
  }

  Future<void> _addCustom() async {
    final ctrl = TextEditingController();
    final id = await showBlurDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Model khác'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'ID model',
            helperText: 'Đúng ID nhà cung cấp, vd gemini-3.1-flash-lite',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Huỷ')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Thêm')),
        ],
      ),
    );
    if (id == null || id.isEmpty || id.contains(RegExp(r'[\s,]'))) return;
    if (_picked.any((p) => p.id == id)) return;
    _add(id);
  }

  Future<void> _editLimits(int i) async {
    final p = _picked[i];
    final ctrls = [p.rpm, p.tpm, p.rpd].map((v) => TextEditingController(text: '$v')).toList();
    Widget field(int j, String label, String helper) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextField(
            controller: ctrls[j],
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: label, helperText: helper),
          ),
        );
    final ok = await showBlurDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(p.id),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          field(0, 'Request / phút (RPM)', 'Số trong AI Studio → Rate limit'),
          field(1, 'Token / phút (TPM)', 'Token đầu vào mỗi phút'),
          field(2, 'Request / ngày (RPD)', '0 = tắt model này'),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Xong')),
        ],
      ),
    );
    final v = ctrls.map((c) => int.tryParse(c.text.trim())).toList();
    if (ok != true || v.any((n) => n == null || n < 0)) return;
    setState(() => _picked[i] = (id: p.id, rpm: v[0]!, tpm: v[1]!, rpd: v[2]!));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final rest = _catalog.where((c) => !_picked.any((p) => p.id == c.id)).toList();

    String limits(int rpm, int tpm, int rpd) => rpd == 0
        ? 'tắt'
        : '$rpm RPM · ${tpm >= 1000 ? '${tpm ~/ 1000}K' : tpm} TPM · ${fmtThousands(rpd)}/ngày';

    Widget label(String s) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
          child: Text(s, style: t.labelSmall?.copyWith(letterSpacing: 1.5, color: cs.primary)),
        );

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.title, style: t.titleLarge),
          const SizedBox(height: 4),
          Text(
            switch (widget.kind) {
              ModelListKind.gemini => 'Kéo để xếp ưu tiên. Hết lượt con trên thì dùng con dưới, '
                  'hết sạch mới rơi về NVIDIA. Bấm dòng trần để sửa số.',
              ModelListKind.geminiMeta =>
                'Kéo để xếp ưu tiên. Trần lượt lấy theo chuỗi Gemini chính.',
              ModelListKind.nvidia => 'Kéo để xếp ưu tiên. NVIDIA free: 40 request/phút mỗi key, '
                  'không trần ngày — model hỏng thì thử con kế ngay.',
            },
            style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ]),
      ),
      Expanded(
        child: ReorderableListView.builder(
          buildDefaultDragHandles: false,
          padding: const EdgeInsets.only(bottom: 12),
          header: label('ĐANG DÙNG · ${_picked.length}'),
          itemCount: _picked.length,
          onReorderItem: (a, b) => setState(() => _picked.insert(b, _picked.removeAt(a))),
          itemBuilder: (context, i) {
            final p = _picked[i];
            final note = _noteOf(p.id) ?? 'Model tự thêm — không có trong danh mục';
            return Padding(
              key: ValueKey(p.id),
              padding: const EdgeInsets.fromLTRB(12, 3, 12, 3),
              child: Container(
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
                ),
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                child: Row(children: [
                  ReorderableDragStartListener(
                    index: i,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(Icons.drag_indicator_rounded, color: cs.onSurfaceVariant),
                    ),
                  ),
                  Text('${i + 1}', style: t.titleSmall?.copyWith(color: cs.primary)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(p.id, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: monoStyle(context, size: 12, color: cs.onSurface)),
                      const SizedBox(height: 2),
                      Text(note, style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                      if (_withLimits)
                        InkWell(
                          onTap: () => _editLimits(i),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              // Flexible: chữ to / màn hẹp thì xuống dòng thay vì tràn
                              Flexible(
                                child: Text(limits(p.rpm, p.tpm, p.rpd),
                                    style: t.labelMedium?.copyWith(color: cs.primary)),
                              ),
                              const SizedBox(width: 4),
                              Icon(Icons.edit_rounded, size: 13, color: cs.primary),
                            ]),
                          ),
                        ),
                    ]),
                  ),
                  IconButton(
                    tooltip: 'Bỏ khỏi chuỗi',
                    icon: Icon(Icons.remove_circle_outline_rounded, color: cs.error),
                    onPressed: () => setState(() => _picked.removeAt(i)),
                  ),
                ]),
              ),
            );
          },
          footer: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            label('THÊM MODEL'),
            for (final c in rest)
              ListTile(
                contentPadding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
                title: Text(c.id, style: monoStyle(context, size: 12, color: cs.onSurface)),
                subtitle: Text(
                  [c.note, if (c.g != null && _withLimits) limits(c.g!.rpm, c.g!.tpm, c.g!.rpd)]
                      .join(' · '),
                  style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                trailing: Icon(Icons.add_circle_outline_rounded, color: cs.primary),
                onTap: () => _add(c.id),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: TextButton.icon(
                onPressed: _addCustom,
                icon: const Icon(Icons.edit_note_rounded),
                label: const Text('Model khác (nhập ID)'),
              ),
            ),
          ]),
        ),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(children: [
            Expanded(
              child: OutlinedButton(
                  onPressed: () => Navigator.pop(context), child: const Text('Huỷ')),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                // chuỗi rỗng = worker mất hẳn provider đó → không cho lưu
                onPressed: _picked.isEmpty ? null : () => Navigator.pop(context, _encode()),
                child: const Text('Lưu'),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }
}
