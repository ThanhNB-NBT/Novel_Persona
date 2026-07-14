import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../chapter_paras.dart';
import '../../cultivation.dart';
import '../../data.dart';
import '../../hanviet.dart';
import '../../tts.dart';
import '../../widgets.dart';
import '../cultivation/pixel.dart';
import 'reader_settings.dart';

/// Vùng chữ đang chọn để sửa: khối chứa + vị trí đầu/cuối trong khối.
typedef Sel = ({String block, int start, int end});

/// Ranh giới từ để chạm-sửa: dấu ngoặc, nháy, phẩy, hai chấm… không thuộc từ.
bool isWordChar(String s, int i) {
  final c = s.codeUnitAt(i);
  return (c >= 0x30 && c <= 0x39) || // 0-9
      (c >= 0x41 && c <= 0x5a) || // A-Z
      (c >= 0x61 && c <= 0x7a) || // a-z
      (c >= 0x00c0 && c <= 0x024f) || // Latin có dấu
      (c >= 0x1e00 && c <= 0x1eff) || // tiếng Việt có dấu
      (c >= 0x3400 && c <= 0x9fff) || // chữ Hán còn sót
      c == 0x5f; // _
}

int _wordIndex(String s, int offset) {
  var i = offset.clamp(0, s.length).toInt();
  if (i < s.length && isWordChar(s, i)) return i;
  if (i > 0 && isWordChar(s, i - 1)) return i - 1;
  while (i < s.length && !isWordChar(s, i)) { i++; }
  return i == s.length ? -1 : i;
}

int wordLeft(String s, int offset) {
  var i = _wordIndex(s, offset);
  if (i < 0) return s.length;
  while (i > 0 && isWordChar(s, i - 1)) { i--; }
  return i;
}

int wordRight(String s, int offset) {
  var i = _wordIndex(s, offset);
  if (i < 0) return s.length;
  while (i < s.length && isWordChar(s, i)) { i++; }
  return i;
}

int previousWordStart(String s, int before) {
  final clamped = before.clamp(0, s.length).toInt();
  var i = clamped - 1;
  while (i >= 0 && !isWordChar(s, i)) { i--; }
  return i < 0 ? clamped : wordLeft(s, i);
}

bool _isGapSpace(String s, int i) {
  final c = s.codeUnitAt(i);
  return c == 0x20 || c == 0x09; // chỉ space/tab là "khoảng trắng nối từ"
}

/// Mở rộng vùng chọn sang PHẢI một từ — nhưng CHỈ khi cách bởi khoảng trắng, gặp dấu
/// câu (", : ; . …) thì dừng, không nuốt dấu vào vùng sửa (sửa thường 1-2 từ sạch).
int extendRightWord(String s, int end) {
  var j = end;
  while (j < s.length && _isGapSpace(s, j)) { j++; }
  if (j >= s.length || !isWordChar(s, j)) return end; // sau khoảng trắng là dấu/hết → giữ nguyên
  while (j < s.length && isWordChar(s, j)) { j++; }
  return j;
}

/// Mở rộng sang TRÁI một từ, cùng luật: chỉ vượt khoảng trắng, không nuốt dấu câu.
int extendLeftWord(String s, int start) {
  var j = start;
  while (j > 0 && _isGapSpace(s, j - 1)) { j--; }
  if (j <= 0 || !isWordChar(s, j - 1)) return start;
  while (j > 0 && isWordChar(s, j - 1)) { j--; }
  return j;
}

int nextWordEnd(String s, int from) {
  final clamped = from.clamp(0, s.length).toInt();
  var i = clamped;
  while (i < s.length && !isWordChar(s, i)) { i++; }
  return i == s.length ? clamped : wordRight(s, i);
}

/// Bản dịch cũ có thể đã chép đuôi chương trước do model nhìn thấy context.
/// Chỉ ẩn các đoạn đầu khớp nguyên văn đuôi trước; dữ liệu DB không bị sửa khi đọc.
String withoutLeadingPreviousEcho(String current, String? previous) {
  if (previous == null || previous.trim().isEmpty) return current;
  final tail = previous.trim();
  final lines = current.split('\n');
  while (lines.isNotEmpty) {
    final lead = lines.first.trim();
    if (lead.length < 20 || !tail.contains(lead)) break;
    lines.removeAt(0);
  }
  return lines.join('\n').trimLeft();
}

class ReaderScreen extends ConsumerStatefulWidget {
  final int novelId;
  final int chapterIndex;
  const ReaderScreen({super.key, required this.novelId, required this.chapterIndex});

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  int get novelId => widget.novelId;
  int get chapterIndex => widget.chapterIndex;

  final _scroll = ScrollController();
  final _pageCtrl = PageController();
  final _percent = ValueNotifier<double>(0);
  final _correct = TextEditingController();
  final _correctFocus = FocusNode();

  // Selection dùng ValueNotifier → chỉ overlay sửa rebuild, KHÔNG rebuild cả trang (đỡ giật khi chọn).
  final _sel = ValueNotifier<Sel?>(null);
  final _editing = ValueNotifier<bool>(false);

  // TTS: đoạn nội dung máy đọc đang đọc TRÊN CHƯƠNG NÀY (-1 = không phải chương đang
  // nghe / đang đọc tiêu đề). Reader nghe cái này để highlight + cuộn theo.
  final _localTtsPara = ValueNotifier<int>(-1);
  // Danh sách đoạn + tiêu đề đang render — để nút Nghe bắt đầu từ đoạn đang đọc, khớp
  // phân đoạn với máy đọc.
  List<String> _renderedParas = const [];
  String _renderedTitle = '';

