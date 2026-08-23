import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data.dart';
import '../../../theme.dart';
import '../../../widgets.dart';
import 'shared.dart';

// ---------------- Crawl: config + nguồn + truyện mới 24h ----------------
class CrawlTab extends ConsumerStatefulWidget {
  const CrawlTab({super.key});

  @override
  ConsumerState<CrawlTab> createState() => _CrawlTabState();
}

class _CrawlTabState extends ConsumerState<CrawlTab> {
  // Mặc định THU GỌN hết: tab dài, admin mở đúng mục cần xem. Thẻ nhịp 24h ở đầu luôn
  // hiện nên vào tab vẫn thấy ngay hệ thống có chạy không.
  bool _openCfg = false, _openTrans = false, _openSrc = false, _openFresh = false;

  // Knob của translator (note bắt đầu 'DỊCH ·') tách nhóm riêng khỏi crawler.
  static bool _isTransKey(Rec s) => '${s['note'] ?? ''}'.startsWith('DỊCH');

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final settings = ref.watch(crawlSettingsProvider).value ?? const <Rec>[];
    final sources = ref.watch(crawlSourcesProvider).value ?? const <Rec>[];
    final fresh = ref.watch(newNovels24hProvider);

    Future<void> refresh() async {
      ref.invalidate(crawlSettingsProvider);
      ref.invalidate(crawlSourcesProvider);
      ref.invalidate(newNovels24hProvider);
      ref.invalidate(crawlPulseProvider);
      ref.invalidate(workerHeartbeatProvider);
    }

