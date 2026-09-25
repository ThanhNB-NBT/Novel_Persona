import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../lunar.dart';
import '../../theme.dart';
import '../../widgets.dart';

const _weekdays = ['Thứ Hai', 'Thứ Ba', 'Thứ Tư', 'Thứ Năm', 'Thứ Sáu', 'Thứ Bảy', 'Chủ Nhật'];

String _solarLine(DateTime d) =>
    '${_weekdays[d.weekday - 1]}, ${d.day.toString().padLeft(2, '0')}/'
    '${d.month.toString().padLeft(2, '0')}/${d.year}';

/// 'Tháng Tám' đứng giữa câu → 'tháng Tám' (tên tháng vẫn viết hoa).
String _inSentence(String monthName) => monthName.replaceFirst('Tháng', 'tháng');

/// Nhãn ngày đặc biệt: mùng 1 và rằm (ngày thắp hương), Tết.
String? _special(LunarDate l) => switch ((l.day, l.month, l.leap)) {
      (1, 1, false) => 'Tết Nguyên Đán',
      (15, 1, false) => 'Rằm tháng Giêng',
      (15, 7, false) => 'Rằm tháng Bảy',
      (15, 8, false) => 'Tết Trung Thu',
      (1, _, _) => 'Mùng 1',
      (15, _, _) => 'Ngày Rằm',
      _ => null,
    };

