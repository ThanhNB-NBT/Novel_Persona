part of 'reader.dart';

// Chế độ lật trang của màn đọc — tách khỏi reader.dart (GĐ0 kế hoạch 2.0).
extension _ReaderPager on _ReaderScreenState {
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
                      onTap: _onTapContent,
                      terms: _markTerms(s),
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
                        onTap: _onTapContent,
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
}