  bool _restored = false;
  int _restoreTries = 0;

  // Bộ nhớ đệm phân trang (chế độ lật trang) — tính lại khi nội dung/cỡ chữ/kích thước đổi.
  List<String>? _pages;
  int? _pageKey;

  // Vuốt quá mép để đổi chương (cuộn dọc): cộng dồn độ overscroll, quá ngưỡng thì nhảy.
  double _overNext = 0, _overPrev = 0;
  bool _navigating = false;
  static const _kOverscroll = 90.0;

  @override
  void initState() {
    super.initState();
    // Mở reader = tín hiệu đọc thật → xin mục lục đầy đủ cho truyện lười.
    // RPC tự no-op khi truyện đã có mục lục nên gọi mỗi lần mở cũng vô hại.
    requestToc(novelId);
    // Tự dịch TRƯỚC 15 chương ngay từ chương ĐANG mở (trước đây chỉ gọi lúc
    // chuyển chương → đọc chương 1 xong không có gì dịch sẵn). pushReplacement
    // tạo state mới nên initState chạy mỗi lần đổi chương — một chỗ này là đủ.
    if (sb.auth.currentUser != null && (prefs.getBool('auto_translate_ahead') ?? true)) {
      requestTranslation(novelId, chapterIndex + 15, priority: 5);
    }
    _persistChapter(); // tiến độ cấp chương (server, cho "đọc tiếp")
    _percent.value = chapterPercent(novelId, chapterIndex);
    _scroll.addListener(_onScroll);
    // Bám máy đọc: highlight đoạn đang đọc + tự chuyển màn khi TTS sang chương mới.
    TtsPlayer.i.state.addListener(_syncTts);
    TtsPlayer.i.paraAt.addListener(_syncTts);
    // Giữ màn hình sáng khi đang đọc/nghe — không phải chạm liên tục cho khỏi tắt.
    // ponytail: gắn theo vòng đời reader; chuyển chương (pushReplacement) enable lại
    // ngay ở initState mới nên khoảng hở dưới giây, thừa dưới ngưỡng tắt màn ~30s.
    WakelockPlus.enable();
  }

  /// Ghi chương đang đọc rồi làm mới các provider — novel_detail nằm dưới reader
  /// vẫn giữ progressProvider sống nên không invalidate thì "đọc tiếp" kẹt chương cũ.
  Future<void> _persistChapter() async {
    await saveProgress(novelId, chapterIndex);
    if (!mounted) return;
    ref.invalidate(progressProvider(novelId));
    ref.invalidate(readingProvider);
  }

  @override
  void dispose() {
    TtsPlayer.i.state.removeListener(_syncTts);
    TtsPlayer.i.paraAt.removeListener(_syncTts);
    _scroll.dispose();
    _pageCtrl.dispose();
    _percent.dispose();
    _correct.dispose();
    _correctFocus.dispose();
    _sel.dispose();
    _editing.dispose();
    _localTtsPara.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  /// Đồng bộ với máy đọc: (1) chương này đang được nghe → mirror đoạn đang đọc để
  /// highlight; (2) TTS đã tự sang chương khác → chuyển màn theo cho khớp (không thì
  /// tiếng đọc chương sau mà màn hình kẹt chương cũ).
  void _syncTts() {
    if (!mounted) return;
    final st = TtsPlayer.i.state.value;
    final here = st.active && st.novelId == novelId && st.chapterIndex == chapterIndex;
    _localTtsPara.value = (here && !st.paused) ? TtsPlayer.i.paraAt.value : -1;
    if (st.active &&
        st.playing &&
        st.novelId == novelId &&
        st.chapterIndex != chapterIndex &&
        !_navigating) {
      _goChapter(st.chapterIndex);
    }
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    if (max <= 0) return;
    final pct = (_scroll.offset / max).clamp(0.0, 1.0);
    _percent.value = pct;
    saveChapterPercent(novelId, chapterIndex, pct); // prefs — rẻ, lưu liên tục ok
  }

  /// Khôi phục vị trí cuộn đã lưu (chờ nội dung layout xong mới có maxScrollExtent).
  void _restoreScroll() {
    if (_restored) return;
    final saved = chapterPercent(novelId, chapterIndex);
    if (saved <= 0.01) {
      _restored = true;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      if (max <= 0) {
        if (_restoreTries++ < 12) _restoreScroll();
        return;
      }
      _scroll.jumpTo(saved * max);
      _restored = true;
    });
  }

  void _goChapter(int index) {
    if (index < 1 || _navigating) return;
    _navigating = true; // chặn nhảy 2 lần; pushReplacement tạo state mới nên cờ tự reset
    // tự dịch trước 15 chương: initState của màn mới lo (một chỗ duy nhất)
    context.pushReplacement('/novel/$novelId/read/$index');
  }

  /// Chạm vào 1 từ trong đoạn → chọn từ đó + mở form sửa ngay (không cần giữ/chọn tay).
  void _onTapWord(String block, int offset, Offset globalPos) {
    if (sb.auth.currentUser == null) {
      context.push('/login');
      return;
    }
    final off = offset.clamp(0, block.length);
    final a = wordLeft(block, off);
    final b = wordRight(block, off);
    if (b <= a) return; // chạm chỗ trống
    _sel.value = (block: block, start: a, end: b);
    if (!_editing.value) {
      _correct.clear();
      _editing.value = true;
    }
    _correctFocus.requestFocus();
    _revealTappedWord(globalPos);
  }

