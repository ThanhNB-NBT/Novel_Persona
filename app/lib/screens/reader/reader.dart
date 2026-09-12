import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../chapter_paras.dart';
import '../../cultivation.dart';
import '../../data.dart';
import '../../hanviet.dart';
import '../../theme.dart';
import '../../tts.dart';
import '../../widgets.dart';
import 'reader_dialogs.dart';
import 'reader_panels.dart';
import 'reader_settings.dart';
import 'reader_text.dart';

// Thuật toán ranh giới từ / phân đoạn / highlight TTS nằm ở reader_text.dart,
// sheet + dialog (sửa cả đoạn, báo lỗi, chọn giọng) ở reader_dialogs.dart.

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
  Timer? _statusPoll; // chương chưa 'done' (đang dịch/hàng đợi) → refetch tới khi xong
  bool _showBars = true; // bật/tắt thanh công cụ (AppBar/Bottom controls)

  // Bộ nhớ đệm phân trang (chế độ lật trang) — tính lại khi nội dung/cỡ chữ/kích thước đổi.
  List<String>? _pages;
  int? _pageKey;

  // Vuốt quá mép để đổi chương (cuộn dọc): cộng dồn độ overscroll, quá ngưỡng thì nhảy.
  double _overNext = 0, _overPrev = 0;
  bool _navigating = false;
  // Đỉnh kéo căng (px) để đổi chương. Nhỏ hơn mốc 90 cũ vì cách đo đã đổi:
  // trước là TỔNG overscroll cộng dồn, giờ là ĐỈNH khoảng cách vượt mép,
  // mà physics đàn hồi có ma sát nên đỉnh luôn nhỏ hơn tổng.
  static const _kOverscroll = 55.0;

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
    _statusPoll?.cancel();
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
    _localTtsPara.value = ttsLocalPara(st,
        novelId: novelId,
        chapterIndex: chapterIndex,
        paraAt: TtsPlayer.i.paraAt.value);
    if (ttsMovedAway(st, novelId: novelId, chapterIndex: chapterIndex) &&
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
    // extra = hướng vuốt → route chọn chiều trượt dọc cho khớp (main.dart)
    context.pushReplacement('/novel/$novelId/read/$index',
        extra: index > chapterIndex ? 1 : -1);
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
    // chạm trúng tên riêng → lấy trọn cụm viết hoa (cả tên), khỏi phải nới ⟨ ⟩ tay
    final (na, nb) = nameRunBounds(block, a, b);
    _sel.value = (block: block, start: na, end: nb);
    if (!_editing.value) {
      _editing.value = true;
    }
    // Điền sẵn để sửa vài ký tự chỉ cần gõ đè; select-all vẫn cho phép thay cả cụm ngay.
    _correct.value = TextEditingValue(
      text: block.substring(na, nb),
      selection: TextSelection(baseOffset: 0, extentOffset: nb - na),
    );
    _correctFocus.requestFocus();
    _revealTappedWord(globalPos);
  }

  /// Bàn phím + form che nửa dưới màn — nếu từ vừa chạm nằm dưới đó thì cuộn lên
  /// để vẫn thấy từ đang sửa (tô đỏ) trong trang. Chờ bàn phím trồi lên xong mới đo.
  void _revealTappedWord(Offset globalPos) {
    Future.delayed(const Duration(milliseconds: 350), () {
      if (!mounted || !_scroll.hasClients || !_editing.value) return;
      // getInheritedWidget… (KHÔNG phải MediaQuery.of): .of trong callback đăng ký
      // cả màn đọc phụ thuộc MediaQuery → mỗi frame bàn phím trượt là rebuild cả
      // nghìn từ, gây giật khi mở bàn phím. Ở đây chỉ cần ĐỌC giá trị một lần.
      final mq = context.getInheritedWidgetOfExactType<MediaQuery>()!.data;
      final visibleBottom = mq.size.height - mq.viewInsets.bottom - 230; // ~230 = form sửa
      if (globalPos.dy > visibleBottom) {
        final target = (_scroll.offset + (globalPos.dy - mq.size.height * 0.28))
            .clamp(0.0, _scroll.position.maxScrollExtent);
        _scroll.animateTo(target,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  /// Tên riêng tiếng Việt: MỌI từ viết hoa ("Lâm Hiên", "Trúc Cơ"). Dùng để quyết định
  /// cặp sửa có được đắp vào glossary (áp cho cả truyện) hay chỉ sửa chương này.
  static bool _looksLikeName(String s) {
    final words = s.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return false;
    return words.every((w) =>
        w[0].toUpperCase() == w[0] && w[0].toLowerCase() != w[0]);
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
    // Chỉ TÊN RIÊNG mới được đắp vào glossary: glossary áp cho MỌI chương sau bằng
    // string-replace, nên cặp từ thường ('em'→'muội') từng sinh ra "xmuội" khắp truyện.
    // Sửa từ thường vẫn có tác dụng — chỉ giới hạn trong chương đang đọc.
    final isName = _looksLikeName(w) && _looksLikeName(v);
    try {
      // p_para = đoạn đang chạm → server chỉ sửa trong đoạn đó, chỗ khác trong chương yên
      await editChapterText(novelId, chapterIndex, w, v, para: _sel.value?.block);
      if (isName) await submitCorrection(novelId, w, v); // glossary cho chương dịch SAU
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Chưa lưu được: $e')));
      }
      return; // giữ nguyên form để người dùng không mất bản đang gõ
    }
    _closeEdit();
    // refetch chương → bản sửa hiện NGAY
    ref.invalidate(chapterProvider(ChapterKey(novelId, chapterIndex)));
    if (mounted) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(SnackBar(
        content: Text(isName ? 'Đã sửa' : 'Đã sửa trong chương này'),
        duration: const Duration(milliseconds: 2500), // gọn — mặc định 4s hơi lâu
        // "Áp cả truyện" chạy string-replace theo glossary → chỉ mời khi vừa thêm TÊN
        // RIÊNG vào glossary; từ thường không có gì để áp, bấm chỉ tổ vá nhầm.
        action: !isName ? null : SnackBarAction(
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

  /// Viết lại NGUYÊN đoạn đang chạm — dialog nằm ở reader_dialogs.dart; lưu xong mới
  /// đóng form, refetch chương và báo "Đã sửa đoạn".
  Future<void> _editWholePara(String block) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await editWholeParaDialog(context,
        novelId: novelId, chapterIndex: chapterIndex, block: block);
    if (!ok) return;
    _closeEdit();
    // refetch chương → bản sửa hiện NGAY
    ref.invalidate(chapterProvider(ChapterKey(novelId, chapterIndex)));
    messenger.showSnackBar(const SnackBar(
        content: Text('Đã sửa đoạn'), duration: Duration(milliseconds: 2000)));
  }

  Future<void> _showTranslationReport(Sel sel, String selected) =>
      translationReportDialog(context,
          novelId: novelId, chapterIndex: chapterIndex, sel: sel, selected: selected);

  @override
  Widget build(BuildContext context) {
    final chapter = ref.watch(chapterProvider(ChapterKey(novelId, chapterIndex)));
    final previous = chapterIndex > 1
        ? ref.watch(chapterProvider(ChapterKey(novelId, chapterIndex - 1))).value
        : null;
    // Nạp SẴN chương sau ngay khi mở chương này: vuốt qua đáy là có dữ liệu liền,
    // không còn vòng quay chiếm cả màn giữa hai chương. Chương cuối trả null — vô hại.
    ref.watch(chapterProvider(ChapterKey(novelId, chapterIndex + 1)));
    ref.watch(glossaryProvider(novelId)); // nạp sẵn glossary để gợi ý khi sửa từ
    final s = ref.watch(readerSettingsProvider);
    // "Hệ thống" của reader = theo chế độ sáng/tối của app (chứ không phải OS thô),
    // để đặt tối trong Cài đặt app là màn đọc cũng tối theo.
    final col = s.resolve(appBrightness(ref, context));

    return Scaffold(
      backgroundColor: col.bg,
      resizeToAvoidBottomInset: false, // form sửa tự nâng theo viewInsets; giữ phân trang ổn định
      // header tối giản: thấp, chữ/icon mờ — nhường trọn sự chú ý cho trang chữ
      appBar: _showBars
          ? AppBar(
              toolbarHeight: 38,
              backgroundColor: col.bg,
              foregroundColor: col.fg.withValues(alpha: 0.55),
              iconTheme: IconThemeData(color: col.fg.withValues(alpha: 0.55), size: 20),
              elevation: 0,
              scrolledUnderElevation: 0,
              leading: IconButton(
                tooltip: 'Quay lại',
                icon: const Icon(Icons.arrow_back_rounded, size: 20),
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/novel/$novelId');
                  }
                },
              ),
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
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: ValueListenableBuilder<double>(
                  valueListenable: _percent,
                  builder: (_, p, _) => LinearProgressIndicator(
                    value: p,
                    minHeight: 1.5,
                    backgroundColor: Colors.transparent,
                    valueColor: AlwaysStoppedAnimation<Color>(col.fg.withValues(alpha: 0.2)),
                  ),
                ),
              ),
            )
          : null,
      // Thanh điều khiển nghe — chỉ hiện khi máy đọc đang chạy cho truyện này VÀ thanh công cụ đang bật
      bottomNavigationBar: _showBars
          ? ValueListenableBuilder<TtsState>(
              valueListenable: TtsPlayer.i.state,
              builder: (_, ts, _) => ts.novelId == novelId
                  ? TtsBar(state: ts, fg: col.fg, bg: col.bg)
                  : const SizedBox.shrink(),
            )
          : null,
      body: SafeArea(
        top: !_showBars,
        bottom: !_showBars,
        child: chapter.when(
        // Chương chưa dịch thì phải CHỜ worker dịch xong — đo trên máy thật là hơn
        // 20 giây. Spinner trơn giữa màn đen không nói được điều đó, người đọc tưởng
        // app treo. Không hiện % (tiến độ dịch không chia mốc được), chỉ một dòng chữ.
        loading: () => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('Đang tải chương…',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: col.fg.withValues(alpha: 0.6))),
          ]),
        ),
        error: (e, _) => AppError(e,
            onRetry: () =>
                ref.invalidate(chapterProvider(ChapterKey(novelId, chapterIndex)))),
        data: (c) {
          if (c == null) return Center(child: Text('Không có chương này', style: TextStyle(color: col.fg)));
          final status = c['translation_status'];
          // Đang dịch/hàng đợi (kể cả do dịch lại) → poll tới khi 'done' rồi tự hiện bản mới.
          _ensureStatusPoll(status != 'done');
          if (status != 'done') {
            return WaitingView(
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
          return false;
        }
        // Đo KHOẢNG CÁCH vượt mép chứ không cộng dồn OverscrollNotification:
        // từ khi cuộn đàn hồi (BouncingScrollPhysics) thì physics nuốt overscroll
        // vào chính vị trí, notification kia gần như không bắn nữa nên cách cũ
        // làm chết hẳn thao tác vuốt-quá-đáy-sang-chương-sau.
        final m = n.metrics;
        final over = m.pixels - m.maxScrollExtent;
        final under = m.minScrollExtent - m.pixels;
        if (over > _overNext) _overNext = over;
        if (under > _overPrev) _overPrev = under;
        if (n is ScrollEndNotification) {
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
      // .builder chứ KHÔNG phải ListView(children:): bản cũ dựng widget cho MỌI đoạn
      // của cả chương ngay lúc mở (chương 3-4 nghìn chữ = cả trăm đoạn, mỗi đoạn một
      // ValueListenableBuilder cho TTS). Đo được 74 frame rơi lúc mở chương, và mỗi
      // lần bàn phím đẩy Scaffold co lại (mở form sửa) là bố cục lại toàn bộ.
      // item 0 = tiêu đề, 1..n = đoạn, cuối = phần hết chương.
      child: ListView.builder(
        controller: _scroll,
        padding: EdgeInsets.fromLTRB(s.sideMargin, 10, s.sideMargin, 40),
        itemCount: paras.length + 2,
        itemBuilder: (context, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Text(title, style: titleStyle),
            );
          }
          if (i <= paras.length) {
            final p = i - 1;
            final para = Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _TapPara(
                para: paras[p],
                style: textStyle,
                align: s.justify ? TextAlign.justify : TextAlign.left,
                sel: _sel,
                onTapWord: _onTapWord,
                ttsPara: _localTtsPara,
                paraIndex: p,
                ttsHlColor: col.fg.withValues(alpha: 0.10),
              ),
            );
            // quà nằm NGAY DƯỚI đoạn của nó → gộp chung 1 item, khỏi lệch chỉ số
            if (p != giftAfter) return para;
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              para,
              GiftButton(novelId: novelId, chapterIndex: chapterIndex, fg: col.fg),
            ]);
          }
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SizedBox(height: 12),
            Divider(color: col.fg.withValues(alpha: 0.15)),
            const SizedBox(height: 8),
            Center(
              child: Text('Hết chương $chapterIndex · vuốt lên để đọc tiếp ↑', style: hint),
            ),
            const SizedBox(height: 16),
            EndPanel(novelId: novelId, chapterIndex: chapterIndex, fg: col.fg),
            CommentsPanel(novelId: novelId, chapterIndex: chapterIndex, fg: col.fg),
          ]);
        },
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
        // cùng độ đàn hồi với PageView đổi tab ở shell
        physics: const PageScrollPhysics(parent: BouncingScrollPhysics()),
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
                  GiftButton(novelId: novelId, chapterIndex: chapterIndex, fg: col.fg),
                EndPanel(novelId: novelId, chapterIndex: chapterIndex, fg: col.fg),
                CommentsPanel(novelId: novelId, chapterIndex: chapterIndex, fg: col.fg),
                const SizedBox(height: 16),
                Center(
                  child: Text('vuốt tiếp để sang chương sau →',
                      style: TextStyle(color: col.fg.withValues(alpha: 0.4), fontSize: 12)),
                ),
              ]),
            );
          }
          final c = i - lead;
          return Stack(
            fit: StackFit.expand,
            children: [
              // Đổ bóng gáy sách nhẹ nhàng ở mép trái tạo chiều sâu trang sách giấy
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 14,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.black.withValues(alpha: 0.04),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
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
              ),
              // Vùng nhận diện cử chỉ chạm (Tap zones): 25% trái (lùi), 50% giữa (bật/tắt thanh công cụ), 25% phải (tiến)
              Positioned.fill(
                child: Row(
                  children: [
                    // Chạm 25% mép trái: Lùi trang
                    Expanded(
                      flex: 25,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: () {
                          if (_pageCtrl.hasClients &&
                              (_pageCtrl.page?.round() ?? 0) > 0) {
                            HapticFeedback.selectionClick();
                            _pageCtrl.previousPage(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOutCubic,
                            );
                          }
                        },
                      ),
                    ),
                    // Chạm 50% vùng giữa: Bật/tắt thanh công cụ (hoặc đóng form sửa)
                    Expanded(
                      flex: 50,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: () {
                          if (_editing.value) {
                            _editing.value = false;
                            _sel.value = null;
                            FocusScope.of(context).unfocus();
                          } else {
                            setState(() => _showBars = !_showBars);
                          }
                        },
                      ),
                    ),
                    // Chạm 25% mép phải: Sang trang kế
                    Expanded(
                      flex: 25,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: () {
                          if (_pageCtrl.hasClients &&
                              (_pageCtrl.page?.round() ?? 0) < total - 1) {
                            HapticFeedback.selectionClick();
                            _pageCtrl.nextPage(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOutCubic,
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
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

  /// Cắt văn bản thành các trang vừa 1 màn — thuật toán nằm ở reader_text.dart
  /// (paginateText) để unit-test được.
  List<String> _paginate(
          String text, TextStyle style, double maxWidth, double pageH, double firstH) =>
      paginateText(text, style, maxWidth, pageH, firstH);

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
    // Ngữ cảnh 2 bên, cắt bớt cho gọn — đủ để biết câu nào mà không đẩy form cao lên.
    const kCtx = 60;
    final pre = block.substring(0, a);
    final post = block.substring(b);
    final ctxBefore =
        pre.length > kCtx ? '…${pre.substring(pre.length - kCtx)}' : pre;
    final ctxAfter = post.length > kCtx ? '${post.substring(0, kCtx)}…' : post;

    // Gợi ý bản đúng từ glossary truyện (tên/thuật ngữ đã có zh↔Hán-Việt khi dịch).
    // Khớp: từ đang chọn == correct_vi (đúng, hiện chữ Trung gốc) hoặc == wrong_vi /
    // chứa nhau (sai → gợi ý correct_vi). Đây là "từ điển" của chính truyện.
    final sel0 = wrong.trim();
    // Khớp KHÔNG phân biệt hoa/thường ("hiên" vẫn ra "Lâm Hiên") + theo TỪ: một từ
    // của vùng chọn trùng một từ trong term là gợi — trước đây bắt substring nguyên
    // cụm phân biệt hoa thường nên rất nhiều từ "trơ" không có gợi ý.
    final selLow = sel0.toLowerCase();
    // Giờ chạm là gom TRỌN tên (nameRunBounds) nên vùng chọn thường khớp nguyên tên →
    // chỉ cần CHỨA-NHAU, bỏ kiểu khớp theo-từng-chữ cũ (chung 1 chữ "Cảnh" là dính cả rổ).
    bool wordHit(String s) {
      if (s.isEmpty) return false;
      final low = s.toLowerCase();
      return low.contains(selLow) || selLow.contains(low);
    }

    // Gợi ý glossary CHỈ khi vùng chọn trông như TÊN RIÊNG (mọi từ viết hoa) — tên
    // trong bản Việt viết hoa từng chữ. Cụm thường ("giống như hệ thống") mà khớp lỏng
    // theo từ sẽ lôi cả rổ thuật ngữ chứa "hệ thống" ra → nhiễu. Chữ Hán sót xử riêng.
    bool isCap(String w) =>
        w.isNotEmpty && w[0].toUpperCase() == w[0] && w[0].toLowerCase() != w[0];
    final nameWords = sel0.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final looksLikeName = nameWords.isNotEmpty && nameWords.every(isCap);

    final terms = looksLikeName
        ? (ref.read(glossaryProvider(novelId)).value ?? const [])
        : const <Map<String, dynamic>>[];
    final sug = <Map<String, dynamic>>[];
    for (final tm in terms) {
      final zh = (tm['term_zh'] ?? '').toString();
      if (zh.isEmpty || sel0.isEmpty) continue;
      final hit = sel0.contains(zh) || // chọn trúng chữ Hán còn sót → term của chính nó
          wordHit((tm['correct_vi'] ?? '').toString()) ||
          wordHit((tm['wrong_vi'] ?? '').toString());
      if (hit) sug.add(tm);
      if (sug.length >= 6) break;
    }

    // Chọn trúng chữ Hán sót trong bản dịch → tra bảng ra thẳng âm Hán-Việt để điền,
    // kể cả khi glossary chưa có term (trước đây chọn chữ Hán là form trơ, không gợi gì).
    // Nếu vùng chọn là MỘT tên thuần chữ Hán → hiện các CÁCH ĐỌC để bấm chọn (đa âm).
    String? hanFill;
    String? hanName;
    if (sel0.isNotEmpty) {
      if (hanVietOnly.hasMatch(sel0)) {
        hanName = sel0;
      } else {
        final filled = sel0.replaceAllMapped(
            hanVietRun,
            (m) => hanVietOf(m.group(0)!) ?? m.group(0)!);
        if (filled != sel0) hanFill = filled;
      }
    }

    Widget extend(IconData icon, String tip, VoidCallback onTap) => IconButton.filledTonal(
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          onPressed: onTap,
          icon: Icon(icon, size: 20),
        );

    // Chip điền [text] vào ô sửa. alt=true: gợi ý tra-bảng (viền xanh, "tra bảng ⇒").
    Widget fillChip(String text, {bool alt = false}) => ActionChip(
          visualDensity: VisualDensity.compact,
          side: alt ? BorderSide(color: cs.primary.withValues(alpha: 0.6)) : null,
          label: Text(alt ? 'tra bảng ⇒ $text' : text,
              style: t.labelMedium?.copyWith(color: alt ? cs.primary : null)),
          onPressed: () {
            _correct.text = text;
            _correct.selection = TextSelection.collapsed(offset: _correct.text.length);
            _correctFocus.requestFocus();
          },
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
        // viền contour như hộp thoại/menu — tấm này tự dựng nên không ăn theme
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          side: BorderSide(color: panelRim(context)),
        ),
        child: Padding(
          // đáy: né bàn phím (viewInsets) HOẶC thanh điều hướng (viewPadding) + chừa 16.
          // Dùng *Of theo khía cạnh (không phải MediaQuery.of) để chỉ overlay này
          // rebuild theo bàn phím, không kéo cây ngoài.
          padding: EdgeInsets.fromLTRB(16, 10, 16,
              (MediaQuery.viewInsetsOf(context).bottom > 0
                      ? MediaQuery.viewInsetsOf(context).bottom
                      : MediaQuery.viewPaddingOf(context).bottom) +
                  16),
          // Chặn trần chiều cao: form + bàn phím từng ăn trọn màn hình. Chừa lại phần
          // trang đọc phía trên, phần thừa của form thì cuộn trong chính nó.
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: (MediaQuery.sizeOf(context).height -
                      MediaQuery.viewInsetsOf(context).bottom) *
                  0.62,
            ),
            child: SingleChildScrollView(
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
                  decoration: BoxDecoration(
                    color: cs.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: cs.error.withValues(alpha: 0.45)),
                  ),
                  // Hiện CẢ NGỮ CẢNH quanh từ sai, không chỉ mỗi từ: bàn phím mở là
                  // form + bàn phím phủ kín trang đọc, không còn thấy đang sửa ở đâu.
                  child: RichText(
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                      children: [
                        TextSpan(text: ctxBefore),
                        TextSpan(
                          text: wrong,
                          style: t.bodyMedium?.copyWith(
                            color: cs.error,
                            fontWeight: FontWeight.w700,
                            backgroundColor: cs.error.withValues(alpha: 0.16),
                          ),
                        ),
                        TextSpan(text: ctxAfter),
                      ],
                    ),
                  ),
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
            if (sug.isEmpty && hanFill == null && hanName == null) ...[
              // không có gì để gợi (từ thường, chưa có trong thuật ngữ) — nói rõ
              // thay vì form trơ khiến user tưởng lỗi
              const SizedBox(height: 8),
              Text('Từ này chưa có trong thuật ngữ truyện — gõ thẳng bản đúng bên dưới.',
                  style: t.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
            ],
            if (sug.isNotEmpty || hanFill != null || hanName != null) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 6, children: [
                // vùng chọn là tên chữ Hán → hiện các CÁCH ĐỌC để bấm chọn (đa âm ra nhiều)
                if (hanName case final hn?)
                  for (final c in hanVietCandidates(hn)) fillChip(c, alt: true),
                if (hanFill case final hf?) fillChip(hf, alt: true),
                for (final m in sug) ...[
                  fillChip('${m['correct_vi']}'),
                  // Cách đọc khác CHỈ hiện khi chọn ĐÚNG tên này (đa âm → nhiều ứng viên);
                  // khớp lỏng (chung 1 chữ) thì chỉ gợi bản đúng, khỏi xịt cách đọc lung tung.
                  if ('${m['correct_vi']}'.toLowerCase() == selLow)
                    for (final c in hanVietCandidates('${m['term_zh']}'))
                      if (c != '${m['correct_vi']}') fillChip(c, alt: true),
                ],
              ]),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: _correct,
              focusNode: _correctFocus,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submitEdit(wrong),
              decoration: const InputDecoration(
                labelText: 'Bản sửa',
                helperText: 'Đã điền sẵn từ đang chọn — gõ để thay.',
                isDense: true,
              ),
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
              // Câu tối nghĩa thì thay một từ không cứu được — mở luôn cả đoạn ra viết lại.
              child: OutlinedButton.icon(
                onPressed: () => _editWholePara(block),
                icon: const Icon(Icons.notes_rounded),
                label: const Text('Sửa cả đoạn'),
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
          ),
        ),
      )),
    );
  }

  Future<void> _retranslate() async {
    if (sb.auth.currentUser == null) {
      context.push('/login');
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    await retranslateChapter(novelId, chapterIndex); // RPC set status='queued'
    await addMyRetranslation(novelId, chapterIndex); // được báo khi worker xong (kể cả ngoài tủ)
    if (!mounted) return;
    // refetch → status 'queued' → _WaitingView "Đang dịch…"; _ensureStatusPoll tự cập
    // nhật khi worker xong. Không hiện bản cũ nữa.
    ref.invalidate(chapterProvider(ChapterKey(novelId, chapterIndex)));
    messenger.showSnackBar(const SnackBar(content: Text('Đang dịch lại chương…')));
  }

  /// Chương chưa 'done' → refetch định kỳ tới khi xong (worker đổi status/nội dung).
  /// Chạy đúng ở mọi đường vào reader vì bám status thật, không phải cờ cục bộ.
  void _ensureStatusPoll(bool waiting) {
    if (waiting) {
      _statusPoll ??= Timer.periodic(const Duration(seconds: 5), (_) {
        if (mounted) {
          ref.invalidate(chapterProvider(ChapterKey(novelId, chapterIndex)));
        }
      });
    } else {
      _statusPoll?.cancel();
      _statusPoll = null;
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