/// Khung lịch âm hôm nay ở màn Tôi — chạm mở lịch tháng.
class LunarTodayCard extends StatelessWidget {
  const LunarTodayCard({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final now = DateTime.now();
    final l = toLunar(now);
    final special = _special(l);
    return Semantics(
      button: true,
      label: 'Lịch âm hôm nay: ngày ${l.day} ${l.monthName} năm ${l.yearName}. Mở lịch tháng',
      excludeSemantics: true,
      child: Material(
        color: cs.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Rad.lg),
          side: BorderSide(color: cs.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/lunar'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
            child: Row(children: [
              // tờ lịch bóc: số ngày âm lớn, tên tháng âm nhỏ phía trên
              Container(
                width: 64,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(Rad.md),
                ),
                child: Column(children: [
                  Text('THÁNG ${l.month}${l.leap ? '*' : ''}',
                      style: t.labelSmall?.copyWith(color: cs.primary, letterSpacing: 0.8)),
                  Text('${l.day}',
                      style: monoStyle(context, size: 30, w: FontWeight.w700, color: cs.primary)),
                ]),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(
                      child: Text('${l.monthName} năm ${l.yearName}',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleMedium),
                    ),
                  ]),
                  const SizedBox(height: 2),
                  Text('Ngày ${l.dayCanChi} · tháng ${l.monthCanChi}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodySmall),
                  const SizedBox(height: 2),
                  Text(special == null ? _solarLine(now) : '$special · ${_solarLine(now)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodySmall?.copyWith(
                          color: special == null ? null : cs.primary,
                          fontWeight: special == null ? null : FontWeight.w600)),
                ]),
              ),
              Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Lịch tháng: lưới ngày dương, ngày âm nhỏ dưới mỗi ô; vuốt ngang / mũi tên đổi tháng.
class LunarCalendarScreen extends StatefulWidget {
  const LunarCalendarScreen({super.key});
  @override
  State<LunarCalendarScreen> createState() => _LunarCalendarScreenState();
}

class _LunarCalendarScreenState extends State<LunarCalendarScreen> {
  late DateTime _month; // ngày 1 của tháng đang xem
  late DateTime _selected;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selected = DateTime(now.year, now.month, now.day);
    _month = DateTime(now.year, now.month);
  }

  void _shift(int by) => setState(() => _month = DateTime(_month.year, _month.month + by));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final lead = _month.weekday - 1; // tuần bắt đầu Thứ Hai
    final cells = ((lead + daysInMonth) / 7).ceil() * 7;
    final sel = toLunar(_selected);
    final isCurrent = _month.year == today.year && _month.month == today.month;

    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          const PageHeader('ÂM LỊCH VIỆT NAM', 'Lịch âm', seal: '曆'),
          FadedExpanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragEnd: (d) {
                final v = d.primaryVelocity ?? 0;
                if (v.abs() > 200) _shift(v < 0 ? 1 : -1);
              },
              child: ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 24), children: [
                Row(children: [
                  IconButton(
                      tooltip: 'Tháng trước',
                      onPressed: () => _shift(-1),
                      icon: const Icon(Icons.chevron_left_rounded)),
                  Expanded(
                    child: Text('Tháng ${_month.month}, ${_month.year}',
                        textAlign: TextAlign.center, style: t.titleLarge),
                  ),
                  IconButton(
                      tooltip: 'Tháng sau',
                      onPressed: () => _shift(1),
                      icon: const Icon(Icons.chevron_right_rounded)),
                ]),
                if (!isCurrent)
                  Center(
                    child: TextButton(
                      onPressed: () => setState(() {
                        _month = DateTime(today.year, today.month);
                        _selected = today;
                      }),
                      child: const Text('Về hôm nay'),
                    ),
                  ),
                const SizedBox(height: 6),
                Row(children: [
                  for (final (i, w) in const ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'].indexed)
                    Expanded(
                      child: Text(w,
                          textAlign: TextAlign.center,
                          style: t.labelMedium?.copyWith(
                              color: i == 6 ? cs.error : cs.onSurfaceVariant)),
                    ),
                ]),
                const SizedBox(height: 6),
                GridView.count(
                  crossAxisCount: 7,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 0.82,
                  children: [
                    for (var i = 0; i < cells; i++)
                      if (i < lead || i >= lead + daysInMonth)
                        const SizedBox()
                      else
                        _DayCell(
                          date: DateTime(_month.year, _month.month, i - lead + 1),
                          today: today,
                          selected: _selected,
                          onTap: (d) => setState(() => _selected = d),
                        ),
                  ],
                ),
                const SizedBox(height: 12),
                _DetailCard(date: _selected, lunar: sel),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  final DateTime date, today, selected;
  final ValueChanged<DateTime> onTap;
  const _DayCell(
      {required this.date, required this.today, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final l = toLunar(date);
    final isToday = date == today;
    final isSel = date == selected;
    final sunday = date.weekday == DateTime.sunday;
    // mùng 1 ghi kèm tháng âm (như tờ lịch treo tường), rằm/mùng 1 tô màu nhấn
    final mark = l.day == 1 || l.day == 15;
    final lunarText = l.day == 1 ? '${l.day}/${l.month}${l.leap ? '*' : ''}' : '${l.day}';
    final fg = isToday ? cs.onPrimary : (sunday ? cs.error : cs.onSurface);
    return Semantics(
      button: true,
      selected: isSel,
      label: 'Ngày ${date.day}, âm lịch ${l.day} ${_inSentence(l.monthName)}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => onTap(date),
        child: AnimatedContainer(
          duration: Motion.fast,
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: isToday ? cs.primary : null,
            borderRadius: BorderRadius.circular(Rad.sm),
            border: Border.all(
                color: isSel && !isToday ? cs.primary : Colors.transparent, width: 1.6),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('${date.day}',
                style: t.titleMedium?.copyWith(color: fg, fontWeight: FontWeight.w700)),
            Text(lunarText,
                style: t.labelSmall?.copyWith(
                    color: isToday
                        ? cs.onPrimary.withValues(alpha: 0.85)
                        : (mark ? cs.primary : cs.onSurfaceVariant),
                    fontWeight: mark ? FontWeight.w700 : null)),
          ]),
        ),
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  final DateTime date;
  final LunarDate lunar;
  const _DetailCard({required this.date, required this.lunar});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final special = _special(lunar);
    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(children: [
            SizedBox(width: 92, child: Text(k, style: t.bodySmall)),
            Expanded(child: Text(v, style: t.bodyMedium?.copyWith(color: cs.onSurface))),
          ]),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(Rad.lg),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_solarLine(date), style: t.titleMedium),
        if (special != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(special,
                style: t.labelLarge?.copyWith(color: cs.primary)),
          ),
        const SizedBox(height: 4),
        row('Âm lịch', 'Ngày ${lunar.day} ${_inSentence(lunar.monthName)}'),
        row('Năm', lunar.yearName),
        row('Tháng', lunar.monthCanChi),
        row('Ngày', lunar.dayCanChi),
      ]),
    );
  }
}
