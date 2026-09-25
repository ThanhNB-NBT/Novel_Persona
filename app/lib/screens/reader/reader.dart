import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
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

part 'reader_edit_form.dart';
part 'reader_pager.dart';

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
  // chữ Trung người dùng bôi trong câu gốc (form sửa) — rỗng = dùng đoạn tự dò
  final _zhPick = ValueNotifier<String>('');
  // Gợi ý AI cho đoạn đang sửa: null = chưa hỏi. _aiReq chặn kết quả về muộn của lần
  // chạm trước đè lên form của từ mới.
  final _ai = ValueNotifier<({bool loading, List<Rec> items, String? err, String thay, bool dung})?>(null);
  var _aiReq = 0;

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
    _zhPick.dispose();
    _ai.dispose();
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

  /// NHẤN GIỮ 1 từ trong đoạn → chọn từ đó + mở form sửa. Chạm thường chỉ bật/tắt thanh
  /// công cụ ([_onTapContent]) — 1.x mở form + bàn phím mỗi lần chạm, người đọc bực.
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
    _zhPick.value = '';
    _ai.value = null;
    _aiReq++;
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

  /// Thuật ngữ để gạch chân trong trang đọc — rỗng khi người dùng tắt công tắc.
  /// Trần 200 term: đoạn văn nào cũng quét cả danh sách, truyện lâu năm có hàng nghìn
  /// term thì mỗi lần cuộn là một vòng lặp thừa. Lấy term của CHÍNH truyện trước.
  List<String> _markTerms(ReaderSettings s) {
    if (!s.markGlossary) return const [];
    final rows = ref.read(glossaryProvider(novelId)).value ?? const <Rec>[];
    final out = <String>[];
    for (final r in rows) {
      final v = (r['correct_vi'] ?? '').toString().trim();
      if (v.length >= 2) out.add(v);
      if (out.length >= 200) break;
    }
    return out;
  }

  /// Chip đổi kiểu chữ cho ô "Bản sửa" — áp lên chữ đang gõ, giữ con trỏ ở cuối.
  Widget _caseChip(BuildContext context, String nhan, String Function(String) f) =>
      ActionChip(
        visualDensity: VisualDensity.compact,
        label: Text(nhan),
        onPressed: () {
          final v = f(_correct.text.trim());
          if (v.isEmpty || v == _correct.text) return;
          _correct.text = v;
          _correct.selection = TextSelection.collapsed(offset: v.length);
        },
      );

  static String _titleCase(String v) => v
      .split(RegExp(r'(\s+)'))
      .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1).toLowerCase())
      .join(' ');

  static String _sentenceCase(String v) =>
      v.isEmpty ? v : v[0].toUpperCase() + v.substring(1).toLowerCase();

  /// Hỏi Gemini (Edge Function goi-y-dich) 3-4 cách dịch cho [chon] trong câu [vi] có
  /// nguồn [zh] — cho từ thường mà glossary/Hán-Việt không có gì để gợi.
  Future<void> _askAi(String zh, String vi, String chon) async {
    final req = ++_aiReq;
    _ai.value = (loading: true, items: const <Rec>[], err: null, thay: chon, dung: false);
    try {
      final r = await goiYDich(zh, vi, chon);
      if (req != _aiReq) return;
      final items = [
        for (final g in (r['goi_y'] as List? ?? const []))
          if (g is Map) Map<String, dynamic>.from(g)
      ];
      final dung = r['dung'] == true;
      _ai.value = (
        loading: false,
        items: items,
        err: items.isEmpty && !dung ? 'AI không đưa ra được cách dịch khác' : null,
        thay: '${r['thay'] ?? chon}',
        dung: dung,
      );
    } catch (e) {
      if (req != _aiReq) return;
      _ai.value = (
        loading: false,
        items: const <Rec>[],
        err: 'Gợi ý AI lỗi — thử lại sau',
        thay: chon,
        dung: false,
      );
      debugPrint('goi-y-dich: $e');
    }
  }

  void _closeEdit() {
    _zhPick.value = '';
    _ai.value = null;
    _aiReq++;
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
                  tooltip: 'Mục lục',
                  icon: const Icon(Icons.format_list_bulleted_rounded, size: 19),
                  onPressed: () => showChapterTocSheet(context,
                      novelId: novelId, current: chapterIndex, onPick: _goChapter),
                ),
                IconButton(
                  tooltip: 'Cài đặt đọc',
                  icon: const Icon(Icons.text_fields_rounded, size: 19),
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
  void _toggleBars() => setState(() => _showBars = !_showBars);

  /// Chạm vào nội dung (cả chế độ cuộn lẫn vùng giữa chế độ lật trang):
  /// đang sửa thì đóng form, không thì bật/tắt thanh công cụ.
  void _onTapContent() {
    if (_editing.value) {
      _editing.value = false;
      _sel.value = null;
      FocusScope.of(context).unfocus();
    } else {
      _toggleBars();
    }
  }

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
                onTap: _onTapContent,
                ttsPara: _localTtsPara,
                paraIndex: p,
                ttsHlColor: col.fg.withValues(alpha: 0.10),
                terms: _markTerms(s),
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

/// Đoạn văn chạm-để-sửa: nhấn giữ từ nào là chọn từ đó; từ đang sửa tô nền đỏ
/// NGAY TRONG TRANG nên gõ trong form vẫn thấy rõ đang sửa chỗ nào.
/// Chỉ đoạn chứa vùng chọn rebuild khi selection đổi (ValueListenableBuilder).
class _TapPara extends StatelessWidget {
  final String para;
  final TextStyle style;
  final TextAlign align;
  final ValueNotifier<Sel?> sel;
  final void Function(String block, int offset, Offset globalPos) onTapWord; // nhấn giữ
  final VoidCallback onTap;
  // TTS: nghe chỉ số đoạn đang đọc; khi trùng paraIndex → tô nền + tự cuộn vào tầm mắt.
  final ValueNotifier<int>? ttsPara;
  final int paraIndex;
  final Color? ttsHlColor;
  // Thuật ngữ của truyện để gạch chân chỗ glossary đã áp; rỗng = tắt (mặc định).
  final List<String> terms;
  const _TapPara({
    required this.para,
    required this.style,
    required this.align,
    required this.sel,
    required this.onTapWord,
    required this.onTap,
    this.ttsPara,
    this.paraIndex = -1,
    this.ttsHlColor,
    this.terms = const [],
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

  /// Ghép hai lớp tô: gạch chân thuật ngữ (nền) + vùng đang sửa (đè lên, màu đỏ).
  /// Tách ra hàm riêng vì giờ phải cắt chuỗi theo NHIỀU mốc chứ không còn 3 mảnh.
  TextSpan _spans(ColorScheme cs, Sel? hl) {
    final marks = terms.isEmpty ? const <(int, int)>[] : glossaryRanges(para, terms);
    if (marks.isEmpty && hl == null) return TextSpan(text: para, style: style);

    // Mốc cắt: đầu/cuối mọi vùng. Đi tuần tự, mỗi khúc tra xem nằm trong lớp nào.
    final cuts = <int>{0, para.length};
    for (final m in marks) { cuts..add(m.$1)..add(m.$2); }
    if (hl != null) { cuts..add(hl.start)..add(hl.end); }
    final points = cuts.where((i) => i >= 0 && i <= para.length).toList()..sort();

    final children = <TextSpan>[];
    for (var k = 0; k + 1 < points.length; k++) {
      final a = points[k], b = points[k + 1];
      if (a >= b) continue;
      final inSel = hl != null && a >= hl.start && b <= hl.end;
      final inMark = marks.any((m) => a >= m.$1 && b <= m.$2);
      children.add(TextSpan(
        text: para.substring(a, b),
        style: inSel
            ? TextStyle(
                backgroundColor: cs.error.withValues(alpha: 0.22),
                color: cs.error,
                fontWeight: FontWeight.w600,
              )
            // Gạch chân mảnh thay vì tô nền: tên xuất hiện dày đặc, tô nền thì cả
            // trang loang lổ. Màu lấy theo chữ đang dùng (màn đọc có bảng màu riêng).
            : inMark
                ? TextStyle(
                    decoration: TextDecoration.underline,
                    decorationStyle: TextDecorationStyle.dotted,
                    decorationColor: (style.color ?? cs.onSurface)
                        .withValues(alpha: 0.45),
                  )
                : null,
      ));
    }
    return TextSpan(style: style, children: children);
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
            onTap: onTap,
            onLongPressStart: (d) {
              HapticFeedback.selectionClick();
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
              _spans(cs, hl),
              textAlign: align,
            ),
          );
        });
      },
    );
  }
}

