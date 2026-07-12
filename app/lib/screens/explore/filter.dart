import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data.dart';
import '../../widgets.dart';

/// Mở form lọc (bottom sheet). Trả về SearchFilter nếu người dùng bấm "Xem kết quả".
Future<SearchFilter?> showFilterSheet(BuildContext context, SearchFilter initial) {
  return showModalBottomSheet<SearchFilter>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
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
    final t = Theme.of(context).textTheme;
    final genres = ref.watch(genresProvider).value ?? const [];
    final facets = ref.watch(filterFacetsProvider).value;
    final mins = minChapterThresholds(facets?.maxChapters ?? 0);
    final statuses = facets?.statuses ?? const <String>[];
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('Bộ lọc', style: t.headlineSmall),
            const Spacer(),
            TextButton(
              onPressed: () => setState(() {
                _min = 0;
                _genre = null;
                _status = null;
              }),
              child: const Text('Đặt lại'),
            ),
          ]),
          _label('Số chương tối thiểu'),
          _UnderlineTabs<int>(
            items: [for (final m in mins) (m, m == 0 ? 'Tất cả' : '$m+')],
            selected: _min,
            onSelect: (v) => setState(() => _min = v),
          ),
          _label('Trạng thái'),
          _UnderlineTabs<String?>(
            items: [(null, 'Tất cả'), for (final s in statuses) (s, statusLabel(s))],
            selected: _status,
            onSelect: (v) => setState(() => _status = v),
          ),
          if (genres.isNotEmpty) ...[
            _label('Thể loại'),
            // thể loại nhiều → wrap nhiều hàng nhưng CHẶN cao ~3 hàng, dư thì cuộn
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 132),
              child: SingleChildScrollView(
                child: _UnderlineTabs<String?>(
                  items: [(null, 'Tất cả'), for (final g in genres) (g as String?, g)],
                  selected: _genre,
                  onSelect: (v) => setState(() => _genre = v),
                  wrap: true,
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(
                  context, SearchFilter(minChapters: _min, genre: _genre, status: _status)),
              child: const Text('Xem kết quả'),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
        child: Text(text, style: Theme.of(context).textTheme.labelSmall),
      );
}

/// Hàng chọn kiểu tab chữ + gạch chân (cuộn ngang, gọn). Dùng cho số chương,
/// trạng thái, thể loại — các mục đều động theo dữ liệu crawl về.
class _UnderlineTabs<T> extends StatelessWidget {
  final List<(T, String)> items; // (giá trị, nhãn)
  final T selected;
  final ValueChanged<T> onSelect;
  final bool wrap; // true = xuống nhiều hàng (mục dài như thể loại)
  const _UnderlineTabs(
      {required this.items,
      required this.selected,
      required this.onSelect,
      this.wrap = false});

  Widget _item(BuildContext context, T value, String label) {
    final cs = Theme.of(context).colorScheme;
    final sel = value == selected;
    return GestureDetector(
      onTap: () => onSelect(value),
      behavior: HitTestBehavior.opaque,
      child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: sel ? cs.primary : cs.onSurfaceVariant,
                    fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
            const SizedBox(height: 4),
            Container(
              height: 2.5,
              width: sel ? 22 : 0,
              decoration: BoxDecoration(
                  color: cs.primary, borderRadius: BorderRadius.circular(2)),
            ),
          ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (wrap) {
      return Wrap(
        spacing: 18,
        runSpacing: 10,
        children: [for (final (v, l) in items) _item(context, v, l)],
      );
    }
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 18),
        itemBuilder: (_, i) => _item(context, items[i].$1, items[i].$2),
      ),
    );
  }
}

/// Màn danh sách kết quả lọc. Header: trái nút back, phải nút lọc (giữ trạng thái hiện tại).
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
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Kết quả lọc'),
        actions: [
          IconButton(
            tooltip: 'Chỉnh bộ lọc',
            icon: const Icon(Icons.tune_rounded),
            onPressed: _editFilter,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(children: [
        _activeChips(context),
        Expanded(
          child: results.when(
            loading: () => const SkeletonList(),
            error: (e, _) => AppError(e, onRetry: () => ref.invalidate(searchProvider(_filter))),
            data: (list) => list.isEmpty
                ? Center(
                    child: Text('Không có truyện phù hợp bộ lọc.',
                        style: Theme.of(context).textTheme.bodyMedium))
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
    );
  }

  Widget _activeChips(BuildContext context) {
    final parts = <String>[
      if (_filter.minChapters > 0) '≥ ${_filter.minChapters} chương',
      if (_filter.status != null)
        _filter.status == 'completed' ? 'Hoàn thành' : 'Đang ra',
      if (_filter.genre != null) _filter.genre!,
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Wrap(
        spacing: 8, runSpacing: 8,
        children: [for (final p in parts) TagChip(p)],
      ),
    );
  }
}
