import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data.dart';
import '../../widgets.dart';

/// Tìm truyện theo tên (lọc theo tiêu chí là màn riêng — xem filter.dart).
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _ctrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
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
                            onPressed: () => setState(() {
                              _ctrl.clear();
                              _query = '';
                            }),
                          ),
                  ),
                  onChanged: (v) => setState(() => _query = v.trim()),
                ),
              ),
            ]),
          ),
          Container(height: 1, color: cs.primary.withValues(alpha: 0.35)),
          Expanded(
            child: results == null
                ? Center(child: Text('Nhập tên truyện để tìm.', style: t.bodyMedium))
                : results.when(
                    loading: () => const AppLoading(),
                    error: (e, _) => Center(child: Text('Lỗi: $e')),
                    data: (list) => list.isEmpty
                        ? Center(
                            child: Text('Không tìm thấy “$_query”.', style: t.bodyMedium))
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
