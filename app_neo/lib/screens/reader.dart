import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data.dart';
import '../neo_theme.dart';
import '../neo_widgets.dart';
import 'novel_detail.dart' show translateRangeDialog;
import 'reader_settings.dart';

/// Vùng chữ đang chọn để sửa: khối chứa + vị trí đầu/cuối trong khối.
typedef Sel = ({String block, int start, int end});

bool isWs(String s, int i) => s[i] == ' ' || s[i] == '\n';

int wordLeft(String s, int a) {
  var i = a;
  while (i > 0 && isWs(s, i - 1)) { i--; }
  while (i > 0 && !isWs(s, i - 1)) { i--; }
  return i;
}

int wordRight(String s, int b) {
  var i = b;
  while (i < s.length && isWs(s, i)) { i++; }
  while (i < s.length && !isWs(s, i)) { i++; }
  return i;
}

final _sentenceEnd = RegExp(r'(?<=[.!?…。！？])\s+');

/// Tách đoạn dài thành câu (logic giữ nguyên app cũ).
List<String> splitBySentence(List<String> paras) {
  const minLen = 40;
  final out = <String>[];
  for (final p in paras) {
    final sentences =
        p.split(_sentenceEnd).where((s) => s.trim().isNotEmpty).toList();
    if (sentences.length <= 1) {
      out.add(p.trim());
      continue;
    }
    var buf = '';
    var count = 0;
    for (final s in sentences) {
      buf = buf.isEmpty ? s.trim() : '$buf ${s.trim()}';
      count++;
      if (buf.length >= minLen || count >= 3) {
        out.add(buf);
        buf = '';
        count = 0;
      }
    }
    if (buf.isNotEmpty) {
      if (buf.length < minLen && out.isNotEmpty) {
        out[out.length - 1] = '${out.last} $buf';
      } else {
        out.add(buf);
      }
    }
  }
  return out;
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

  final _sel = ValueNotifier<Sel?>(null);
  final _editing = ValueNotifier<bool>(false);

  bool _restored = false;
  int _restoreTries = 0;

  List<String>? _pages;
  int? _pageKey;

  double _overNext = 0, _overPrev = 0;
  bool _navigating = false;
  static const _kOverscroll = 90.0;

  // Đã từng thấy màn chờ dịch → khi chương done (realtime) chữ hiện kiểu decrypt.
  bool _sawWaiting = false;

  @override
  void initState() {
    super.initState();
    _persistChapter();
    _percent.value = chapterPercent(novelId, chapterIndex);
    _scroll.addListener(_onScroll);
  }

  Future<void> _persistChapter() async {
    await saveProgress(novelId, chapterIndex);
    if (!mounted) return;
    ref.invalidate(progressProvider(novelId));
    ref.invalidate(readingProvider);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _pageCtrl.dispose();
    _percent.dispose();
    _correct.dispose();
    _correctFocus.dispose();
    _sel.dispose();
    _editing.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    if (max <= 0) return;
    final pct = (_scroll.offset / max).clamp(0.0, 1.0);
    _percent.value = pct;
    saveChapterPercent(novelId, chapterIndex, pct);
  }

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
    _navigating = true;
    if (sb.auth.currentUser != null && (prefs.getBool('auto_translate_ahead') ?? true)) {
      requestTranslation(novelId, index + 15, priority: 5);
    }
    context.pushReplacement('/novel/$novelId/read/$index');
  }

  void _onTapWord(String block, int offset, Offset globalPos) {
    if (sb.auth.currentUser == null) {
      context.push('/login');
      return;
    }
    final off = offset.clamp(0, block.length);
    final a = wordLeft(block, off);
    final b = wordRight(block, off);
    if (b <= a) return;
    _sel.value = (block: block, start: a, end: b);
    if (!_editing.value) {
      _correct.clear();
      _editing.value = true;
    }
    _correctFocus.requestFocus();
    _revealTappedWord(globalPos);
  }

  void _revealTappedWord(Offset globalPos) {
    Future.delayed(const Duration(milliseconds: 350), () {
      if (!mounted || !_scroll.hasClients || !_editing.value) return;
      final mq = MediaQuery.of(context);
      final visibleBottom = mq.size.height - mq.viewInsets.bottom - 230;
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
    if (v.isEmpty || w.isEmpty || v == w) return;
    await editChapterText(novelId, chapterIndex, w, v);
    await submitCorrection(novelId, w, v);
    _closeEdit();
    ref.invalidate(chapterProvider(ChapterKey(novelId, chapterIndex)));
    if (mounted) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(SnackBar(
        content: const Text('Đã sửa'),
        duration: const Duration(milliseconds: 2500),
        action: SnackBarAction(
          label: 'Áp cả truyện',
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

  @override
  Widget build(BuildContext context) {
    final chapter = ref.watch(chapterProvider(ChapterKey(novelId, chapterIndex)));
    ref.watch(glossaryProvider(novelId));
    final s = ref.watch(readerSettingsProvider);
    final col = s.resolve(appBrightness(ref, context));

    return Scaffold(
      backgroundColor: col.bg,
      resizeToAvoidBottomInset: false,
      // header HUD mảnh: CH.0042 + % + settings — mờ, nhường chỗ cho trang chữ
      appBar: AppBar(
        toolbarHeight: 38,
        backgroundColor: col.bg,
        foregroundColor: col.fg.withValues(alpha: 0.55),
        iconTheme: IconThemeData(color: col.fg.withValues(alpha: 0.55), size: 20),
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 0,
        title: Text('Chương $chapterIndex',
            style: Neo.mono(12, color: col.fg.withValues(alpha: 0.55), spacing: 2)),
        actions: [
          ValueListenableBuilder<double>(
            valueListenable: _percent,
            builder: (_, p, _) => Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text('${(p * 100).round().toString().padLeft(3)}%',
                    style: Neo.mono(10, color: col.fg.withValues(alpha: 0.45))),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Cài đặt đọc',
            icon: const Icon(Icons.tune, size: 18),
            onPressed: () => showReaderSettingsSheet(context, ref, onRetranslate: _retranslate),
          ),
          const SizedBox(width: 2),
        ],
      ),
      body: chapter.when(
        loading: () => const NeoLoading(label: 'Đang tải chương…'),
        error: (e, _) => NeoMessage('Lỗi: $e', error: true),
        data: (c) {
          if (c == null) {
            return NeoMessage('Không có chương này.');
          }
          final status = c['translation_status'];
          if (status != 'done') {
            _sawWaiting = true; // khi realtime chuyển done → decrypt
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
              ?.replaceFirst(RegExp(r'^#+\s*'), '')
              .trim();
          final title = (rawTitle == null || rawTitle.isEmpty)
              ? 'Chương $chapterIndex'
              : rawTitle;
          final paras = splitBySentence(((c['content_vi'] as String?) ?? '')
              .split('\n')
              .where((p) => p.trim().isNotEmpty)
              .toList());
          if (paras.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.menu_book_outlined, size: 44, color: col.fg.withValues(alpha: 0.4)),
                  const SizedBox(height: 12),
                  Text('Chương này chưa có nội dung dịch.',
                      textAlign: TextAlign.center, style: TextStyle(color: col.fg)),
                  const SizedBox(height: 4),
                  Text('Bản dịch cũ có thể bị lỗi — thử dịch lại.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: col.fg.withValues(alpha: 0.6), fontSize: 13)),
                  const SizedBox(height: 16),
                  NeoButton(label: 'Dịch lại chương', onPressed: _retranslate),
                ]),
              ),
            );
          }
          final textStyle = readerFontStyle(s.fontKey,
              fontSize: s.fontSize, height: s.lineHeight, color: col.fg);

          final decrypt = _sawWaiting && !reduceMotion(context);
          _sawWaiting = false; // chỉ chạy 1 lần cho lần chuyển done này

          return Stack(
            fit: StackFit.expand,
            children: [
              s.pageMode
                  ? _buildPager(context, s, col, title, paras, textStyle)
                  : _buildScroll(context, s, col, title, paras, textStyle, decrypt),
              _overlay(context),
            ],
          );
        },
      ),
    );
  }

  // -------- Chế độ cuộn dọc --------
  Widget _buildScroll(BuildContext context, ReaderSettings s, ReaderColor col,
      String title, List<String> paras, TextStyle textStyle, bool decrypt) {
    _restoreScroll();
    final titleStyle = readerFontStyle(s.fontKey,
            fontSize: s.fontSize + 4, height: 1.3, color: col.fg)
        .copyWith(fontWeight: FontWeight.w700);
    final hint = TextStyle(color: col.fg.withValues(alpha: 0.5), fontSize: 13);
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
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
          for (final (i, para) in paras.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: decrypt
                  ? DecryptText(
                      text: para,
                      style: textStyle,
                      align: s.justify ? TextAlign.justify : TextAlign.left,
                      delay: Duration(milliseconds: (i * 90).clamp(0, 1400)),
                      child: _TapPara(
                        para: para,
                        style: textStyle,
                        align: s.justify ? TextAlign.justify : TextAlign.left,
                        sel: _sel,
                        onTapWord: _onTapWord,
                      ),
                    )
                  : _TapPara(
                      para: para,
                      style: textStyle,
                      align: s.justify ? TextAlign.justify : TextAlign.left,
                      sel: _sel,
                      onTapWord: _onTapWord,
                    ),
            ),
          const SizedBox(height: 12),
          Divider(color: col.fg.withValues(alpha: 0.15)),
          const SizedBox(height: 8),
          Center(
            child: Text('Hết chương $chapterIndex · vuốt lên để đọc tiếp ↑', style: hint),
          ),
          const SizedBox(height: 16),
          _EndPanel(novelId: novelId, chapterIndex: chapterIndex, fg: col.fg),
        ],
      ),
    );
  }

  // -------- Chế độ lật trang --------
  Widget _buildPager(BuildContext context, ReaderSettings s, ReaderColor col,
      String title, List<String> paras, TextStyle textStyle) {
    final normalized = paras.join('\n\n');
    final titleStyle = readerFontStyle(s.fontKey,
            fontSize: s.fontSize + 4, height: 1.3, color: col.fg)
        .copyWith(fontWeight: FontWeight.w700);

    return LayoutBuilder(builder: (context, cons) {
      final w = cons.maxWidth - s.sideMargin * 2;
      final h = cons.maxHeight - 20;
      final ttp = TextPainter(
          text: TextSpan(text: title, style: titleStyle),
          textDirection: TextDirection.ltr)
        ..layout(maxWidth: w);
      final firstH = (h - ttp.height - 18).clamp(60.0, h);

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
            final c = i - lead;
            final p = pages.length > 1 ? c / (pages.length - 1) : 1.0;
            _percent.value = p.clamp(0, 1);
            saveChapterPercent(novelId, chapterIndex, p);
          }
        },
        itemBuilder: (context, i) {
          if (lead == 1 && i == 0) return _pagerEdge(col, next: false);
          if (i == total - 1) return _pagerEdge(col, next: true);
          if (i == total - 2) {
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(s.sideMargin, 24, s.sideMargin, 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Center(
                  child: Text('Hết chương $chapterIndex',
                      style: TextStyle(color: col.fg.withValues(alpha: 0.5), fontSize: 13)),
                ),
                const SizedBox(height: 16),
                _EndPanel(novelId: novelId, chapterIndex: chapterIndex, fg: col.fg),
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
              physics: const NeverScrollableScrollPhysics(),
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

  Widget _pagerEdge(ReaderColor col, {required bool next}) {
    final c = col.fg.withValues(alpha: 0.55);
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(next ? Icons.chevron_right : Icons.chevron_left, size: 44, color: c),
        const SizedBox(height: 8),
        Text(next ? 'CHƯƠNG SAU' : 'CHƯƠNG TRƯỚC', style: Neo.mono(11, color: c, spacing: 2)),
      ]),
    );
  }

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
        final ws = text.lastIndexOf(RegExp(r'\s'), end - 1);
        if (ws > start) end = ws + 1;
      }
      if (end <= start) end = (start + 1).clamp(0, n);
      pages.add(text.substring(start, end).trim());
      start = end;
    }
    if (pages.isEmpty) pages.add('');
    return pages;
  }

  // -------- Overlay form sửa --------
  Widget _overlay(BuildContext context) => AnimatedBuilder(
        animation: Listenable.merge([_sel, _editing]),
        builder: (context, _) {
          final sel = _sel.value;
          if (sel == null || !_editing.value) return const SizedBox.shrink();
          return _editForm(context, sel);
        },
      );

  Widget _editForm(BuildContext context, Sel sel) {
    final block = sel.block;
    final a = sel.start.clamp(0, block.length);
    final b = sel.end.clamp(0, block.length);
    final wrong = block.substring(a, b);

    // Gợi ý bản đúng từ glossary truyện (logic giữ nguyên app cũ).
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
          (cv.isNotEmpty && (sel0.contains(cv) || cv.contains(sel0))) ||
          (wv.isNotEmpty && sel0.contains(wv));
      if (hit) sug.add(tm);
      if (sug.length >= 4) break;
    }

    Widget extend(IconData icon, String tip, VoidCallback onTap) => InkWell(
          onTap: onTap,
          child: Container(
            width: 36, height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: Neo.surface2, border: Border.all(color: Neo.faint)),
            child: Icon(icon, size: 20, color: Neo.cyan),
          ),
        );

    return Positioned(
      left: 0, right: 0, bottom: 0,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        builder: (context, v, child) => Transform.translate(
            offset: Offset(0, (1 - v) * 56),
            child: Opacity(opacity: v, child: child)),
        child: Container(
          decoration: BoxDecoration(
            color: Neo.surface,
            border: Border(top: BorderSide(color: Neo.cyan)),
            boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 18, offset: Offset(0, -4))],
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16,
                (MediaQuery.of(context).viewInsets.bottom > 0
                        ? MediaQuery.of(context).viewInsets.bottom
                        : MediaQuery.of(context).viewPadding.bottom) +
                    16),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text('Sửa bản dịch',
                        style: Neo.mono(12, color: Neo.cyan, weight: FontWeight.w700, spacing: 2)),
                    const Spacer(),
                    InkWell(
                      onTap: _closeEdit,
                      child: Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.close, size: 20, color: Neo.dim),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    extend(Icons.chevron_left, 'Mở rộng 1 từ sang trái', () {
                      final na = wordLeft(block, a);
                      if (na != a) _sel.value = (block: block, start: na, end: b);
                    }),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Neo.danger.withValues(alpha: 0.1),
                          border: Border.all(color: Neo.danger.withValues(alpha: 0.5)),
                        ),
                        child: Text(wrong,
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: Neo.danger, fontWeight: FontWeight.w600, fontSize: 15)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    extend(Icons.chevron_right, 'Mở rộng 1 từ sang phải', () {
                      final nb = wordRight(block, b);
                      if (nb != b) _sel.value = (block: block, start: a, end: nb);
                    }),
                  ]),
                  if (sug.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, runSpacing: 6, children: [
                      for (final m in sug)
                        InkWell(
                          onTap: () {
                            _correct.text = '${m['correct_vi']}';
                            _correct.selection =
                                TextSelection.collapsed(offset: _correct.text.length);
                            _correctFocus.requestFocus();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Neo.cyan.withValues(alpha: 0.08),
                              border: Border.all(color: Neo.cyan.withValues(alpha: 0.4)),
                            ),
                            child: Text('${m['term_zh']} → ${m['correct_vi']}',
                                style: Neo.mono(11, color: Neo.cyan)),
                          ),
                        ),
                    ]),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    controller: _correct,
                    focusNode: _correctFocus,
                    textInputAction: TextInputAction.done,
                    style: TextStyle(color: Neo.text, fontSize: 15),
                    onSubmitted: (_) => _submitEdit(wrong),
                    decoration: const InputDecoration(labelText: 'SỬA THÀNH', isDense: true),
                  ),
                  const SizedBox(height: 12),
                  NeoButton(label: 'Lưu', onPressed: () => _submitEdit(wrong)),
                ]),
          ),
        ),
      ),
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

