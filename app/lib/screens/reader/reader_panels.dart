import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../cultivation.dart';
import '../../data.dart';
import '../../tts.dart';
import '../../widgets.dart';
import '../cultivation/pixel.dart';
import 'reader_dialogs.dart';

/// Panel cuối chương: trạng thái 20 chương kế tiếp + Dịch thêm (ước lượng thời gian)
/// + toggle tự dịch trước 15 chương + Báo cáo chương lỗi.
class EndPanel extends ConsumerStatefulWidget {
  final int novelId;
  final int chapterIndex;
  final Color fg;
  const EndPanel({super.key, required this.novelId, required this.chapterIndex, required this.fg});
  @override
  ConsumerState<EndPanel> createState() => _EndPanelState();
}

class _EndPanelState extends ConsumerState<EndPanel> {
  bool _auto = prefs.getBool('auto_translate_ahead') ?? true;
  Timer? _tocPoll; // poll mục lục lười đang tải (reader đã gọi request_toc lúc mở)
  int _pollsLeft = 60; // ponytail: cap ~5 phút; ToC treo thì thôi kéo lại cả mục
  // lục mỗi 5s (reader mở lâu → rò egress), rời chương/vào lại tự retry.

  @override
  void dispose() {
    _tocPoll?.cancel();
    super.dispose();
  }

  String _eta(int chapters) {
    final sec = chapters * 40;
    return sec < 90 ? '~$sec giây' : '~${(sec / 60).round()} phút';
  }

  Future<void> _report() async {
    if (sb.auth.currentUser == null) {
      context.push('/login');
      return;
    }
    final reason = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showBlurDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Báo cáo chương lỗi'),
        content: TextField(
          controller: reason,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
              labelText: 'Lỗi gì? (dịch sai, thiếu đoạn, trùng chương…)', isDense: true),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Gửi')),
        ],
      ),
    );
    if (ok != true || reason.text.trim().isEmpty) return;
    await reportChapter(widget.novelId, widget.chapterIndex, reason.text.trim());
    messenger.showSnackBar(
        const SnackBar(content: Text('Đã gửi báo cáo'), duration: Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    final fg = widget.fg;
    final list = ref.watch(chapterListProvider(widget.novelId)).value ?? const <Rec>[];
    final novel = ref.watch(novelProvider(widget.novelId)).value;
    final total = (novel?['chapter_count_source'] ?? 0) as int;
    final tocLoading = list.isNotEmpty && list.length < total;
    if (tocLoading) {
      _tocPoll ??= Timer.periodic(const Duration(seconds: 5), (timer) {
        if (_pollsLeft-- <= 0) {
          timer.cancel();
          _tocPoll = null;
          return;
        }
        ref.invalidate(chapterListProvider(widget.novelId));
      });
    } else {
      _tocPoll?.cancel();
      _tocPoll = null;
    }
    final next = [
      for (final c in list)
        if ((c['chapter_index'] as int) > widget.chapterIndex &&
            (c['chapter_index'] as int) <= widget.chapterIndex + 20)
          c
    ];
    final ready = next.where((c) => c['translation_status'] == 'done').length;
    final busy = next
        .where((c) =>
            c['translation_status'] == 'queued' || c['translation_status'] == 'translating')
        .length;
    final missing = next.length - ready - busy;
    final soft = TextStyle(color: fg.withValues(alpha: 0.6), fontSize: 13);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        border: Border.all(color: fg.withValues(alpha: 0.15)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('20 CHƯƠNG KẾ TIẾP',
            style: TextStyle(
                color: fg.withValues(alpha: 0.45),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8)),
        const SizedBox(height: 6),
        Text(
          tocLoading && next.isEmpty
              ? 'Đang tải mục lục (${list.length}/$total chương)…'
              : next.isEmpty
                  ? 'Đã tới chương mới nhất của nguồn.'
                  : '$ready sẵn sàng · $busy đang dịch/chờ'
                  '${missing > 0 ? ' · $missing chưa dịch (${_eta(missing)})' : ''}',
          style: TextStyle(color: fg.withValues(alpha: 0.85), fontSize: 14),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: fg.withValues(alpha: 0.85),
                side: BorderSide(color: fg.withValues(alpha: 0.3)),
              ),
              onPressed: () => translateRangeDialog(context, ref, widget.novelId,
                  translated: (novel?['chapter_count_translated'] ?? 0) as int,
                  source: (novel?['chapter_count_source'] ?? 0) as int,
                  onDone: () => ref.invalidate(chapterListProvider(widget.novelId))),
              icon: const Icon(Icons.playlist_add_rounded, size: 18),
              label: const Text('Dịch thêm chương'),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Báo cáo chương lỗi',
            onPressed: _report,
            icon: Icon(Icons.flag_outlined, size: 20, color: fg.withValues(alpha: 0.6)),
          ),
        ]),
        Row(children: [
          Expanded(child: Text('Tự dịch trước 15 chương khi đọc', style: soft)),
          Switch(
            value: _auto,
            onChanged: (v) {
              prefs.setBool('auto_translate_ahead', v);
              setState(() => _auto = v);
            },
          ),
        ]),
      ]),
    );
  }
}

