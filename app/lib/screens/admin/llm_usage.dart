import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data.dart';
import '../../theme.dart';
import '../../widgets.dart';
import 'tabs/shared.dart';

// Chữ mono chỉ dùng độ đậm mặc định: app chỉ bundle JetBrainsMono-Medium, bậc khác phải tải
// mạng lúc chạy (và làm hỏng render test).

/// Thống kê API LLM (Gemini chính, NVIDIA dự phòng): biểu đồ request 14 ngày, lượt còn lại
/// của từng key × model so với trần free tier, sức khỏe model. Mục nào cũng thu gọn được.
///
/// Số liệu do worker ghi mỗi lần gọi model (bảng llm_usage, gộp theo giờ). "Ngày" ở đây là
/// NGÀY QUOTA của Google — nửa đêm giờ Pacific, tức 14:00 giờ VN (15:00 mùa đông) — để số
/// request khớp đúng con số AI Studio dùng khi chặn.
class LlmUsageScreen extends ConsumerStatefulWidget {
  const LlmUsageScreen({super.key});

  @override
  ConsumerState<LlmUsageScreen> createState() => _LlmUsageScreenState();
}

class _LlmUsageScreenState extends ConsumerState<LlmUsageScreen> {
  String? _day; // null = ngày quota hiện tại
  // mục đang thu gọn; mặc định đóng bảng chương theo model (số cộng dồn cũ, ít khi cần xem)
  final _closed = <String>{'tokens'};

  void _refresh() {
    ref.invalidate(llmUsageDailyProvider);
    ref.invalidate(crawlSettingsProvider);
    ref.invalidate(tokenUsageProvider);
  }

