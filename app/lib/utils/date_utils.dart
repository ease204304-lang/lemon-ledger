/// 日期工具 (epoch day 转换) + 金额格式化 (千分位)
/// v1.5.0 抽出, 之前散落在 home_page / calendar_page / ranking_page 各处
library date_utils;

/// cents → "1,234.56" 千分位 + 2 位小数
String fmtCents(int cents) {
  if (cents == 0) return '0';
  final s = (cents / 100).toStringAsFixed(2);
  final parts = s.split('.');
  final intPart = parts[0];
  final buf = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
    buf.write(intPart[i]);
  }
  return '${buf.toString()}.${parts[1]}';
}

int dateToEpochDay(DateTime d) =>
    DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/
        86400000;

DateTime epochDayToDate(int day) {
  final ms = day * 86400000;
  final d = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  return DateTime(d.year, d.month, d.day);
}

int todayEpochDay() {
  final d = DateTime.now();
  return dateToEpochDay(DateTime(d.year, d.month, d.day));
}

/// cents → 带符号: income "+12.34" / expense "-12.34"
String signedAmountCents(int cents, bool isIncome) {
  final v = (cents / 100).toStringAsFixed(2);
  return isIncome ? '+$v' : '-$v';
}