/// Hiệu ứng "decrypt": ký tự nhiễu → rõ dần từ trái sang (chỉ khi chương vừa
/// dịch xong realtime). Xong animation thì trả về [child] (đoạn chạm-để-sửa).
class DecryptText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final TextAlign align;
  final Duration delay;
  final Widget child;
  const DecryptText({
    super.key,
    required this.text,
    required this.style,
    required this.align,
    required this.delay,
    required this.child,
  });

  @override
  State<DecryptText> createState() => _DecryptTextState();
}

class _DecryptTextState extends State<DecryptText>
    with SingleTickerProviderStateMixin {
  static const _noise = r'!<>-_\/[]{}—=+*^?#01';
  late final _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (widget.text.length * 4).clamp(350, 900)));
  final _rnd = math.Random();

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        if (_ctrl.isCompleted) return widget.child;
        final t = widget.text;
        final reveal = (_ctrl.value * t.length).floor();
        final buf = StringBuffer(t.substring(0, reveal));
        // dải ~14 ký tự sau điểm reveal là nhiễu, phần còn lại ẩn (giữ layout bằng khoảng trắng)
        final scrambleEnd = (reveal + 14).clamp(0, t.length);
        for (var i = reveal; i < scrambleEnd; i++) {
          buf.write(t[i] == ' ' ? ' ' : _noise[_rnd.nextInt(_noise.length)]);
        }
        if (_ctrl.value == 0 && widget.delay > Duration.zero) {
          // chưa tới lượt: giữ chỗ trống cùng chiều cao
          return Opacity(opacity: 0, child: Text(t, style: widget.style, textAlign: widget.align));
        }
        return Text.rich(
          TextSpan(style: widget.style, children: [
            TextSpan(text: buf.toString()),
            TextSpan(
                text: t.substring(scrambleEnd),
                style: const TextStyle(color: Colors.transparent)),
          ]),
          textAlign: widget.align,
        );
      },
    );
  }
}