  /// Bàn phím + form che nửa dưới màn — nếu từ vừa chạm nằm dưới đó thì cuộn lên
  /// để vẫn thấy từ đang sửa (tô đỏ) trong trang. Chờ bàn phím trồi lên xong mới đo.
  void _revealTappedWord(Offset globalPos) {
    Future.delayed(const Duration(milliseconds: 350), () {
      if (!mounted || !_scroll.hasClients || !_editing.value) return;
      final mq = MediaQuery.of(context);
      final visibleBottom = mq.size.height - mq.viewInsets.bottom - 230; // ~230 = form sửa
      if (globalPos.dy > visibleBottom) {
        final target = (_scroll.offset + (globalPos.dy - mq.size.height * 0.28))
            .clamp(0.0, _scroll.position.maxScrollExtent);
        _scroll.animateTo(target,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  void _closeEdit() {
    _correct.clear();
    _editing.value = false;
    _sel.value = null;
  }

  Future<void> _submitEdit(String wrong) async {
    if (sb.auth.currentUser == null) {
      context.push('/login');
      return;
    }
    final v = _correct.text.trim();
    final w = wrong.trim();
    if (v.isEmpty || w.isEmpty || v == w) return; // trống/không đổi → bỏ
    await editChapterText(novelId, chapterIndex, w, v); // sửa THẲNG chương này (không LLM, không queue)
    await submitCorrection(novelId, w, v); // lưu glossary cho chương/truyện dịch SAU
    _closeEdit();
    // refetch chương → bản sửa hiện NGAY
    ref.invalidate(chapterProvider(ChapterKey(novelId, chapterIndex)));
    if (mounted) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(SnackBar(
        content: const Text('Đã sửa'),
        duration: const Duration(milliseconds: 2500), // gọn — mặc định 4s hơi lâu
        action: SnackBarAction(
          label: 'Áp cả truyện',
          // string-replace mọi chương done (miễn phí, chạy nền) — chỉ khi bạn chủ động bấm.
          // SnackBarAction tự ẩn snackbar; hiện xác nhận ngắn thay thế.
          onPressed: () {
            requestPatch(novelId);
            messenger.showSnackBar(const SnackBar(
                content: Text('Đang vá cả truyện ở chế độ nền…'),
                duration: Duration(seconds: 2)));
          },
        ),
      ));
    }
  }

  Future<void> _showTranslationReport(Sel sel, String selected) async {
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
          content: Column(mainAxisSize: MainAxisSize.min, children: [
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
          ]),
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
                if (mounted) {
                  ScaffoldMessenger.of(this.context).showSnackBar(
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

  @override
  Widget build(BuildContext context) {
    final chapter = ref.watch(chapterProvider(ChapterKey(novelId, chapterIndex)));
    final previous = chapterIndex > 1
        ? ref.watch(chapterProvider(ChapterKey(novelId, chapterIndex - 1))).value
        : null;
    ref.watch(glossaryProvider(novelId)); // nạp sẵn glossary để gợi ý khi sửa từ
    final s = ref.watch(readerSettingsProvider);
    // "Hệ thống" của reader = theo chế độ sáng/tối của app (chứ không phải OS thô),
    // để đặt tối trong Cài đặt app là màn đọc cũng tối theo.
    final col = s.resolve(appBrightness(ref, context));

    return Scaffold(
      backgroundColor: col.bg,
      resizeToAvoidBottomInset: false, // form sửa tự nâng theo viewInsets; giữ phân trang ổn định
      // header tối giản: thấp, chữ/icon mờ — nhường trọn sự chú ý cho trang chữ
      appBar: AppBar(
        toolbarHeight: 38,
        backgroundColor: col.bg,
        foregroundColor: col.fg.withValues(alpha: 0.55),
        iconTheme: IconThemeData(color: col.fg.withValues(alpha: 0.55), size: 20),
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 0,
        title: Text('Chương $chapterIndex',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: col.fg.withValues(alpha: 0.55))),
        actions: [
          ValueListenableBuilder<double>(
            valueListenable: _percent,
            builder: (_, p, _) => Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text('${(p * 100).round()}%',
                    style: TextStyle(fontSize: 11, color: col.fg.withValues(alpha: 0.45))),
              ),
            ),
          ),
          // Nghe truyện: TTS hệ thống đọc từ chương đang mở; điều khiển ở thanh đáy
          ValueListenableBuilder<TtsState>(
            valueListenable: TtsPlayer.i.state,
            builder: (_, ts, _) => IconButton(
              tooltip: ts.active ? 'Dừng nghe' : 'Nghe chương này',
              icon: Icon(
                  ts.active ? Icons.headset_off_rounded : Icons.headset_rounded,
                  size: 19),
              onPressed: () async {
                if (ts.active) {
                  await TtsPlayer.i.stop();
                  return;
                }
                final messenger = ScaffoldMessenger.of(context);
                // bắt đầu từ ĐOẠN đang đọc (ước lượng theo % cuộn), không đọc lại từ đầu;
                // truyền paras/title để máy đọc phân đoạn KHỚP với màn hình → highlight đúng
                final n = _renderedParas.length;
                final from =
                    n == 0 ? 0 : (_percent.value * n).floor().clamp(0, n - 1);
                // máy thiếu giọng tiếng Việt → nói thẳng lý do thay vì câm lặng
                final warn = await TtsPlayer.i.start(novelId, chapterIndex,
                    fromContentPara: from,
                    paras: _renderedParas,
                    title: _renderedTitle);
                if (warn != null) {
                  messenger.showSnackBar(SnackBar(
                      content: Text(warn), duration: const Duration(seconds: 6)));
                }
              },
            ),
          ),
          IconButton(
            tooltip: 'Cài đặt đọc',
            icon: const Icon(Icons.settings_rounded, size: 19),
            onPressed: () => showReaderSettingsSheet(context, ref, onRetranslate: _retranslate),
          ),
          const SizedBox(width: 2),
        ],
      ),
      // Thanh điều khiển nghe — chỉ hiện khi máy đọc đang chạy cho truyện này
      bottomNavigationBar: ValueListenableBuilder<TtsState>(
        valueListenable: TtsPlayer.i.state,
        builder: (_, ts, _) => ts.novelId == novelId
            ? _TtsBar(state: ts, fg: col.fg, bg: col.bg)
            : const SizedBox.shrink(),
      ),
      body: chapter.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AppError(e,
            onRetry: () =>
                ref.invalidate(chapterProvider(ChapterKey(novelId, chapterIndex)))),
        data: (c) {
          if (c == null) return Center(child: Text('Không có chương này', style: TextStyle(color: col.fg)));
          final status = c['translation_status'];
          if (status != 'done') {
            return _WaitingView(
              status: status,
              color: col.fg,
              onRequest: () async {
                if (sb.auth.currentUser == null) {
                  context.push('/login');
                  return;
                }
                await requestTranslation(novelId, chapterIndex + 10, priority: 5);
                ref.invalidate(chapterProvider(ChapterKey(novelId, chapterIndex)));
              },
            );
          }
          final rawTitle = (c['title_vi'] as String?)
              ?.replaceFirst(RegExp(r'^#+\s*'), '') // bỏ '# ' markdown model đôi khi chèn
              .trim();
          final title = (rawTitle == null || rawTitle.isEmpty)
              ? 'Chương $chapterIndex'
              : rawTitle;
          final content = withoutLeadingPreviousEcho(
              (c['content_vi'] as String?) ?? '', previous?['content_vi'] as String?);
          final paras = contentParagraphs(content);
          _renderedParas = paras; // để nút Nghe bắt đầu từ ĐOẠN đang đọc, không từ đầu chương
          _renderedTitle = title;
          if (paras.isEmpty) {
            // done nhưng nội dung rỗng (bản dịch cũ lỗi) → cho dịch lại thay vì hiện trắng
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.menu_book_outlined, size: 48, color: col.fg.withValues(alpha: 0.4)),
                  const SizedBox(height: 12),
                  Text('Chương này chưa có nội dung dịch.',
                      textAlign: TextAlign.center, style: TextStyle(color: col.fg)),
                  const SizedBox(height: 4),
                  Text('Bản dịch cũ có thể bị lỗi — thử dịch lại.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: col.fg.withValues(alpha: 0.6), fontSize: 13)),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _retranslate,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Dịch lại chương'),
                  ),
                ]),
              ),
            );
          }
          final textStyle = readerFontStyle(s.fontKey,
              fontSize: s.fontSize, height: s.lineHeight, color: col.fg);

          // fit: expand để Stack luôn lấp đầy màn — nếu không, đứa con non-positioned
          // duy nhất là _overlay (SizedBox.shrink) làm Stack co về 0 → nội dung "tàng hình".
          return Stack(
            fit: StackFit.expand,
            children: [
              s.pageMode
                  ? _buildPager(context, s, col, title, paras, textStyle)
                  : _buildScroll(context, s, col, title, paras, textStyle),
              _overlay(context),
            ],
          );
        },
      ),
    );
  }

  /// Chương này còn quà tu tiên chưa nhận không (công thức md5 + bảng claims).
  bool _hasGift() {
    final uid = sb.auth.currentUser?.id;
    if (uid == null || !giftAt(uid, novelId, chapterIndex)) return false;
    final claimed = ref.watch(cultClaimedProvider(novelId)).value ?? const <int>{};
    return !claimed.contains(chapterIndex);
  }

  // -------- Chế độ cuộn dọc (SelectableText → chọn chữ để sửa) --------
  Widget _buildScroll(BuildContext context, ReaderSettings s, ReaderColor col,
      String title, List<String> paras, TextStyle textStyle) {
    _restoreScroll();
    // quà chèn CUỐI đoạn thứ hash%n — tất định, mỗi user mỗi chỗ khác nhau
    final giftAfter = _hasGift()
        ? giftHash(sb.auth.currentUser!.id, novelId, chapterIndex) % paras.length
        : -1;
    final titleStyle = readerFontStyle(s.fontKey,
            fontSize: s.fontSize + 4, height: 1.3, color: col.fg)
        .copyWith(fontWeight: FontWeight.w700);
    final hint = TextStyle(color: col.fg.withValues(alpha: 0.5), fontSize: 13);
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        // Cuộn hết rồi vuốt tiếp (overscroll) → nhảy chương; kéo quá đỉnh → chương trước.
        if (n is ScrollStartNotification) {
          _overNext = 0;
          _overPrev = 0;
        } else if (n is OverscrollNotification) {
          if (n.overscroll > 0) {
            _overNext += n.overscroll;
          } else {
            _overPrev += -n.overscroll;
          }
        } else if (n is ScrollEndNotification) {
          if (_overNext > _kOverscroll) {
            _goChapter(chapterIndex + 1);
          } else if (_overPrev > _kOverscroll) {
            _goChapter(chapterIndex - 1);
          }
          _overNext = 0;
          _overPrev = 0;
        }
        return false;
      },
      child: ListView(
        controller: _scroll,
        padding: EdgeInsets.fromLTRB(s.sideMargin, 10, s.sideMargin, 40),
        children: [
          Text(title, style: titleStyle),
          const SizedBox(height: 18),
          for (var i = 0; i < paras.length; i++) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _TapPara(
                para: paras[i],
                style: textStyle,
                align: s.justify ? TextAlign.justify : TextAlign.left,
                sel: _sel,
                onTapWord: _onTapWord,
                ttsPara: _localTtsPara,
                paraIndex: i,
                ttsHlColor: col.fg.withValues(alpha: 0.10),
              ),
            ),
            if (i == giftAfter)
              _GiftButton(novelId: novelId, chapterIndex: chapterIndex, fg: col.fg),
          ],
          const SizedBox(height: 12),
          Divider(color: col.fg.withValues(alpha: 0.15)),
          const SizedBox(height: 8),
          Center(
            child: Text('Hết chương $chapterIndex · vuốt lên để đọc tiếp ↑', style: hint),
          ),
          const SizedBox(height: 16),
          _EndPanel(novelId: novelId, chapterIndex: chapterIndex, fg: col.fg),
          _CommentsPanel(novelId: novelId, chapterIndex: chapterIndex, fg: col.fg),
        ],
      ),
    );
  }

  // -------- Chế độ lật trang (Text thường → PageView vuốt ngang luôn ăn) --------
  Widget _buildPager(BuildContext context, ReaderSettings s, ReaderColor col,
      String title, List<String> paras, TextStyle textStyle) {
    // tính Ở ĐÂY (trong build) — itemBuilder chạy lúc layout, ref.watch trong đó sẽ nổ assert
    final hasGift = _hasGift();
    final normalized = paras.join('\n\n');
    final titleStyle = readerFontStyle(s.fontKey,
            fontSize: s.fontSize + 4, height: 1.3, color: col.fg)
        .copyWith(fontWeight: FontWeight.w700);

    return LayoutBuilder(builder: (context, cons) {
      final w = cons.maxWidth - s.sideMargin * 2;
      final h = cons.maxHeight - 20; // trừ padding trên/dưới 10+10
      final ttp = TextPainter(
          text: TextSpan(text: title, style: titleStyle),
          textDirection: TextDirection.ltr)
        ..layout(maxWidth: w);
      final firstH = (h - ttp.height - 18).clamp(60.0, h);

      // Trang đệm 2 đầu: vuốt qua trang cuối → chương sau; vuốt ngược trước trang đầu → chương trước.
      // Chương 1 không có đệm đầu. lead = số trang đệm phía trước (0 hoặc 1).
      final lead = chapterIndex > 1 ? 1 : 0;

      final key = Object.hash(normalized, s.fontKey, s.fontSize.round(),
          s.lineHeight.toStringAsFixed(1), w.round(), h.round());
      if (key != _pageKey) {
        _pages = _paginate(normalized, textStyle, w, h, firstH);
        _pageKey = key;
        final saved = chapterPercent(novelId, chapterIndex);
        final c = _pages!.length > 1 ? (saved * (_pages!.length - 1)).round() : 0;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _pageCtrl.hasClients) {
            _pageCtrl.jumpToPage((c + lead).clamp(0, _pages!.length - 1 + lead));
          }
        });
      }
      final pages = _pages!;
      // + trang panel cuối chương (dịch thêm/báo cáo) + đệm sau để vuốt sang chương
      final total = pages.length + lead + 2;

      return PageView.builder(
        controller: _pageCtrl,
        itemCount: total,
        onPageChanged: (i) {
          if (lead == 1 && i == 0) {
            _goChapter(chapterIndex - 1);
          } else if (i == total - 1) {
            _goChapter(chapterIndex + 1);
          } else if (i < total - 2) {
            final c = i - lead; // chỉ số trang nội dung (trang panel không tính %)
            final p = pages.length > 1 ? c / (pages.length - 1) : 1.0;
            _percent.value = p.clamp(0, 1);
            saveChapterPercent(novelId, chapterIndex, p);
          }
        },
        itemBuilder: (context, i) {
          if (lead == 1 && i == 0) return _pagerEdge(col, next: false);
          if (i == total - 1) return _pagerEdge(col, next: true);
          if (i == total - 2) {
            // trang cuối chương: panel dịch thêm/báo cáo/tự dịch — vuốt tiếp mới sang chương
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(s.sideMargin, 24, s.sideMargin, 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Center(
                  child: Text('Hết chương $chapterIndex',
                      style: TextStyle(color: col.fg.withValues(alpha: 0.5), fontSize: 13)),
                ),
                const SizedBox(height: 16),
                // chế độ lật trang: quà nằm ở trang panel cuối chương (không chen vào trang chữ)
                if (hasGift)
                  _GiftButton(novelId: novelId, chapterIndex: chapterIndex, fg: col.fg),
                _EndPanel(novelId: novelId, chapterIndex: chapterIndex, fg: col.fg),
                _CommentsPanel(novelId: novelId, chapterIndex: chapterIndex, fg: col.fg),
                const SizedBox(height: 16),
                Center(
                  child: Text('vuốt tiếp để sang chương sau →',
                      style: TextStyle(color: col.fg.withValues(alpha: 0.4), fontSize: 12)),
                ),
              ]),
            );
          }
          final c = i - lead;
          return Padding(
            padding: EdgeInsets.fromLTRB(s.sideMargin, 10, s.sideMargin, 10),
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(), // đã fit sẵn; chặn kéo trong trang
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (c == 0) ...[
                  Text(title, style: titleStyle),
                  const SizedBox(height: 18),
                ],
                _TapPara(
                  para: pages[c],
                  style: textStyle,
                  align: s.justify ? TextAlign.justify : TextAlign.left,
                  sel: _sel,
                  onTapWord: _onTapWord,
                ),
              ]),
            ),
          );
        },
      );
    });
  }

  /// Trang đệm ở 2 đầu chế độ lật trang — chỉ thoáng hiện lúc vuốt qua để đổi chương.
  Widget _pagerEdge(ReaderColor col, {required bool next}) {
    final c = col.fg.withValues(alpha: 0.55);
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(next ? Icons.chevron_right_rounded : Icons.chevron_left_rounded, size: 44, color: c),
        const SizedBox(height: 8),
        Text(next ? 'Chương sau' : 'Chương trước', style: TextStyle(color: c)),
      ]),
    );
  }

  /// Cắt văn bản thành các trang vừa 1 màn (tìm nhị phân số ký tự vừa chiều cao).
  List<String> _paginate(
      String text, TextStyle style, double maxWidth, double pageH, double firstH) {
    final pages = <String>[];
    final tp = TextPainter(textDirection: TextDirection.ltr, maxLines: null);
    final n = text.length;
    int start = 0;
    while (start < n) {
      final limit = pages.isEmpty ? firstH : pageH;
      int lo = start + 1, hi = n, best = start + 1;
      while (lo <= hi) {
        final mid = (lo + hi) >> 1;
        tp.text = TextSpan(text: text.substring(start, mid), style: style);
        tp.layout(maxWidth: maxWidth);
        if (tp.height <= limit) {
          best = mid;
          lo = mid + 1;
        } else {
          hi = mid - 1;
        }
      }
      int end = best;
      if (end < n) {
        // lùi về khoảng trắng gần nhất để không cắt giữa từ
        final ws = text.lastIndexOf(RegExp(r'\s'), end - 1);
        if (ws > start) end = ws + 1;
      }
      if (end <= start) end = (start + 1).clamp(0, n); // an toàn, tránh lặp vô hạn
      pages.add(text.substring(start, end).trim());
      start = end;
    }
    if (pages.isEmpty) pages.add('');
    return pages;
  }

  // -------- Overlay form sửa (mở thẳng khi chạm từ), chỉ nó rebuild theo selection --------
  Widget _overlay(BuildContext context) => AnimatedBuilder(
        animation: Listenable.merge([_sel, _editing]),
        builder: (context, _) {
          final sel = _sel.value;
          if (sel == null || !_editing.value) return const SizedBox.shrink();
          return _editForm(context, sel);
        },
      );

  /// Form nhỏ ở đáy: từ đang sửa + 2 nút mở rộng vùng chọn (trái/phải) + đóng.
  Widget _editForm(BuildContext context, Sel sel) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final block = sel.block;
    final a = sel.start.clamp(0, block.length);
    final b = sel.end.clamp(0, block.length);
    final wrong = block.substring(a, b);

    // Gợi ý bản đúng từ glossary truyện (tên/thuật ngữ đã có zh↔Hán-Việt khi dịch).
    // Khớp: từ đang chọn == correct_vi (đúng, hiện chữ Trung gốc) hoặc == wrong_vi /
    // chứa nhau (sai → gợi ý correct_vi). Đây là "từ điển" của chính truyện.
    final sel0 = wrong.trim();
    final terms = ref.read(glossaryProvider(novelId)).value ?? const [];
    final sug = <Map<String, dynamic>>[];
    for (final tm in terms) {
      final zh = (tm['term_zh'] ?? '').toString();
      if (zh.isEmpty || sel0.isEmpty) continue;
      final cv = (tm['correct_vi'] ?? '').toString();
      final wv = (tm['wrong_vi'] ?? '').toString();
      final hit = cv == sel0 ||
          wv == sel0 ||
          sel0.contains(zh) || // chọn trúng chữ Hán còn sót → term của chính nó
          (cv.isNotEmpty && (sel0.contains(cv) || cv.contains(sel0))) ||
          (wv.isNotEmpty && sel0.contains(wv));
      if (hit) sug.add(tm);
      if (sug.length >= 4) break;
    }

    // Chọn trúng chữ Hán sót trong bản dịch → tra bảng ra thẳng âm Hán-Việt để điền,
    // kể cả khi glossary chưa có term (trước đây chọn chữ Hán là form trơ, không gợi gì).
    String? hanFill;
    if (sel0.isNotEmpty) {
      final filled = sel0.replaceAllMapped(
          RegExp(r'[㐀-䶿一-鿿]+'),
          (m) => hanVietOf(m.group(0)!) ?? m.group(0)!);
      if (filled != sel0) hanFill = filled;
    }

    Widget extend(IconData icon, String tip, VoidCallback onTap) => IconButton.filledTonal(
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          onPressed: onTap,
          icon: Icon(icon, size: 20),
        );

    return Positioned(
      left: 0, right: 0, bottom: 0,
      // trượt lên + hiện dần khi form mở; TweenAnimationBuilder giữ state qua rebuild
      // nên nới vùng chọn ⟨⟩ KHÔNG chạy lại animation (đỡ giật)
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        builder: (context, v, child) => Transform.translate(
            offset: Offset(0, (1 - v) * 56),
            child: Opacity(opacity: v, child: child)),
        child: Material(
        elevation: 8,
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        child: Padding(
          // đáy: né bàn phím (viewInsets) HOẶC thanh điều hướng (viewPadding) + chừa 16
          padding: EdgeInsets.fromLTRB(16, 10, 16,
              (MediaQuery.of(context).viewInsets.bottom > 0
                      ? MediaQuery.of(context).viewInsets.bottom
                      : MediaQuery.of(context).viewPadding.bottom) +
                  16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('Sửa bản dịch', style: t.titleMedium),
              const Spacer(),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: _closeEdit,
                icon: const Icon(Icons.close_rounded),
              ),
            ]),
            // Vùng đang thay (ĐỎ) + mở rộng theo TỪ ⟨ ⟩ — luôn thấy rõ từ nào đang sửa.
            Row(children: [
              extend(Icons.chevron_left_rounded, 'Mở rộng 1 từ sang trái', () {
                final na = extendLeftWord(block, a);
                if (na != a) _sel.value = (block: block, start: na, end: b);
              }),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: cs.error.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: cs.error.withValues(alpha: 0.45)),
                  ),
                  child: Text(wrong,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: t.bodyLarge?.copyWith(color: cs.error, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 8),
              extend(Icons.chevron_right_rounded, 'Mở rộng 1 từ sang phải', () {
                final nb = extendRightWord(block, b);
                if (nb != b) _sel.value = (block: block, start: a, end: nb);
              }),
            ]),
            // gợi ý bản đúng từ glossary (chữ Trung → Hán-Việt) — bấm để điền.
            // Kèm chip "tra bảng ⇒" khi phiên âm Hán-Việt theo bảng KHÁC bản trong
            // glossary — người không biết tiếng Trung vẫn đối chiếu được chuẩn.
            if (sug.isNotEmpty || hanFill != null) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 6, children: [
                if (hanFill case final hf?)
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    side: BorderSide(color: cs.primary.withValues(alpha: 0.6)),
                    label: Text('tra bảng ⇒ $hf',
                        style: t.labelMedium?.copyWith(color: cs.primary)),
                    onPressed: () {
                      _correct.text = hf;
                      _correct.selection =
                          TextSelection.collapsed(offset: _correct.text.length);
                      _correctFocus.requestFocus();
                    },
                  ),
                for (final m in sug) ...[
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    label: Text('${m['term_zh']} → ${m['correct_vi']}', style: t.labelMedium),
                    onPressed: () {
                      _correct.text = '${m['correct_vi']}';
                      _correct.selection =
                          TextSelection.collapsed(offset: _correct.text.length);
                      _correctFocus.requestFocus();
                    },
                  ),
                  if (hanVietOf('${m['term_zh']}') case final hv?
                      when hv != '${m['correct_vi']}')
                    ActionChip(
                      visualDensity: VisualDensity.compact,
                      side: BorderSide(color: cs.primary.withValues(alpha: 0.6)),
                      label: Text('tra bảng ⇒ $hv',
                          style: t.labelMedium?.copyWith(color: cs.primary)),
                      onPressed: () {
                        _correct.text = hv;
                        _correct.selection =
                            TextSelection.collapsed(offset: _correct.text.length);
                        _correctFocus.requestFocus();
                      },
                    ),
                ],
              ]),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: _correct,
              focusNode: _correctFocus,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submitEdit(wrong),
              decoration: const InputDecoration(labelText: 'Sửa thành', isDense: true),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => _submitEdit(wrong),
                child: const Text('Lưu'),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _showTranslationReport(sel, wrong),
                icon: const Icon(Icons.flag_outlined),
                label: const Text('Báo lỗi, không sửa chương'),
              ),
            ),
          ]),
        ),
      )),
    );
  }

  Future<void> _retranslate() async {
    if (sb.auth.currentUser == null) {
      context.push('/login');
      return;
    }
    await retranslateChapter(novelId, chapterIndex);
    ref.invalidate(chapterProvider(ChapterKey(novelId, chapterIndex)));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã xếp hàng dịch lại chương')));
    }
  }
}

