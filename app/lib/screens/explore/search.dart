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
    final results =
        _query.isEmpty ? null : ref.watch(searchProvider(SearchFilter(query: _query)));
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: TextField(
            controller: _ctrl,
            autofocus: true,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Tìm truyện theo tên…',
              border: InputBorder.none,
              filled: false,
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(() {
                        _ctrl.clear();
                        _query = '';
                      }),
                    ),
            ),
            onChanged: (v) => setState(() => _query = v.trim()),
          ),
        ),
      ),
      body: results == null
          ? Center(
              child: Text('Nhập tên truyện để tìm.',
                  style: Theme.of(context).textTheme.bodyMedium),
            )
          : results.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Text('Không tìm thấy “$_query”.',
                  style: Theme.of(context).textTheme.bodyMedium),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.only(top: 4, bottom: 24),
            itemCount: list.length,
            separatorBuilder: (_, _) => const RowDivider(),
            itemBuilder: (_, i) => NovelListRow(
              n: list[i],
              onTap: () => context.push('/novel/${list[i]['id']}'),
            ),
          );
        },
      ),
    );
  }
}
