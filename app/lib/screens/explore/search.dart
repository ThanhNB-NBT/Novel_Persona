import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data.dart';
import '../../widgets.dart';
import '../library/library.dart' show showRequestSheet;

/// Tìm truyện theo tên (lọc theo tiêu chí là màn riêng — xem filter.dart).
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  static const _kHistoryKey = 'search_history_list';
  static const _kMaxHistory = 10;
  static const _kSuggestions = [
    'Tiên hiệp',
    'Huyền huyễn',
    'Đô thị',
    'Kiếm hiệp',
    'Xuyên không',
    'Hệ thống',
    'Trọng sinh',
    'Khoa huyễn',
  ];

  final _ctrl = TextEditingController();
  String _query = '';
  Timer? _debounce; // gõ liên tục → chờ ngưng 300ms mới truy vấn (khỏi 1 query/phím)
  List<String> _history = [];

  @override
  void initState() {
    super.initState();
    _history = prefs.getStringList(_kHistoryKey) ?? [];
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _saveHistory(String term) {
    final t = term.trim();
    if (t.isEmpty) return;
    _history.remove(t);
    _history.insert(0, t);
    if (_history.length > _kMaxHistory) {
      _history = _history.sublist(0, _kMaxHistory);
    }
    prefs.setStringList(_kHistoryKey, _history);
    if (mounted) setState(() {});
  }

  void _removeHistory(String term) {
    setState(() {
      _history.remove(term);
      prefs.setStringList(_kHistoryKey, _history);
    });
  }

  void _clearHistory() {
    setState(() {
      _history.clear();
      prefs.remove(_kHistoryKey);
    });
  }

  void _applyQuery(String q) {
    _debounce?.cancel();
    _ctrl.text = q;
    _ctrl.selection = TextSelection.fromPosition(TextPosition(offset: q.length));
    setState(() => _query = q.trim());
    _saveHistory(q);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final results =
        _query.isEmpty ? null : ref.watch(searchProvider(SearchFilter(query: _query)));
    // layout kiểu NEO: không AppBar — hàng nhập trần + gạch 1px màu nhấn bên dưới
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 16, 6),
            child: Row(children: [
              IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: cs.onSurfaceVariant),
                onPressed: () => context.pop(),
              ),
              Icon(Icons.search_rounded, size: 20, color: cs.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  cursorColor: cs.primary,
                  decoration: InputDecoration(
                    hintText: 'Tìm truyện theo tên…',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () {
                              _debounce?.cancel();
                              setState(() {
                                _ctrl.clear();
                                _query = '';
                              });
                            },
                          ),
                  ),
                  onChanged: (v) {
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 300), () {
                      if (mounted) setState(() => _query = v.trim());
                    });
                  },
                  onSubmitted: (v) {
                    _debounce?.cancel();
                    final q = v.trim();
                    setState(() => _query = q); // Enter = tìm ngay, khỏi chờ
                    if (q.isNotEmpty) _saveHistory(q);
                  },
                ),
              ),
            ]),
          ),
          Container(height: 1, color: cs.primary.withValues(alpha: 0.35)),
          Expanded(
            child: results == null
                ? _buildHistoryAndSuggestions(context, cs, t)
                : results.when(
                    loading: () => const SkeletonList(),
                    error: (e, _) => AppError(e,
                        onRetry: () => ref.invalidate(
                            searchProvider(SearchFilter(query: _query)))),
                    data: (list) => list.isEmpty
                        // không có trong kho → mời yêu cầu crawl luôn với tên đang gõ
                        ? Center(
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              Text('Không tìm thấy “$_query”.', style: t.bodyMedium),
                              const SizedBox(height: 14),
                              FilledButton.tonalIcon(
                                icon: const Icon(Icons.travel_explore_rounded, size: 18),
                                label: const Text('Yêu cầu tìm truyện này'),
                                onPressed: () =>
                                    showRequestSheet(context, initialQuery: _query),
                              ),
                            ]),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.only(top: 4, bottom: 24),
                            itemCount: list.length,
                            separatorBuilder: (_, _) => const RowDivider(),
                            itemBuilder: (_, i) => NovelListRow(
                              n: list[i],
                              onTap: () {
                                if (_query.isNotEmpty) _saveHistory(_query);
                                context.push('/novel/${list[i]['id']}');
                              },
                            ),
                          ),
                  ),
          ),
        ]),
      ),
    );
  }

  Widget _buildHistoryAndSuggestions(
      BuildContext context, ColorScheme cs, TextTheme t) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_history.isNotEmpty) ...[
            Row(
              children: [
                Icon(Icons.history_rounded, size: 18, color: cs.onSurfaceVariant),
                const SizedBox(width: 6),
                Text('Tìm kiếm gần đây',
                    style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const Spacer(),
                TextButton(
                  onPressed: _clearHistory,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: Text('Xóa tất cả',
                      style: TextStyle(color: cs.error, fontSize: 13)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _history
                  .map((term) => InputChip(
                        avatar: const Icon(Icons.history_rounded, size: 14),
                        label: Text(term),
                        onPressed: () => _applyQuery(term),
                        onDeleted: () => _removeHistory(term),
                        deleteIcon: const Icon(Icons.close_rounded, size: 15),
                        visualDensity: VisualDensity.compact,
                      ))
                  .toList(),
            ),
            const SizedBox(height: 22),
          ],
          Row(
            children: [
              Icon(Icons.local_fire_department_rounded, size: 18, color: cs.primary),
              const SizedBox(width: 6),
              Text('Từ khóa & Thể loại hot',
                  style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _kSuggestions
                .map((tag) => ActionChip(
                      label: Text(tag),
                      onPressed: () => _applyQuery(tag),
                      visualDensity: VisualDensity.compact,
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}