/// Đoạn văn chạm-để-sửa: chạm vào từ nào là chọn từ đó; từ đang sửa tô nền đỏ
/// NGAY TRONG TRANG nên gõ trong form vẫn thấy rõ đang sửa chỗ nào.
/// Chỉ đoạn chứa vùng chọn rebuild khi selection đổi (ValueListenableBuilder).
class _TapPara extends StatelessWidget {
  final String para;
  final TextStyle style;
  final TextAlign align;
  final ValueNotifier<Sel?> sel;
  final void Function(String block, int offset, Offset globalPos) onTapWord;
  // TTS: nghe chỉ số đoạn đang đọc; khi trùng paraIndex → tô nền + tự cuộn vào tầm mắt.
  final ValueNotifier<int>? ttsPara;
  final int paraIndex;
  final Color? ttsHlColor;
  const _TapPara({
    required this.para,
    required this.style,
    required this.align,
    required this.sel,
    required this.onTapWord,
    this.ttsPara,
    this.paraIndex = -1,
    this.ttsHlColor,
  });

  @override
  Widget build(BuildContext context) {
    final tp = ttsPara;
    if (tp == null) return _base(context);
    // Đoạn đang đọc → nền mờ + cuộn vào ~35% màn (bám theo giọng đọc). child dựng 1 lần.
    return ValueListenableBuilder<int>(
      valueListenable: tp,
      builder: (context, active, child) {
        final on = active == paraIndex;
        if (on) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              Scrollable.ensureVisible(context,
                  alignment: 0.35,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut);
            }
          });
        }
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: on ? (ttsHlColor ?? Colors.transparent) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: child,
        );
      },
      child: _base(context),
    );
  }

  Widget _base(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ValueListenableBuilder<Sel?>(
      valueListenable: sel,
      builder: (context, s, _) {
        final hl = (s != null && s.block == para) ? s : null;
        return LayoutBuilder(builder: (context, cons) {
          final scaler = MediaQuery.textScalerOf(context);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) {
              // đo lại layout chữ y hệt lúc render → vị trí chạm → chỉ số ký tự
              final tp = TextPainter(
                text: TextSpan(text: para, style: style),
                textAlign: align,
                textDirection: TextDirection.ltr,
                textScaler: scaler,
              )..layout(maxWidth: cons.maxWidth);
              final off = tp.getPositionForOffset(d.localPosition).offset;
              tp.dispose();
              onTapWord(para, off, d.globalPosition);
            },
            child: Text.rich(
              hl == null
                  ? TextSpan(text: para, style: style)
                  : TextSpan(style: style, children: [
                      TextSpan(text: para.substring(0, hl.start)),
                      TextSpan(
                        text: para.substring(hl.start, hl.end),
                        style: TextStyle(
                          backgroundColor: cs.error.withValues(alpha: 0.22),
                          color: cs.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      TextSpan(text: para.substring(hl.end)),
                    ]),
              textAlign: align,
            ),
          );
        });
      },
    );
  }
}