  @override
  Widget build(BuildContext context) {
    final usage = ref.watch(llmUsageDailyProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Thống kê API'),
        actions: [
          IconButton(
            tooltip: 'Làm mới',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _refresh,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: usage.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => AppError(e, onRetry: _refresh),
          data: (d) => _body(context, d),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, Rec d) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final rows = List<Rec>.from(d['usage'] ?? const []);
    final chapters = {
      for (final c in List<Rec>.from(d['chapters'] ?? const [])) '${c['day']}': c['n'] as int
    };
    final days = _lastDays(14);
    final day = _day ?? days.first;
    final settings = ref.watch(crawlSettingsProvider).value ?? const <Rec>[];
    final geminiRaw = '${settings.where((s) => s['key'] == 'gemini_models').firstOrNull?['value'] ?? ''}';
    final tokens = ref.watch(tokenUsageProvider).value ?? const <Rec>[];

    int sum(Iterable<Rec> rs, String f) => rs.fold(0, (a, r) => a + ((r[f] ?? 0) as int));
    Iterable<Rec> of(String dd, [String? provider]) =>
        rows.where((r) => r['day'] == dd && (provider == null || r['provider'] == provider));

    final today = of(day).toList();
    final req = sum(today, 'requests');
    final ok = sum(today, 'ok');

    // Sức khỏe model gộp từ sổ llm_usage (có từ bản Gemini 14/09) — bảng model_health cũ cộng
    // dồn từ thời NVIDIA, đầy model đã khai tử nên không dùng nữa.
    final health = <String, List<Rec>>{};
    for (final r in rows) {
      health.putIfAbsent('${r['model']}', () => []).add(r);
    }
    final healthRows = health.entries.toList()
      ..sort((a, b) => sum(b.value, 'requests').compareTo(sum(a.value, 'requests')));

    // Mục thu gọn được: header bấm để mở/đóng, như tab Crawl.
    Widget section(String id, IconData icon, String title, Widget body, {String? trailing}) {
      final open = !_closed.contains(id);
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          onTap: () => setState(() => open ? _closed.add(id) : _closed.remove(id)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
            child: Row(children: [
              Icon(icon, size: 15, color: cs.primary),
              const SizedBox(width: 7),
              Expanded(
                child: Text(title,
                    style: t.labelSmall?.copyWith(letterSpacing: 1.5, color: cs.primary)),
              ),
              if (trailing != null)
                Text(trailing, style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(width: 8),
              Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  size: 18, color: cs.onSurfaceVariant),
            ]),
          ),
        ),
        if (open) _card(context, body),
      ]);
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        // --- 14 ngày: cột chồng Gemini / NVIDIA, chạm cột để xem chi tiết ngày đó ---
        _card(context, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _legend(context, cs.primary, 'Gemini'),
            const SizedBox(width: 14),
            _legend(context, cs.tertiary, 'NVIDIA'),
            const Spacer(),
            Text('reset 14:00 VN',
                style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
          ]),
          const SizedBox(height: 12),
          _DayBars(
            days: days.reversed.toList(),
            selected: day,
            gemini: (dd) => sum(of(dd, 'gemini'), 'requests'),
            nvidia: (dd) => sum(of(dd, 'nvidia'), 'requests'),
            onTap: (dd) => setState(() => _day = dd == days.first ? null : dd),
          ),
        ])),

        section('day', Icons.today_rounded,
            day == days.first ? 'HÔM NAY · ${_dm(day)}' : 'NGÀY ${_dm(day)}',
            Column(children: [
              Row(children: [
                _stat(context, fmtThousands(req), 'request', cs.primary),
                _stat(context, fmtThousands(chapters[day] ?? 0), 'chương dịch', null),
                _stat(context, req == 0 ? '—' : '${(ok * 100 / req).round()}%', 'thành công',
                    req > 0 && ok / req < 0.85 ? cs.error : null),
              ]),
              const SizedBox(height: 10),
              Text(
                'Gemini ${fmtThousands(sum(of(day, 'gemini'), 'requests'))} · '
                'NVIDIA ${fmtThousands(sum(of(day, 'nvidia'), 'requests'))} · '
                '429: ${sum(today, 'rate_limited')} · lỗi khác: ${sum(today, 'failed')}\n'
                'token vào ${fmtThousands(sum(today, 'prompt_tokens'))} · '
                'ra ${fmtThousands(sum(today, 'completion_tokens'))}',
                textAlign: TextAlign.center,
                style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ])),

        section('keys', Icons.key_rounded, 'LƯỢT GEMINI THEO KEY',
            _GeminiQuota(
              models: parseGeminiModels(geminiRaw),
              dayRows: of(day, 'gemini').toList(),
              keys: {for (final r in rows.where((r) => r['provider'] == 'gemini')) '${r['key_label']}'}
                  .toList()
                ..sort(),
            )),

        if (of(day, 'nvidia').isNotEmpty)
          section('nvidia', Icons.swap_horiz_rounded, 'NVIDIA DỰ PHÒNG',
              Column(children: [for (final r in of(day, 'nvidia')) _usageRow(context, r)])),

        if (healthRows.isNotEmpty)
          section('health', Icons.monitor_heart_outlined, 'SỨC KHỎE MODEL',
              trailing: 'từ bản Gemini',
              Column(children: [
                for (final e in healthRows) _healthRow(context, e.key, e.value),
              ])),

        if (tokens.isNotEmpty)
          section('tokens', Icons.data_usage_rounded, 'CHƯƠNG ĐÃ DỊCH THEO MODEL',
              trailing: 'từ trước tới nay',
              Column(children: [
                for (final r in tokens)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(children: [
                      Expanded(
                        child: Text(r['model_used'] ?? '(?)',
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodyMedium),
                      ),
                      Text('${fmtThousands(r['chapters'] ?? 0)} ch · '
                          '${fmtThousands((r['prompt_tokens'] ?? 0) + (r['completion_tokens'] ?? 0))} tok',
                          style: monoStyle(context, size: 11)),
                    ]),
                  ),
              ])),
      ],
    );
  }
}