/// Thanh điều khiển nghe truyện: play/pause + chương đang đọc + giọng + tốc độ + tắt.
class TtsBar extends StatelessWidget {
  final TtsState state;
  final Color fg, bg;
  const TtsBar({super.key, required this.state, required this.fg, required this.bg});

  static const _rates = [
    (0.4, '0.8×'), (0.5, '1×'), (0.65, '1.3×'), (0.8, '1.6×'),
    (0.9, '1.8×'), (1.0, '2×'),
  ];

  @override
  Widget build(BuildContext context) {
    final soft = fg.withValues(alpha: 0.6);
    return Container(
      padding: EdgeInsets.fromLTRB(12, 4, 8, 4 + MediaQuery.paddingOf(context).bottom),
      decoration: BoxDecoration(
        color: bg,
        border: Border(top: BorderSide(color: fg.withValues(alpha: 0.12))),
      ),
      child: Row(children: [
        IconButton(
          tooltip: state.playing ? 'Dừng tạm' : 'Đọc tiếp',
          icon: Icon(
              state.playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
              size: 32,
              color: fg.withValues(alpha: 0.8)),
          onPressed: () => state.playing ? TtsPlayer.i.pause() : TtsPlayer.i.resume(),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            'Đang nghe · chương ${state.chapterIndex}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: soft, fontSize: 13),
          ),
        ),
        IconButton(
          tooltip: 'Chọn giọng đọc',
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.record_voice_over_rounded, size: 20, color: soft),
          onPressed: () => showTtsVoiceSheet(context, state, fg, bg),
        ),
        StatefulBuilder(
          builder: (_, setLocal) {
            final idx = _rates
                .indexWhere((r) => (r.$1 - TtsPlayer.i.rate).abs() < 0.01)
                .clamp(0, _rates.length - 1);
            return TextButton(
              onPressed: () async {
                await TtsPlayer.i.setRate(_rates[(idx + 1) % _rates.length].$1);
                setLocal(() {});
              },
              child: Text(_rates[idx].$2,
                  style: TextStyle(color: soft, fontWeight: FontWeight.w700)),
            );
          },
        ),
        IconButton(
          tooltip: 'Tắt nghe',
          icon: Icon(Icons.close_rounded, size: 20, color: soft),
          onPressed: () => TtsPlayer.i.stop(),
        ),
      ]),
    );
  }
}

/// Bình luận cuối chương.
class CommentsPanel extends ConsumerStatefulWidget {
  final int novelId;
  final int chapterIndex;
  final Color fg;
  const CommentsPanel({super.key, required this.novelId, required this.chapterIndex, required this.fg});
  @override
  ConsumerState<CommentsPanel> createState() => _CommentsPanelState();
}

class _CommentsPanelState extends ConsumerState<CommentsPanel> {
  final _input = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await addChapterComment(widget.novelId, widget.chapterIndex, text);
      _input.clear();
      ref.invalidate(
          chapterCommentsProvider(ChapterKey(widget.novelId, widget.chapterIndex)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fg = widget.fg;
    final key = ChapterKey(widget.novelId, widget.chapterIndex);
    final comments = ref.watch(chapterCommentsProvider(key)).value ?? const <Rec>[];
    final uid = sb.auth.currentUser?.id;
    final admin = ref.watch(isAdminProvider).value == true;
    final soft = TextStyle(color: fg.withValues(alpha: 0.45), fontSize: 11);
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        border: Border.all(color: fg.withValues(alpha: 0.15)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          comments.isEmpty ? 'BÌNH LUẬN' : 'BÌNH LUẬN (${comments.length})',
          style: TextStyle(
              color: fg.withValues(alpha: 0.45),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8),
        ),
        if (comments.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Chưa ai bình luận chương này.',
                style: TextStyle(color: fg.withValues(alpha: 0.55), fontSize: 13)),
          ),
        for (final c in comments)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(
                    '${c['display_name'] ?? 'Ẩn danh'} · ${timeAgo(c['created_at'])}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: soft.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (c['user_id'] == uid || admin)
                  GestureDetector(
                    onTap: () async {
                      await deleteChapterComment(c['id'] as int);
                      ref.invalidate(chapterCommentsProvider(key));
                    },
                    child: Icon(Icons.close_rounded,
                        size: 14, color: fg.withValues(alpha: 0.4)),
                  ),
              ]),
              const SizedBox(height: 3),
              Text(c['content'] ?? '',
                  style: TextStyle(color: fg.withValues(alpha: 0.85), fontSize: 14, height: 1.45)),
            ]),
          ),
        const SizedBox(height: 12),
        if (uid == null)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: fg.withValues(alpha: 0.85),
                side: BorderSide(color: fg.withValues(alpha: 0.3)),
              ),
              onPressed: () => context.push('/login'),
              child: const Text('Đăng nhập để bình luận'),
            ),
          )
        else
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: TextField(
                controller: _input,
                maxLines: 3,
                minLines: 1,
                maxLength: 2000,
                scrollPadding: EdgeInsets.only(
                    bottom: MediaQuery.viewInsetsOf(context).bottom + 90),
                style: TextStyle(color: fg.withValues(alpha: 0.9), fontSize: 14),
                cursorColor: fg.withValues(alpha: 0.7),
                decoration: InputDecoration(
                  counterText: '',
                  isDense: true,
                  hintText: 'Cảm nghĩ về chương này…',
                  hintStyle: TextStyle(color: fg.withValues(alpha: 0.4), fontSize: 14),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: fg.withValues(alpha: 0.25)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: fg.withValues(alpha: 0.55)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Gửi',
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: fg.withValues(alpha: 0.6)))
                  : Icon(Icons.send_rounded, size: 20, color: fg.withValues(alpha: 0.7)),
            ),
          ]),
      ]),
    );
  }
}