/// Panel cuối chương: trạng thái 20 chương kế tiếp + Dịch thêm (ước lượng thời gian)
/// + toggle tự dịch trước 15 chương + Báo cáo chương lỗi.
/// ponytail: chỉ ở chế độ cuộn dọc — chế độ lật trang đổi chương qua trang đệm, thêm sau nếu cần.
class _EndPanel extends ConsumerStatefulWidget {
  final int novelId;
  final int chapterIndex;
  final Color fg;
  const _EndPanel({required this.novelId, required this.chapterIndex, required this.fg});
  @override
  ConsumerState<_EndPanel> createState() => _EndPanelState();
}

class _EndPanelState extends ConsumerState<_EndPanel> {
  bool _auto = prefs.getBool('auto_translate_ahead') ?? true;
  Timer? _tocPoll; // poll mục lục lười đang tải (reader đã gọi request_toc lúc mở)

  @override
  void dispose() {
    _tocPoll?.cancel();
    super.dispose();
  }

  String _eta(int chapters) {
    // ~40s/chương (model chính hiện tại) — ước lượng cho user chọn, không phải cam kết
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
    final ok = await showDialog<bool>(
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
    // Mục lục lười: truyện chưa ai đọc chỉ có vài stub mẫu; request_toc đã bắn lúc mở
    // reader, crawler tải đủ trong ~10-20s — poll tới khi đủ thì timer tự tắt.
    final total = (novel?['chapter_count_source'] ?? 0) as int;
    final tocLoading = list.isNotEmpty && list.length < total;
    if (tocLoading) {
      _tocPoll ??= Timer.periodic(const Duration(seconds: 5),
          (_) => ref.invalidate(chapterListProvider(widget.novelId)));
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
        // Tự dịch trước: mỗi lần sang chương sẽ xếp dịch tới chương hiện tại + 15.
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

Future<void> _showTtsVoiceSheet(
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

/// Thanh điều khiển nghe truyện: play/pause + chương đang đọc + giọng + tốc độ + tắt.
class _TtsBar extends StatelessWidget {
  final TtsState state;
  final Color fg, bg;
  const _TtsBar({required this.state, required this.fg, required this.bg});

  // flutter_tts: 0.5 = tốc độ chuẩn → nhãn quy về 1× (nhân đôi rate). 1.0 = trần engine.
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
          onPressed: () => _showTtsVoiceSheet(context, state, fg, bg),
        ),
        // bấm xoay vòng tốc độ — StatefulBuilder khỏi kéo cả reader rebuild
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

/// Bình luận cuối chương — nhóm bạn đọc chung thả cảm nghĩ, người đọc sau tới
/// chương này thì thấy. Dùng màu fg của reader (không lấy ColorScheme của app).
class _CommentsPanel extends ConsumerStatefulWidget {
  final int novelId;
  final int chapterIndex;
  final Color fg;
  const _CommentsPanel({required this.novelId, required this.chapterIndex, required this.fg});
  @override
  ConsumerState<_CommentsPanel> createState() => _CommentsPanelState();
}

class _CommentsPanelState extends ConsumerState<_CommentsPanel> {
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
                style: TextStyle(color: fg.withValues(alpha: 0.9), fontSize: 14),
                cursorColor: fg.withValues(alpha: 0.7),
                decoration: InputDecoration(
                  counterText: '', // khỏi hiện 0/2000 chật chỗ
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

/// Nút cơ duyên tu tiên trong chương: bấm → RPC cult_claim_gift → dialog vật phẩm.
/// Dùng màu fg của reader (không lấy ColorScheme của app).
class _GiftButton extends ConsumerStatefulWidget {
  final int novelId;
  final int chapterIndex;
  final Color fg;
  const _GiftButton({required this.novelId, required this.chapterIndex, required this.fg});
  @override
  ConsumerState<_GiftButton> createState() => _GiftButtonState();
}

class _GiftButtonState extends ConsumerState<_GiftButton> {
  bool _claiming = false;

  Future<void> _claim() async {
    if (_claiming) return;
    setState(() => _claiming = true);
    try {
      final it = await cultClaimGift(widget.novelId, widget.chapterIndex);
      if (!mounted) return;
      // nút tự ẩn (claims đổi) + kho ở màn Tu Tiên thấy đồ mới
      ref.invalidate(cultClaimedProvider(widget.novelId));
      ref.invalidate(cultInventoryProvider);
      ref.invalidate(cultCollectionProvider);
      final halo = it['halo'] as String?; // trận pháp hào quang (hậu phi thăng)
      if (halo != null) ref.invalidate(cultStateProvider); // đội tự động → cảnh đổi
      final grade = it['grade'] as int;
      // lời dẫn tất định theo chương — mỗi cơ duyên một tình huống khác nhau
      final flavor = giftFlavors[giftHash(sb.auth.currentUser!.id,
              widget.novelId, widget.chapterIndex) %
          giftFlavors.length];
      showDialog(
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

class _WaitingView extends StatelessWidget {
  final String? status;
  final Color color;
  final VoidCallback onRequest;
  const _WaitingView({required this.status, required this.color, required this.onRequest});

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
