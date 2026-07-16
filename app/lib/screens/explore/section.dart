import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data.dart';
import '../../widgets.dart';
import 'filter.dart';

/// "Xem tất cả" 1 mục Khám phá — danh sách đầy đủ, tải dần khi cuộn gần cuối.
/// ponytail: state phân trang giữ ngay trong màn (không cần provider riêng).
class SectionScreen extends ConsumerStatefulWidget {
  final SectionKind kind;
  const SectionScreen({super.key, required this.kind});
  @override
  ConsumerState<SectionScreen> createState() => _SectionScreenState();
}

class _SectionScreenState extends ConsumerState<SectionScreen> {
  static const _pageSize = 30;
  final _scroll = ScrollController();
  final _items = <Rec>[];
  bool _loading = false;
  bool _hasMore = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) _load();
  }

  Future<void> _load() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      final rows = await fetchNovelPage(widget.kind, _items.length, _pageSize);
      if (!mounted) return;
      setState(() {
        _items.addAll(rows);
        _hasMore = rows.length == _pageSize;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
        _hasMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(sectionTitles[widget.kind] ?? 'Truyện'),
        actions: [
          IconButton(
            tooltip: 'Lọc truyện',
            icon: const Icon(Icons.tune_rounded),
            onPressed: () async {
              final f = await showFilterSheet(context, const SearchFilter());
              if (f != null && context.mounted) {
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => FilterResultsScreen(filter: f)));
              }
            },
          ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_items.isEmpty) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      if (_error != null) return Center(child: Text('Lỗi: $_error'));
      return const Center(child: Text('Chưa có truyện nào.'));
    }
    // list dòng như cũ — user chê lưới poster tốn diện tích (2026-07-16)
    return ListView.separated(
      controller: _scroll,
      padding: const EdgeInsets.only(top: 4, bottom: 24),
      itemCount: _items.length + (_hasMore || _loading ? 1 : 0),
      separatorBuilder: (_, i) => i < _items.length - 1 ? const RowDivider() : const SizedBox.shrink(),
      itemBuilder: (_, i) {
        if (i >= _items.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final n = _items[i];
        return NovelListRow(n: n, onTap: () => context.push('/novel/${n['id']}'));
      },
    );
  }
}