/// Nút cơ duyên tu tiên trong chương.
class GiftButton extends ConsumerStatefulWidget {
  final int novelId;
  final int chapterIndex;
  final Color fg;
  const GiftButton({super.key, required this.novelId, required this.chapterIndex, required this.fg});
  @override
  ConsumerState<GiftButton> createState() => _GiftButtonState();
}

class _GiftButtonState extends ConsumerState<GiftButton> {
  bool _claiming = false;

  Future<void> _claim() async {
    if (_claiming) return;
    setState(() => _claiming = true);
    try {
      final it = await cultClaimGift(widget.novelId, widget.chapterIndex);
      if (!mounted) return;
      ref.invalidate(cultClaimedProvider(widget.novelId));
      ref.invalidate(cultInventoryProvider);
      ref.invalidate(cultCollectionProvider);
      final halo = it['halo'] as String?;
      if (halo != null) ref.invalidate(cultStateProvider);
      final grade = it['grade'] as int;
      final flavor = giftFlavors[giftHash(sb.auth.currentUser!.id,
              widget.novelId, widget.chapterIndex) %
          giftFlavors.length];
      showBlurDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cơ duyên!'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(flavor,
                textAlign: TextAlign.center,
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            PixelIcon(it['pixel'] as String, grade: grade, size: 72),
            const SizedBox(height: 10),
            Text(it['name'] as String,
                style: Theme.of(ctx)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            Text('${cultTypeNames[it['type']]} · phẩm ${gradeNames[grade - 1]}',
                style: Theme.of(ctx)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: gradeColor(grade))),
            const SizedBox(height: 6),
            Text(it['descr'] as String? ?? '',
                textAlign: TextAlign.center,
                style: Theme.of(ctx).textTheme.bodySmall),
            if (halo != null) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 10),
              Text('Thiên cơ hiển lộ — đắc Tiên trận!',
                  textAlign: TextAlign.center,
                  style: Theme.of(ctx).textTheme.labelMedium?.copyWith(
                      color: Color(tienHalos[halo]!.$2),
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Image.asset('assets/cult_halo/$halo.webp', width: 96, height: 96),
              Text(haloName(halo),
                  style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600)),
              Text('Đã đội lên nếu chưa có trận nào',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
            ],
          ]),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Thu vào kho')),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _claiming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fg = widget.fg;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Center(
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: fg.withValues(alpha: 0.85),
            side: BorderSide(color: fg.withValues(alpha: 0.3)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
          onPressed: _claim,
          icon: _claiming
              ? SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: fg.withValues(alpha: 0.6)))
              : const PixelIcon('gift', grade: 5, size: 22),
          label: const Text('Cơ duyên hé mở — nhận bảo vật'),
        ),
      ),
    );
  }
}

class WaitingView extends StatelessWidget {
  final String? status;
  final Color color;
  final VoidCallback onRequest;
  const WaitingView({super.key, required this.status, required this.color, required this.onRequest});

  @override
  Widget build(BuildContext context) {
    final (label, showButton) = switch (status) {
      'queued' => ('Chương đang trong hàng đợi dịch…', false),
      'translating' => ('Đang dịch…', false),
      'failed' => ('Dịch lỗi.', true),
      _ => ('Chương chưa được dịch.', true),
    };
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (!showButton) const CircularProgressIndicator(),
        const SizedBox(height: 12),
        Text(label, style: TextStyle(color: color)),
        if (showButton)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: FilledButton(
                onPressed: onRequest,
                child: Text(status == 'failed' ? 'Dịch lại' : 'Yêu cầu dịch')),
          ),
      ]),
    );
  }
}