    // thẻ bo tròn viền mảnh — cùng ngôn ngữ với thẻ thống kê các tab khác
    Widget card(Widget child) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
            ),
            child: child,
          ),
        );

    // Nhãn mục = header bấm để thu gọn/mở: icon dẫn + tên nhấn + đếm/tóm tắt + chevron.
    Widget sectionLabel(IconData icon, String s,
            {String? hint, String? trailing, required bool open, required VoidCallback onToggle}) =>
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(icon, size: 15, color: cs.primary),
                const SizedBox(width: 7),
                Text(s,
                    style: t.labelSmall?.copyWith(letterSpacing: 1.5, color: cs.primary)),
                const Spacer(),
                if (trailing != null)
                  Text(trailing,
                      style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(width: 8),
                Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    size: 18, color: cs.onSurfaceVariant),
              ]),
              // ẩn hint khi thu gọn — gọn hẳn
              if (hint != null && open) ...[
                const SizedBox(height: 4),
                Text(hint, style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
              ],
            ]),
          ),
        );

    // 1 hàng cấu hình: tên thân thiện + key kỹ thuật (mono, mờ) + pill giá trị kèm bút
    // sửa — cả pill là affordance "bấm để sửa" rõ ràng.
    // pill giá trị: nền nhấn nhạt, bo tròn — dùng cho cả giá trị ngắn lẫn từng model dài
    Widget valuePill(String v, {bool mono = false}) => Container(
          padding: EdgeInsets.fromLTRB(mono ? 10 : 13, mono ? 4 : 6, mono ? 10 : 13, mono ? 4 : 6),
          decoration: BoxDecoration(
            color: cs.primaryContainer.withValues(alpha: mono ? 0.35 : 0.5),
            borderRadius: BorderRadius.circular(20),
          ),
          // mono = tên model/định danh kỹ thuật: chữ nhỏ, đều nét, đọc dễ hơn chữ tít
          child: Text(v,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: mono
                  ? monoStyle(context, size: 11, color: cs.primary)
                  : t.titleSmall?.copyWith(color: cs.primary)),
        );

    Widget settingRow(Rec s) {
      final value = '${s['value']}';
      final long = value.length > 16 || value.contains(',');
      return InkWell(
          onTap: () => _editSetting(context, ref, s),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // bỏ tiền tố nhóm 'DỊCH ·'/'CRAWL ·' — đã tách section rồi
                  Text('${s['note'] ?? s['key']}'.replaceFirst(RegExp(r'^(DỊCH|CRAWL) · '), ''),
                      style: t.bodyMedium),
                  const SizedBox(height: 3),
                  Text('${s['key']}',
                      style: monoStyle(context, size: 10.5, color: cs.onSurfaceVariant)),
                ]),
              ),
              const SizedBox(width: 10),
              if (!long) valuePill('${s['value']}'),
              if (long)
                Icon(Icons.edit_rounded, size: 15,
                    color: cs.primary.withValues(alpha: 0.7)),
            ]),
            // Giá trị dài (chuỗi model LLM dự phòng) nhét vào pill bên phải thì bị bóp
            // còn một ký tự mỗi dòng — cho xuống hàng riêng, mỗi model một chip.
            if (long) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final part in '${s['value']}'.split(',').map((e) => e.trim())
                    .where((e) => e.isNotEmpty))
                  valuePill(part, mono: true),
              ]),
            ],
          ]),
          ),
        );
    }

    // 1 hàng nguồn: tên + chip trạng thái màu (SỐNG/LỖI/TẮT) + host/nhịp gọn, switch
    // bật/tắt + pill quota riêng (bấm để chỉnh số truyện mới mỗi đợt của nguồn này).
    Widget sourceRow(Rec s) {
      final enabled = s['enabled'] == true;
      final failing = (s['fail_count'] ?? 0) > 0;
      final host = Uri.tryParse('${s['base_url']}')?.host.replaceFirst('www.', '') ??
          '${s['base_url']}';
      final (chip, chipColor) = !enabled
          ? ('TẮT', cs.onSurfaceVariant)
          : failing
              ? ('LỖI', cs.error)
              : ('SỐNG', kLive);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text('${s['name']}',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: t.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: enabled ? cs.onSurface : cs.onSurfaceVariant)),
                ),
                const SizedBox(width: 8),
                TagChip(chip, color: chipColor),
              ]),
              const SizedBox(height: 3),
              Text(
                [
                  host,
                  if (failing) 'fail ${s['fail_count']} chu kỳ',
                  if (enabled && s['last_ok_at'] != null)
                    'OK ${elapsed(s['last_ok_at'])} trước',
                ].join(' · '),
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: t.labelSmall?.copyWith(
                    color: failing ? cs.error : cs.onSurfaceVariant),
              ),
            ]),
          ),
          // Quota riêng của nguồn: truyện MỚI tối đa mỗi đợt discovery. NULL = theo
          // giá trị chung; bấm để chỉnh, worker tự nhận ở tick kế.
          const SizedBox(width: 8),
          _QuotaPill(
            quota: s['discover_quota'] as int?,
            onTap: () => _editQuota(context, ref, s),
          ),
          const SizedBox(width: 4),
          Switch(
            value: enabled,
            onChanged: (v) async {
              final messenger = ScaffoldMessenger.of(context);
              await setSourceEnabled(s['id'] as int, v);
              ref.invalidate(crawlSourcesProvider);
              messenger.showSnackBar(SnackBar(
                  content: Text(v
                      ? 'Đã bật ${s['name']} — crawler sẽ tự nhận trong khoảng 10 giây'
                      : 'Đã tắt ${s['name']}')));
            },
          ),
        ]),
      );
    }

    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const _CrawlPulseCard(),
          sectionLabel(Icons.translate_rounded, 'CẤU HÌNH DỊCH',
              hint: 'Sửa xong worker tự nhận trong ~1 phút — không cần restart.',
              open: _openTrans,
              onToggle: () => setState(() => _openTrans = !_openTrans)),
          if (_openTrans)
            card(Column(children: [
              for (final (i, s) in settings.where(_isTransKey).indexed) ...[
                if (i > 0) Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
                settingRow(s),
              ],
            ])),
          sectionLabel(Icons.tune_rounded, 'CẤU HÌNH CRAWLER',
              hint: 'Sửa xong worker tự nhận ở chu kỳ kế — không cần restart.',
              open: _openCfg,
              onToggle: () => setState(() => _openCfg = !_openCfg)),
          if (_openCfg)
            card(Column(children: [
              for (final (i, s) in settings.where((s) => !_isTransKey(s)).indexed) ...[
                if (i > 0) Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
                settingRow(s),
              ],
            ])),
          sectionLabel(Icons.dns_rounded, 'NGUỒN CRAWL',
              trailing: sources.isEmpty
                  ? null
                  : '${sources.where((s) => s['enabled'] == true && (s['fail_count'] ?? 0) == 0).length}'
                      '/${sources.length} sống',
              open: _openSrc,
              onToggle: () => setState(() => _openSrc = !_openSrc)),
          if (_openSrc)
            card(Column(children: [
              for (final (i, s) in sources.indexed) ...[
                if (i > 0) Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
                sourceRow(s),
              ],
            ])),
          fresh.when(
            loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Padding(
                padding: const EdgeInsets.all(16), child: Text('Lỗi: $e')),
            data: (list) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                sectionLabel(Icons.auto_awesome_rounded, 'TRUYỆN MỚI VỀ · 24 GIỜ',
                    hint: list.isEmpty
                        ? null
                        : '${list.length} truyện — Top #N = hạng trên bảng '
                            'tổng lượt đọc của nguồn (nguồn không công bố con số).',
                    open: _openFresh,
                    onToggle: () => setState(() => _openFresh = !_openFresh)),
                if (_openFresh)
                  if (list.isEmpty)
                    const Padding(
                        padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
                        child: Text('Chưa có truyện mới trong 24 giờ.'))
                  else
                    for (final (i, n) in list.indexed) ...[
                      if (i > 0) const Divider(height: 1, indent: 66),
                      _FreshNovelRow(n),
                    ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _editSetting(BuildContext context, WidgetRef ref, Rec s) {
    final ctrl = TextEditingController(text: '${s['value']}');
    // Knob số thì bắt số như cũ; knob CHUỖI (llm_model = danh sách model dự phòng) trước
    // đây rơi vào int.tryParse → bấm Lưu không có gì xảy ra, không sửa được từ app.
    final isNumber = int.tryParse('${s['value']}') != null;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s['note'] ?? s['key']),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: isNumber ? TextInputType.number : TextInputType.text,
            maxLines: isNumber ? 1 : null,
            decoration: InputDecoration(
              labelText: s['key'],
              helperText: isNumber ? null : 'Nhiều giá trị thì ngăn bằng dấu phẩy.',
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Huỷ')),
          FilledButton(
            onPressed: () async {
              final raw = ctrl.text.trim();
              if (raw.isEmpty) return;
              if (isNumber) {
                final v = int.tryParse(raw);
                if (v == null || v < 0) return; // số không âm (0 = tắt với knob hỗ trợ)
              }
              await updateCrawlSetting(s['key'] as String, raw);
              if (ctx.mounted) Navigator.pop(ctx);
              ref.invalidate(crawlSettingsProvider);
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }
  /// Dialog chỉnh quota riêng của 1 nguồn: số truyện MỚI tối đa mỗi đợt discovery.
  /// Để trống = về mặc định chung (worker_settings.discover_new_per_cycle).
  void _editQuota(BuildContext context, WidgetRef ref, Rec s) {
    final ctrl = TextEditingController(
        text: s['discover_quota'] == null ? '' : '${s['discover_quota']}');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Quota ${s['name']}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Số truyện mới / đợt',
            helperText:
                'Bỏ trống = theo giá trị chung (discover_new_per_cycle).',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Huỷ')),
          FilledButton(
            onPressed: () async {
              final raw = ctrl.text.trim();
              final q = raw.isEmpty ? null : int.tryParse(raw);
              if (raw.isNotEmpty && (q == null || q < 0)) return;
              await setSourceQuota(s['id'] as int, q);
              if (ctx.mounted) Navigator.pop(ctx);
              ref.invalidate(crawlSourcesProvider);
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }
}

/// Nhịp 24 giờ ở đầu tab Crawl: crawl về bao nhiêu, dịch xong bao nhiêu, còn kẹt bao
/// nhiêu — cộng nhịp tim hai tiến trình. Mọi mục bên dưới mặc định thu gọn nên đây là
/// thứ admin thấy đầu tiên khi mở tab.
class _CrawlPulseCard extends ConsumerWidget {
  const _CrawlPulseCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final p = ref.watch(crawlPulseProvider).value;
    final beats = ref.watch(workerHeartbeatProvider).value ?? const <Rec>[];
    Widget cell(int? v, String label, Color? c) => Expanded(
          child: Column(children: [
            Text(v == null ? '—' : '$v', style: t.headlineSmall?.copyWith(color: c)),
            const SizedBox(height: 2),
            Text(label, textAlign: TextAlign.center, style: t.labelSmall),
          ]),
        );
    final failedChapters = p?['failedChapters'] ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: cs.primaryContainer.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(children: [
          Row(children: [
            cell(p?['novels24h'], 'truyện mới\n24h', cs.primary),
            cell(p?['chapters24h'], 'chương về\n24h', cs.tertiary),
            cell(p?['done24h'], 'dịch xong\n24h', kLive),
            cell(failedChapters, 'chương lỗi',
                failedChapters > 0 ? cs.error : null),
          ]),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(children: [
              Text(
                [
                  '${p?['done1h'] ?? '—'} chương/giờ',
                  'chờ dịch ${p?['queued'] ?? '—'}',
                  'chưa dịch giới thiệu ${p?['metaPending'] ?? '—'}',
                  'job lỗi ${p?['failedJobs'] ?? '—'}',
                  'đang theo dõi ${p?['tracked'] ?? '—'} truyện',
                ].join(' · '),
                textAlign: TextAlign.center,
                style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              workerPulse(context, beats, 'crawler', 'Crawler'),
              const SizedBox(height: 6),
              workerPulse(context, beats, 'translator', 'Translator'),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Pill quota của nguồn: "10/đợt" khi có riêng, "chung" khi theo mặc định — cả pill
/// là affordance bấm để chỉnh. Ẩn màu nhẹ để không lấn át chip trạng thái.
class _QuotaPill extends StatelessWidget {
  final int? quota;
  final VoidCallback onTap;
  const _QuotaPill({required this.quota, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.filter_alt_outlined,
              size: 12, color: cs.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(quota == null ? 'chung' : '$quota/đợt',
              style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
        ]),
      ),
    );
  }
}

/// 1 truyện mới về: bìa + tên + lúc về + "Top #N · nguồn" (nguồn KHÔNG công bố số
/// lượt đọc — chỉ có thứ hạng trên bảng xếp hạng tổng lượt đọc của nguồn đó).
class _FreshNovelRow extends StatelessWidget {
  final Rec n;
  const _FreshNovelRow(this.n);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final title = n['title_vi'] ?? n['title_zh'] ?? 'Truyện #${n['id']}';
    final src = (n['sources'] as Map?)?['name'];
    final rank = n['source_rank'];
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(16, 2, 12, 2),
      leading: Cover(url: n['cover_url'], width: 38, aspect: 1.36, label: '$title'),
      title: Text('$title',
          maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleMedium),
      subtitle: Text(
        [
          'về ${elapsed(n['created_at'])} trước',
          '${n['chapter_count_source'] ?? 0} chương',
          n['status'] == 'completed' ? 'hoàn thành' : 'đang ra',
        ].join(' · '),
        maxLines: 1, overflow: TextOverflow.ellipsis,
        style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant),
      ),
      trailing: rank != null
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('Top #${(rank as int) + 1}${src != null ? ' · $src' : ''}',
                  style: t.labelSmall?.copyWith(
                      color: cs.primary, fontWeight: FontWeight.w700)),
            )
          : (src != null
              ? Text('$src', style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant))
              : null),
      onTap: () => context.push('/admin/novel/${n['id']}'),
    );
  }
}