/// Đoạn văn chạm-để-sửa (logic giữ nguyên app cũ).
class _TapPara extends StatelessWidget {
  final String para;
  final TextStyle style;
  final TextAlign align;
  final ValueNotifier<Sel?> sel;
  final void Function(String block, int offset, Offset globalPos) onTapWord;
  const _TapPara({
    required this.para,
    required this.style,
    required this.align,
    required this.sel,
    required this.onTapWord,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Sel?>(
      valueListenable: sel,
      builder: (context, s, _) {
        final hl = (s != null && s.block == para) ? s : null;
        return LayoutBuilder(builder: (context, cons) {
          final scaler = MediaQuery.textScalerOf(context);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) {
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
                          backgroundColor: Neo.danger.withValues(alpha: 0.22),
                          color: Neo.danger,
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

/// Panel cuối chương (logic giữ nguyên app cũ, style HUD theo màu nền đọc).
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Neo.surface,
        shape: NeoCutBorder(side: BorderSide(color: Neo.faint)),
        title: Text('Báo cáo chương lỗi',
            style: Neo.mono(13, color: Neo.text, weight: FontWeight.w700)),
        content: TextField(
          controller: reason,
          autofocus: true,
          maxLines: 3,
          style: TextStyle(color: Neo.text),
          decoration: const InputDecoration(
              labelText: 'Lỗi gì? (dịch sai, thiếu đoạn, trùng chương…)', isDense: true),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: Text('Huỷ', style: Neo.mono(11, color: Neo.dim))),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: Text('Gửi', style: Neo.mono(11, color: Neo.cyan, weight: FontWeight.w700))),
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
      decoration: ShapeDecoration(
        shape: NeoCutBorder(side: BorderSide(color: fg.withValues(alpha: 0.2))),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('20 chương kế tiếp',
            style: Neo.mono(10, color: fg.withValues(alpha: 0.45), spacing: 2)),
        const SizedBox(height: 6),
        Text(
          next.isEmpty
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
                shape: const RoundedRectangleBorder(),
              ),
              onPressed: () => translateRangeDialog(context, ref, widget.novelId,
                  translated: (novel?['chapter_count_translated'] ?? 0) as int,
                  source: (novel?['chapter_count_source'] ?? 0) as int,
                  onDone: () => ref.invalidate(chapterListProvider(widget.novelId))),
              icon: const Icon(Icons.playlist_add, size: 18),
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
            activeTrackColor: Neo.cyan.withValues(alpha: 0.5),
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

/// Màn chờ dịch: HUD progress + trạng thái mono.
class _WaitingView extends StatelessWidget {
  final String? status;
  final Color color;
  final VoidCallback onRequest;
  const _WaitingView({required this.status, required this.color, required this.onRequest});

  @override
  Widget build(BuildContext context) {
    final (label, showButton) = switch (status) {
      'queued' => ('Trong hàng đợi dịch…', false),
      'translating' => ('Đang dịch…', false),
      'failed' => ('Dịch lỗi', true),
      _ => ('Chương chưa được dịch', true),
    };
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (!showButton) const SizedBox(width: 180, child: HudProgress()),
        const SizedBox(height: 14),
        Text(label, style: Neo.mono(11, color: color.withValues(alpha: 0.8), spacing: 3)),
        if (showButton)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: SizedBox(
              width: 220,
              child: NeoButton(
                  label: status == 'failed' ? 'Dịch lại' : 'Yêu cầu dịch',
                  onPressed: onRequest),
            ),
          ),
      ]),
    );
  }
}
