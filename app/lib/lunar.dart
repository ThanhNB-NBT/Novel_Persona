import 'dart:math' as math;

/// Âm lịch Việt Nam — thuật toán thiên văn của Hồ Ngọc Đức, múi giờ +7.
/// Múi giờ quyết định ngày sóc: lịch Việt (+7) và lịch Trung Quốc (+8) có năm lệch
/// nhau một ngày Tết (vd 1985), nên KHÔNG dùng thư viện lịch Trung Quốc.
class LunarDate {
  final int day, month, year;
  final bool leap; // tháng nhuận
  final int jd; // số ngày Julius của ngày dương tương ứng (cho can chi ngày)
  const LunarDate(this.day, this.month, this.year, this.leap, this.jd);

  String get yearName => '${_can[(year + 6) % 10]} ${_chi[(year + 8) % 12]}';
  String get monthCanChi => '${_can[(year * 12 + month + 3) % 10]} ${_chi[(month + 1) % 12]}';
  String get dayCanChi => '${_can[(jd + 9) % 10]} ${_chi[(jd + 1) % 12]}';

  /// "Tháng Tám", "Tháng Giêng", "Tháng Chạp" (+ " nhuận").
  String get monthName => 'Tháng ${_monthNames[month - 1]}${leap ? ' nhuận' : ''}';
}

const _can = ['Giáp', 'Ất', 'Bính', 'Đinh', 'Mậu', 'Kỷ', 'Canh', 'Tân', 'Nhâm', 'Quý'];
const _chi = ['Tý', 'Sửu', 'Dần', 'Mão', 'Thìn', 'Tỵ', 'Ngọ', 'Mùi', 'Thân', 'Dậu', 'Tuất', 'Hợi'];
const _monthNames = ['Giêng', 'Hai', 'Ba', 'Tư', 'Năm', 'Sáu', 'Bảy', 'Tám', 'Chín', 'Mười',
  'Mười Một', 'Chạp'];

const _tz = 7.0;

int _jdFromDate(int dd, int mm, int yy) {
  final a = (14 - mm) ~/ 12;
  final y = yy + 4800 - a;
  final m = mm + 12 * a - 3;
  return dd + (153 * m + 2) ~/ 5 + 365 * y + y ~/ 4 - y ~/ 100 + y ~/ 400 - 32045;
}

int _newMoonDay(int k) {
  final t = k / 1236.85, t2 = t * t, t3 = t2 * t;
  const dr = math.pi / 180;
  var jd1 = 2415020.75933 + 29.53058868 * k + 0.0001178 * t2 - 0.000000155 * t3;
  jd1 += 0.00033 * math.sin((166.56 + 132.87 * t - 0.009173 * t2) * dr);
  final m = 359.2242 + 29.10535608 * k - 0.0000333 * t2 - 0.00000347 * t3;
  final mpr = 306.0253 + 385.81691806 * k + 0.0107306 * t2 + 0.00001236 * t3;
  final f = 21.2964 + 390.67050646 * k - 0.0016528 * t2 - 0.00000239 * t3;
  var c1 = (0.1734 - 0.000393 * t) * math.sin(m * dr) + 0.0021 * math.sin(2 * dr * m);
  c1 = c1 - 0.4068 * math.sin(mpr * dr) + 0.0161 * math.sin(dr * 2 * mpr);
  c1 = c1 - 0.0004 * math.sin(dr * 3 * mpr);
  c1 = c1 + 0.0104 * math.sin(dr * 2 * f) - 0.0051 * math.sin(dr * (m + mpr));
  c1 = c1 - 0.0074 * math.sin(dr * (m - mpr)) + 0.0004 * math.sin(dr * (2 * f + m));
  c1 = c1 - 0.0004 * math.sin(dr * (2 * f - m)) - 0.0006 * math.sin(dr * (2 * f + mpr));
  c1 = c1 + 0.0010 * math.sin(dr * (2 * f - mpr)) + 0.0005 * math.sin(dr * (2 * mpr + m));
  final deltat = t < -11
      ? 0.001 + 0.000839 * t + 0.0002261 * t2 - 0.00000845 * t3 - 0.000000081 * t * t3
      : -0.000278 + 0.000265 * t + 0.000262 * t2;
  return (jd1 + c1 - deltat + 0.5 + _tz / 24).floor();
}

/// Cung hoàng đạo (0..11) của mặt trời lúc đầu ngày [jdn].
int _sunLongitude(int jdn) {
  final t = (jdn - 0.5 - _tz / 24 - 2451545.0) / 36525, t2 = t * t;
  const dr = math.pi / 180;
  final m = 357.52910 + 35999.05030 * t - 0.0001559 * t2 - 0.00000048 * t * t2;
  final l0 = 280.46645 + 36000.76983 * t + 0.0003032 * t2;
  var dl = (1.914600 - 0.004817 * t - 0.000014 * t2) * math.sin(dr * m);
  dl += (0.019993 - 0.000101 * t) * math.sin(dr * 2 * m) + 0.000290 * math.sin(dr * 3 * m);
  var l = (l0 + dl) * dr;
  l -= math.pi * 2 * (l / (math.pi * 2)).floor();
  return (l / math.pi * 6).floor();
}

/// Ngày bắt đầu tháng 11 âm (tháng chứa Đông chí) của năm [yy].
int _lunarMonth11(int yy) {
  final off = _jdFromDate(31, 12, yy) - 2415021;
  final k = (off / 29.530588853).floor();
  final nm = _newMoonDay(k);
  return _sunLongitude(nm) >= 9 ? _newMoonDay(k - 1) : nm;
}

int _leapMonthOffset(int a11) {
  final k = ((a11 - 2415021.076998695) / 29.530588853 + 0.5).floor();
  var i = 1;
  var arc = _sunLongitude(_newMoonDay(k + i));
  int last;
  do {
    last = arc;
    i++;
    arc = _sunLongitude(_newMoonDay(k + i));
  } while (arc != last && i < 14);
  return i - 1;
}

LunarDate toLunar(DateTime d) {
  final dayNumber = _jdFromDate(d.day, d.month, d.year);
  final k = ((dayNumber - 2415021.076998695) / 29.530588853).floor();
  var monthStart = _newMoonDay(k + 1);
  if (monthStart > dayNumber) monthStart = _newMoonDay(k);
  var a11 = _lunarMonth11(d.year);
  var b11 = a11;
  int lunarYear;
  if (a11 >= monthStart) {
    lunarYear = d.year;
    a11 = _lunarMonth11(d.year - 1);
  } else {
    lunarYear = d.year + 1;
    b11 = _lunarMonth11(d.year + 1);
  }
  final lunarDay = dayNumber - monthStart + 1;
  final diff = ((monthStart - a11) / 29).floor();
  var leap = false;
  var lunarMonth = diff + 11;
  if (b11 - a11 > 365) {
    final leapDiff = _leapMonthOffset(a11);
    if (diff >= leapDiff) {
      lunarMonth = diff + 10;
      if (diff == leapDiff) leap = true;
    }
  }
  if (lunarMonth > 12) lunarMonth -= 12;
  if (lunarMonth >= 11 && diff < 4) lunarYear -= 1;
  return LunarDate(lunarDay, lunarMonth, lunarYear, leap, dayNumber);
}
