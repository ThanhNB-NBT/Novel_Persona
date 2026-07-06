import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data.dart';
import '../neo_theme.dart';
import '../neo_widgets.dart';

/// Tìm truyện theo tên — logic app cũ, ô nhập kiểu terminal.
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
    return NeoScaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 16, 6),
            child: Row(children: [
              IconButton(
                icon: Icon(Icons.arrow_back, color: Neo.dim),
                onPressed: () => context.pop(),
              ),
              Icon(Icons.search, size: 20, color: Neo.dim),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  style: Neo.mono(14, color: Neo.text),
                  cursorColor: Neo.cyan,
                  decoration: InputDecoration(
                    hintText: 'Tìm truyện theo tên…',
                    hintStyle: Neo.mono(12),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close, size: 18),
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
          Container(height: 1, color: Neo.cyan.withValues(alpha: 0.35)),
          Expanded(
            child: results == null
                ? const NeoMessage('Nhập tên truyện để tìm.')
                : results.when(
                    loading: () => const NeoLoading(label: 'Đang tìm…'),
                    error: (e, _) => NeoMessage('Lỗi: $e', error: true),
                    data: (list) => list.isEmpty
                        ? NeoMessage('Không tìm thấy "$_query".')
                        : ListView.separated(
                            padding: const EdgeInsets.only(top: 4, bottom: 24),
                            itemCount: list.length,
                            separatorBuilder: (_, _) => const NeoDivider(),
                            itemBuilder: (_, i) => NeoNovelRow(
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
