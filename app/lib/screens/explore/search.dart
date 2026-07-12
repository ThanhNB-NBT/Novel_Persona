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
  final _ctrl = TextEditingController();
  String _query = '';
  Timer? _debounce; // gõ liên tục → chờ ngưng 300ms mới truy vấn (khỏi 1 query/phím)

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
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
                    setState(() => _query = v.trim()); // Enter = tìm ngay, khỏi chờ
                  },
                ),
              ),
            ]),
          ),
          Container(height: 1, color: cs.primary.withValues(alpha: 0.35)),
          Expanded(
            child: results == null
                ? Center(child: Text('Nhập tên truyện để tìm.', style: t.bodyMedium))
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
                              onTap: () => context.push('/novel/${list[i]['id']}'),
                            ),
                          ),
                  ),
          ),
        ]),
      ),
    );
  }
}