/// n ngày quota gần nhất, mới nhất trước, dạng 'yyyy-MM-dd' (khớp cột day của RPC).
/// ponytail: lấy Pacific = UTC-7 (giờ mùa hè). Mùa đông (UTC-8) lệch đúng 1 giờ quanh
/// nửa đêm Pacific — cột "hôm nay" có thể trống trong giờ đó; cần chính xác thì lấy
/// mốc ngày từ RPC.
List<String> _lastDays(int n) {
  final pacific = DateTime.now().toUtc().subtract(const Duration(hours: 7));
  final base = DateTime.utc(pacific.year, pacific.month, pacific.day);
  return [
    for (var i = 0; i < n; i++)
      base.subtract(Duration(days: i)).toIso8601String().substring(0, 10),
  ];
}

String _dm(String day) => '${day.substring(8, 10)}/${day.substring(5, 7)}';

Widget _card(BuildContext context, Widget child) {
  final cs = Theme.of(context).colorScheme;
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
    child: Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: child,
    ),
  );
}

Widget _legend(BuildContext context, Color c, String s) => Row(children: [
      Container(width: 10, height: 10,
          decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
      const SizedBox(width: 5),
      Text(s, style: Theme.of(context).textTheme.labelSmall),
    ]);

Widget _stat(BuildContext c, String v, String label, Color? color) => Expanded(
      child: Column(children: [
        Text(v, style: Theme.of(c).textTheme.headlineSmall?.copyWith(color: color)),
        Text(label, style: Theme.of(c).textTheme.bodySmall),
      ]),
    );

/// 1 dòng request theo key × model: số lượt + OK/429/lỗi + latency trung bình.
Widget _usageRow(BuildContext context, Rec r) {
  final t = Theme.of(context).textTheme;
  final cs = Theme.of(context).colorScheme;
  final req = (r['requests'] ?? 0) as int;
  final avg = req > 0 ? (r['total_latency_ms'] ?? 0) / req / 1000 : 0.0;
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${r['model']}', maxLines: 1, overflow: TextOverflow.ellipsis,
              style: monoStyle(context, size: 11.5, color: cs.onSurface)),
          Text('${r['key_label']} · OK ${r['ok']} · 429 ${r['rate_limited']} · lỗi ${r['failed']}'
              ' · ${avg.toStringAsFixed(1)}s TB',
              style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
        ]),
      ),
      Text(fmtThousands(req), style: t.titleSmall),
    ]),
  );
}

/// 1 dòng sức khỏe model (gộp các dòng llm_usage của model đó): chấm sống/chậm/chết + latency
/// TB + % OK + số 429/lỗi. Latency cộng cả lần lỗi (sổ không tách) nên hơi cao hơn lần OK.
Widget _healthRow(BuildContext context, String model, List<Rec> rs) {
  final t = Theme.of(context).textTheme;
  final cs = Theme.of(context).colorScheme;
  int sum(String f) => rs.fold(0, (a, r) => a + ((r[f] ?? 0) as int));
  final total = sum('requests'), ok = sum('ok');
  final rate = total > 0 ? ok / total : 0.0;
  final avgMs = total > 0 ? sum('total_latency_ms') / total : 0.0;
  // dưới 5 lượt chưa đủ kết luận: 1 request hỏng vì trần token từng làm 3.5-flash-lite "chết"
  final (dot, label) = total < 5
      ? (cs.onSurfaceVariant, 'ít dữ liệu')
      : (rate < 0.5)
      ? (cs.error, 'chết')
      : (avgMs > 90000 || rate < 0.85)
          ? (cs.tertiary, 'chậm')
          : (kLive, 'sống');
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Container(width: 10, height: 10,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(model, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleSmall),
          const SizedBox(height: 2),
          Text('${(avgMs / 1000).toStringAsFixed(1)}s TB · ${(rate * 100).round()}% OK '
              '($ok/$total) · 429: ${sum('rate_limited')} · lỗi: ${sum('failed')}',
              style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
        ]),
      ),
      Text(label, style: t.labelMedium?.copyWith(color: dot, fontWeight: FontWeight.w600)),
    ]),
  );
}

