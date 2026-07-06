import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data.dart';
import '../neo_theme.dart';
import '../neo_widgets.dart';

/// Mở form lọc (bottom sheet HUD). Trả về SearchFilter nếu bấm "Xem kết quả".
Future<SearchFilter?> showFilterSheet(BuildContext context, SearchFilter initial) {
  return showModalBottomSheet<SearchFilter>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Neo.surface,
    shape: const Border(top: BorderSide(color: Neo.cyan, width: 1)),
    builder: (_) => _FilterForm(initial: initial),
  );
}

class _FilterForm extends ConsumerStatefulWidget {
  final SearchFilter initial;
  const _FilterForm({required this.initial});
  @override
  ConsumerState<_FilterForm> createState() => _FilterFormState();
}

class _FilterFormState extends ConsumerState<_FilterForm> {
  late int _min = widget.initial.minChapters;
  late String? _genre = widget.initial.genre;
  late String? _status = widget.initial.status;

  @override
  Widget build(BuildContext context) {
    final genres = ref.watch(genresProvider).value ?? const [];
    final facets = ref.watch(filterFacetsProvider).value;
    final mins = minChapterThresholds(facets?.maxChapters ?? 0);
    final statuses = facets?.statuses ?? const <String>[];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text('// BỘ LỌC', style: Neo.mono(13, color: Neo.cyan, weight: FontWeight.w700, spacing: 2)),
                const Spacer(),
                InkWell(
                  onTap: () => setState(() {
                    _min = 0;
                    _genre = null;
                    _status = null;
                  }),
                  child: Text('ĐẶT LẠI', style: Neo.mono(10, color: Neo.plasma, spacing: 2)),
                ),
              ]),
              _label('SỐ CHƯƠNG TỐI THIỂU'),
              _Segments<int>(
                items: [for (final m in mins) (m, m == 0 ? 'Tất cả' : '$m+')],
                selected: _min,
                onSelect: (v) => setState(() => _min = v),
              ),
              _label('TRẠNG THÁI'),
              _Segments<String?>(
                items: [(null, 'Tất cả'), for (final s in statuses) (s, statusLabel(s))],
                selected: _status,
                onSelect: (v) => setState(() => _status = v),
              ),
              if (genres.isNotEmpty) ...[
                _label('THỂ LOẠI'),
                _Segments<String?>(
                  items: [(null, 'Tất cả'), for (final g in genres) (g as String?, g)],
                  selected: _genre,
                  onSelect: (v) => setState(() => _genre = v),
                ),
              ],
              const SizedBox(height: 22),
              NeoButton(
                label: 'XEM KẾT QUẢ',
                onPressed: () => Navigator.pop(context,
                    SearchFilter(minChapters: _min, genre: _genre, status: _status)),
              ),
            ]),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 18, 0, 8),
        child: Text(text, style: Neo.mono(9, spacing: 3)),
      );
}

/// Hàng chọn dạng ô vát nhỏ (cuộn ngang) — bản NEO của underline tabs.
class _Segments<T> extends StatelessWidget {
  final List<(T, String)> items;
  final T selected;
  final ValueChanged<T> onSelect;
  const _Segments({required this.items, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final (value, label) = items[i];
          final sel = value == selected;
          return InkWell(
            onTap: () => onSelect(value),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: sel ? Neo.cyan.withValues(alpha: 0.12) : Colors.transparent,
                border: Border.all(color: sel ? Neo.cyan : Neo.faint),
              ),
              child: Text(label.toUpperCase(),
                  style: Neo.mono(10,
                      color: sel ? Neo.cyan : Neo.dim,
                      weight: sel ? FontWeight.w700 : FontWeight.w500,
                      spacing: 1.5)),
            ),
          );
        },
      ),
    );
  }
}

/// Màn kết quả lọc.
class FilterResultsScreen extends ConsumerStatefulWidget {
  final SearchFilter filter;
  const FilterResultsScreen({super.key, required this.filter});
  @override
  ConsumerState<FilterResultsScreen> createState() => _FilterResultsScreenState();
}

class _FilterResultsScreenState extends ConsumerState<FilterResultsScreen> {
  late SearchFilter _filter = widget.filter;

  Future<void> _editFilter() async {
    final f = await showFilterSheet(context, _filter);
    if (f != null && mounted) setState(() => _filter = f);
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(searchProvider(_filter));
    return NeoScaffold(
      body: SafeArea(
        child: Column(children: [
          NeoAppBar(title: 'Kết quả lọc', actions: [
            IconButton(
              tooltip: 'Chỉnh bộ lọc',
              icon: const Icon(Icons.tune, color: Neo.text, size: 22),
              onPressed: _editFilter,
            ),
          ]),
          _activeChips(),
          Expanded(
            child: results.when(
              loading: () => const NeoLoading(),
              error: (e, _) => NeoMessage('Lỗi: $e', error: true),
              data: (list) => list.isEmpty
                  ? const NeoMessage('KHÔNG CÓ TRUYỆN PHÙ HỢP BỘ LỌC')
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

  Widget _activeChips() {
    final parts = <String>[
      if (_filter.minChapters > 0) '≥ ${_filter.minChapters} CH',
      if (_filter.status != null)
        _filter.status == 'completed' ? 'Hoàn thành' : 'Đang ra',
      if (_filter.genre != null) _filter.genre!,
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(spacing: 8, runSpacing: 8, children: [for (final p in parts) NeoTag(p)]),
      ),
    );
  }
}
