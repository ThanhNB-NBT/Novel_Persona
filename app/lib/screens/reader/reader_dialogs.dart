import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data.dart';
import '../../tts.dart';
import 'reader_text.dart';

// Các sheet/dialog của màn đọc — tách khỏi reader.dart cho gọn.

/// Viết lại NGUYÊN đoạn đang chạm. Không string-replace: server ghép đoạn mới vào đúng
/// chỗ đoạn cũ, và từ chối nếu đoạn cũ đã đổi (người khác vừa sửa) — xem migration 093.
/// Trả true khi đã lưu thành công (caller lo đóng form + refetch + snackbar).
Future<bool> editWholeParaDialog(BuildContext context,
    {required int novelId, required int chapterIndex, required String block}) async {
  if (sb.auth.currentUser == null) {
    context.push('/login');
    return false;
  }
  final ctrl = TextEditingController(text: block);
  final messenger = ScaffoldMessenger.of(context);
  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Sửa cả đoạn'),
      content: SizedBox(
        width: double.maxFinite,
        child: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: null,
          minLines: 5,
          decoration: const InputDecoration(
            helperText: 'Viết lại nguyên đoạn; chỉ đoạn này đổi.',
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Lưu')),
      ],
    ),
  );
  final text = ctrl.text.trim();
  ctrl.dispose();
  if (saved != true || text.isEmpty || text == block) return false;
  try {
    await editChapterPara(novelId, chapterIndex, block, text);
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Chưa lưu được: $e')));
    return false;
  }
  return true;
}

/// Dialog báo lỗi bản dịch (không sửa nội dung chương) — kèm đoạn chọn và ngữ cảnh.
Future<void> translationReportDialog(BuildContext context,
    {required int novelId,
    required int chapterIndex,
    required Sel sel,
    required String selected}) async {
  if (sb.auth.currentUser == null) {
    context.push('/login');
    return;
  }
  final note = TextEditingController();
  var type = 'Sai nghĩa';
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Báo lỗi bản dịch'),
        // scroll: bàn phím bật lên trên màn nhỏ thì cuộn thay vì tràn/cắt ô nhập
        content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Đoạn chọn: “${selected.trim()}”', maxLines: 2,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: type,
            decoration: const InputDecoration(labelText: 'Loại lỗi'),
            items: const [
              DropdownMenuItem(value: 'Sai nghĩa', child: Text('Sai nghĩa')),
              DropdownMenuItem(value: 'Xưng hô/giọng', child: Text('Xưng hô hoặc giọng văn')),
              DropdownMenuItem(value: 'Chính tả', child: Text('Chính tả')),
              DropdownMenuItem(value: 'Cảm thán/chữ đệm', child: Text('Cảm thán hoặc chữ đệm')),
              DropdownMenuItem(value: 'Khác', child: Text('Khác')),
            ],
            onChanged: (value) => setState(() => type = value ?? type),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: note,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Ghi chú (không bắt buộc)',
              hintText: 'Không sửa nội dung chương',
            ),
          ),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Hủy')),
          FilledButton(
            onPressed: () async {
              final contextText = sel.block.replaceAll(RegExp(r'\s+'), ' ').trim();
              final excerpt = contextText.length <= 400
                  ? contextText : '${contextText.substring(0, 400)}…';
              await reportChapter(novelId, chapterIndex,
                  '[$type] Chọn: “${selected.trim()}”. Ngữ cảnh: “$excerpt”. ${note.text.trim()}');
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Đã gửi báo lỗi; chương không bị sửa')));
              }
            },
            child: const Text('Gửi báo lỗi'),
          ),
        ],
      ),
    ),
  );
  note.dispose();
}

/// Sheet chọn giọng đọc TTS — nghe thử từng giọng trước khi chọn.
Future<void> showTtsVoiceSheet(
    BuildContext context, TtsState state, Color fg, Color bg) async {
  final messenger = ScaffoldMessenger.of(context);
  if (state.playing) await TtsPlayer.i.pause();
  if (!context.mounted) return;

  var selected = TtsPlayer.i.selectedVoiceKey;
  final voices = TtsPlayer.i.availableVoices();
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: bg,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (_, setLocal) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * 0.68,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Giọng đọc tiếng Việt',
                style: TextStyle(color: fg, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Chạm để chọn · nút phát để nghe thử',
                style: TextStyle(color: fg.withValues(alpha: 0.6), fontSize: 13)),
            const SizedBox(height: 12),
            Expanded(
              child: FutureBuilder<List<TtsVoice>>(
                future: voices,
                builder: (_, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return Center(
                        child: CircularProgressIndicator(color: fg.withValues(alpha: 0.7)));
                  }
                  final items = snapshot.data ?? const [];
                  selected ??= TtsPlayer.i.selectedVoiceKey;
                  if (items.isEmpty) {
                    return Center(
                      child: Text(
                        'Chưa tìm thấy giọng Tiếng Việt.\n'
                        'Hãy tải voice Tiếng Việt trong cài đặt TTS/Trợ năng của máy.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: fg.withValues(alpha: 0.7), height: 1.5),
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: fg.withValues(alpha: 0.1)),
                    itemBuilder: (_, index) {
                      final voice = items[index];
                      final active = selected == voice.key;

                      Future<void> choose({required bool preview}) async {
                        try {
                          if (preview) {
                            await TtsPlayer.i.previewVoice(voice);
                          } else {
                            await TtsPlayer.i.selectVoice(voice);
                          }
                          if (sheetContext.mounted) setLocal(() => selected = voice.key);
                        } catch (e) {
                          messenger.showSnackBar(
                              SnackBar(content: Text('Không dùng được giọng này: $e')));
                        }
                      }

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                        selected: active,
                        selectedTileColor: fg.withValues(alpha: 0.06),
                        leading: Icon(
                            active ? Icons.radio_button_checked : Icons.radio_button_off,
                            color: active ? fg : fg.withValues(alpha: 0.45)),
                        title: Text(voice.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          '${voice.qualityLabel}${voice.networkRequired ? ' · cần mạng' : ' · offline'}',
                          style: TextStyle(color: fg.withValues(alpha: 0.58)),
                        ),
                        trailing: IconButton(
                          tooltip: 'Nghe thử ${voice.name}',
                          icon: Icon(Icons.play_circle_outline_rounded,
                              color: fg.withValues(alpha: 0.7)),
                          onPressed: () => choose(preview: true),
                        ),
                        onTap: () => choose(preview: false),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Giọng Nâng cao/Premium chỉ xuất hiện sau khi được tải về máy.',
              style: TextStyle(color: fg.withValues(alpha: 0.5), fontSize: 12),
            ),
          ]),
        ),
      ),
    ),
  );
}