/// Biểu đồ cột chồng tự vẽ bằng Container — khỏi thêm thư viện chart cho 14 cột.
class _DayBars extends StatelessWidget {
  final List<String> days; // cũ → mới (trái → phải)
  final String selected;
  final int Function(String) gemini, nvidia;
  final ValueChanged<String> onTap;
  const _DayBars({
    required this.days,
    required this.selected,
    required this.gemini,
    required this.nvidia,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const h = 96.0;
    final peak = days.fold<int>(1, (m, d) => m > gemini(d) + nvidia(d) ? m : gemini(d) + nvidia(d));
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      for (final d in days)
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onTap(d),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (d == selected)
                Text(fmtThousands(gemini(d) + nvidia(d)),
                    maxLines: 1,
                    style: monoStyle(context, size: 9.5, color: cs.primary)),
              const SizedBox(height: 3),
              SizedBox(
                height: h,
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  for (final (v, c) in [(nvidia(d), cs.tertiary), (gemini(d), cs.primary)])
                    if (v > 0)
                      Container(
                        height: (h * v / peak).clamp(2.0, h),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: d == selected ? c : c.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                ]),
              ),
              const SizedBox(height: 5),
              Text(d.substring(8, 10),
                  style: monoStyle(context, size: 10,
                      color: d == selected ? cs.primary : cs.onSurfaceVariant)),
            ]),
          ),
        ),
    ]);
  }
}

/// Mỗi model Gemini (theo thứ tự ưu tiên của knob) + thanh lượt đã dùng / trần RPD từng key.
/// Model có request trong ngày mà không còn trong knob vẫn hiện (không có trần → không vẽ thanh).
class _GeminiQuota extends StatelessWidget {
  final List<GeminiModel> models;
  final List<Rec> dayRows;
  final List<String> keys;
  const _GeminiQuota({required this.models, required this.dayRows, required this.keys});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    if (keys.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text('Chưa có request Gemini nào — worker cần bản mới và key trong .env.',
            style: t.bodySmall),
      );
    }
    final names = [
      ...models.map((m) => m.name),
      ...{for (final r in dayRows) '${r['model']}'}.where((n) => !models.any((m) => m.name == n)),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final (i, name) in names.indexed) ...[
        if (i > 0) Divider(height: 18, color: cs.outlineVariant.withValues(alpha: 0.5)),
        () {
          final m = models.where((m) => m.name == name).firstOrNull;
          final used = dayRows.where((r) => r['model'] == name)
              .fold<int>(0, (a, r) => a + (r['requests'] as int));
          return Row(children: [
            Expanded(
              child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: monoStyle(context, size: 12, color: cs.onSurface)),
            ),
            Text(
              m == null
                  ? '$used · đã gỡ khỏi chuỗi'
                  : '$used/${fmtThousands(m.rpd * keys.length)} · ${m.rpm} RPM',
              style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ]);
        }(),
        const SizedBox(height: 6),
        for (final k in keys)
          () {
            final used = dayRows.where((r) => r['model'] == name && r['key_label'] == k)
                .fold<int>(0, (a, r) => a + (r['requests'] as int));
            final rpd = models.where((m) => m.name == name).firstOrNull?.rpd;
            final frac = rpd == null || rpd == 0 ? null : used / rpd;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                SizedBox(
                  width: 64,
                  child: Text(k, style: monoStyle(context, size: 10.5)),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: frac?.clamp(0.0, 1.0) ?? 0,
                      minHeight: 6,
                      backgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.6),
                      valueColor: AlwaysStoppedAnimation(
                          frac != null && frac >= 0.9 ? cs.error : cs.primary),
                    ),
                  ),
                ),
                SizedBox(
                  width: 70,
                  child: Text(rpd == null ? '$used' : '$used/$rpd',
                      textAlign: TextAlign.right,
                      style: monoStyle(context, size: 10.5,
                          color: frac != null && frac >= 0.9 ? cs.error : null)),
                ),
              ]),
            );
          }(),
      ],
    ]);
  }
}
