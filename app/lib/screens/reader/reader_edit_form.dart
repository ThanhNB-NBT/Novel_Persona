part of 'reader.dart';

// Form sửa bản dịch của màn đọc — tách khỏi reader.dart (GĐ0 kế hoạch 2.0).
extension _ReaderEditForm on _ReaderScreenState {
  // -------- Overlay form sửa (mở thẳng khi chạm từ), chỉ nó rebuild theo selection --------
  Widget _overlay(BuildContext context) => AnimatedBuilder(
        animation: Listenable.merge([_sel, _editing, _zhPick, _ai]),
        builder: (context, _) {
          final sel = _sel.value;
          if (sel == null || !_editing.value) return const SizedBox.shrink();
          // Consumer: chỉ form rebuild khi bản gốc tải xong, không kéo cả màn đọc
          return Consumer(builder: (context, ref, _) {
            final zh = ref.watch(chapterZhProvider(ChapterKey(novelId, chapterIndex))).value;
            return _editForm(context, sel, zh ?? '');
          });
        },
      );

  /// Form nhỏ ở đáy: từ đang sửa + 2 nút mở rộng vùng chọn (trái/phải) + đóng.
  Widget _editForm(BuildContext context, Sel sel, String zh) {
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

    final allTerms = ref.read(glossaryProvider(novelId)).value ?? const <Map<String, dynamic>>[];
    // Trước hết: tên có chữ Hán trong BẢN GỐC chương, giống vùng chọn khi bỏ dấu — bắt
    // được tên dịch lệch ("Ba La" → "Ba Lạp Ba Lạp") mà so chuỗi có dấu bên dưới trượt.
    // Không cần vùng chọn viết hoa: nguồn đã lọc sẵn nên ít nhiễu.
    final sug = termsFromSource(sel0, block, zh, allTerms);
    final terms = looksLikeName ? allTerms : const <Map<String, dynamic>>[];
    for (final tm in terms) {
      if (sug.length >= 6) break;
      if (sug.any((s) => s['correct_vi'] == tm['correct_vi'])) continue;
      final zh = (tm['term_zh'] ?? '').toString();
      if (zh.isEmpty || sel0.isEmpty) continue;
      final hit = sel0.contains(zh) || // chọn trúng chữ Hán còn sót → term của chính nó
          wordHit((tm['correct_vi'] ?? '').toString()) ||
          wordHit((tm['wrong_vi'] ?? '').toString());
      if (hit) sug.add(tm);
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

    // Câu GỐC chữ Trung của khối đang chạm (dòng zh↔vi khớp 1-1) + đoạn chữ Hán ứng với
    // vùng chọn: người dùng bôi trong câu gốc, không thì tự dò theo âm Hán-Việt. Có chữ
    // Trung thì tra nghĩa mới ra hồn — tra chữ Việt đã dịch sai chỉ ra đúng cái sai đó.
    final viText = (ref.read(chapterProvider(ChapterKey(novelId, chapterIndex))).value
            ?['content_vi'] ?? '')
        .toString();
    final src = sourceLineFor(block, viText, zh);
    final zhWord = _zhPick.value.isNotEmpty
        ? _zhPick.value
        : (src == null ? null : zhSpanFor(sel0, src));
    final zhReadings = zhWord == null || hanName != null
        ? const <String>[]
        : hanVietCandidates(zhWord)
            .where((c) => c.toLowerCase() != selLow)
            .toList();

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
            if (src != null) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                      zhWord == null
                          ? 'Câu gốc — bôi chữ để tra/phiên âm'
                          : 'Câu gốc — đang xét: $zhWord',
                      style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                  const SizedBox(height: 2),
                  SelectableText(
                    src,
                    minLines: 1, // thiếu minLines thì maxLines giữ chỗ đủ 4 dòng dù câu ngắn
                    maxLines: 4,
                    style: t.bodyMedium,
                    onSelectionChanged: (s, _) {
                      final v = s.textInside(src).trim();
                      if (v != _zhPick.value) _zhPick.value = v;
                    },
                  ),
                ]),
              ),
            ],
            if (sug.isEmpty && hanFill == null && hanName == null && zhReadings.isEmpty) ...[
              // không có gì để gợi (từ thường, chưa có trong thuật ngữ) — nói rõ
              // thay vì form trơ khiến user tưởng lỗi
              const SizedBox(height: 8),
              Text(
                  src == null
                      ? 'Từ này chưa có trong thuật ngữ truyện — gõ thẳng bản đúng bên dưới.'
                      : 'Chưa có trong thuật ngữ — bôi chữ tương ứng ở câu gốc rồi bấm Tra.',
                  style: t.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
            ],
            if (sug.isNotEmpty || hanFill != null || hanName != null || zhReadings.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 6, children: [
                // vùng chọn là tên chữ Hán → hiện các CÁCH ĐỌC để bấm chọn (đa âm ra nhiều)
                if (hanName case final hn?)
                  for (final c in hanVietCandidates(hn)) fillChip(c, alt: true),
                if (hanFill case final hf?) fillChip(hf, alt: true),
                // phiên âm Hán-Việt của chữ gốc đang xét (bôi tay hoặc tự dò)
                for (final c in zhReadings) fillChip(c, alt: true),
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
            // Gợi ý AI: chỉ khi có câu gốc (AI cần chữ Trung mới dịch lại được cho đúng).
            if (src != null) ...[
              const SizedBox(height: 8),
              switch (_ai.value) {
                null => Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                      onPressed: () => _askAi(src, block, sel0),
                      icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                      label: const Text('Gợi ý AI cách dịch khác'),
                    ),
                  ),
                (loading: true, items: _, err: _, thay: _, dung: _) => Row(children: [
                    const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 10),
                    Text('AI đang đọc câu gốc…', style: t.labelMedium),
                  ]),
                (
                  loading: false,
                  items: final items,
                  err: final err,
                  thay: final thay,
                  dung: final dung,
                ) =>
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (err != null)
                        Text(err, style: t.labelMedium?.copyWith(color: cs.error))
                      else
                        Text(
                            dung
                                ? 'AI: “$thay” đã dịch đúng'
                                    '${items.isEmpty ? '' : ' — cách nói tương đương:'}'
                                : 'AI gợi ý thay “$thay”:',
                            style: t.labelMedium?.copyWith(
                                color: dung ? cs.primary : cs.onSurfaceVariant)),
                      for (final g in items)
                        InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () {
                            // chạm một chữ ("nghiệm") mà AI xét cả cụm ("điểm kinh nghiệm")
                            // → nới vùng chọn ra trọn cụm, kẻo điền vào ra "điểm kinh thức ăn"
                            if (thay != wrong) {
                              final i = block.lastIndexOf(thay, a);
                              if (i >= 0 && i + thay.length >= b) {
                                _sel.value = (block: block, start: i, end: i + thay.length);
                              }
                            }
                            _correct.text = '${g['vi']}';
                            _correct.selection =
                                TextSelection.collapsed(offset: _correct.text.length);
                            _correctFocus.requestFocus();
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                            child: Row(children: [
                              Icon(Icons.auto_awesome_rounded, size: 16, color: cs.primary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text.rich(TextSpan(children: [
                                  TextSpan(
                                      text: '${g['vi']}',
                                      style: t.bodyMedium
                                          ?.copyWith(fontWeight: FontWeight.w600)),
                                  if ('${g['y'] ?? ''}'.isNotEmpty)
                                    TextSpan(
                                        text: ' · ${g['y']}',
                                        style: t.labelMedium
                                            ?.copyWith(color: cs.onSurfaceVariant)),
                                ])),
                              ),
                            ]),
                          ),
                        ),
                    ],
                  ),
              },
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
            const SizedBox(height: 8),
            // Kiểu chữ + tra cứu. Tên Hán-Việt nhiều âm tiết gõ tay hay sai hoa/thường
            // ("lâm hiên" / "Lâm hiên"), mà đây là thứ glossary áp cho CẢ truyện nên
            // sai một chữ hoa là lệch khắp nơi — bấm nút nhanh và chắc hơn gõ lại.
            Wrap(spacing: 6, runSpacing: 6, children: [
              _caseChip(context, 'Hoa Từng Chữ', _ReaderScreenState._titleCase),
              _caseChip(context, 'Hoa chữ đầu', _ReaderScreenState._sentenceCase),
              _caseChip(context, 'thường', (v) => v.toLowerCase()),
              ActionChip(
                visualDensity: VisualDensity.compact,
                avatar: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('Chép'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: wrong));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Đã chép'),
                    duration: Duration(milliseconds: 1200),
                  ));
                },
              ),
              ActionChip(
                visualDensity: VisualDensity.compact,
                avatar: const Icon(Icons.search_rounded, size: 16),
                label: Text(zhWord != null ? 'Tra $zhWord' : 'Tra'),
                // Tra CHỮ GỐC qua Google Dịch (zh→vi): chữ đang xét, không có thì cả câu gốc.
                // Không có nguồn (offline/lệch dòng) mới rơi về tìm chữ Việt như cũ.
                onPressed: () => launchUrl(
                  (zhWord ?? src) != null
                      ? Uri.https('translate.google.com', '/', {
                          'sl': 'zh-CN', 'tl': 'vi', 'op': 'translate',
                          'text': zhWord ?? src!,
                        })
                      : Uri.https('www.google.com', '/search', {'q': wrong}),
                  mode: LaunchMode.externalApplication,
                ),
              ),
            ]),
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
}
