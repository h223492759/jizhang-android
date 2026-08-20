import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

void toast(String msg) {
  // 用 floating SnackBar + 底部 margin 把 toast 抬到中心 FAB 之上，
  // 避免默认 SnackBar 紧贴底栏导致 FAB 短暂上移。
  scaffoldMessengerKey.currentState
    ?..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
}

String fmtMoney(num v) {
  final f = NumberFormat('#,##0.##', 'zh_CN');
  return f.format(v);
}

/// 固定两位小数（含 .00）——账单页等需要精确金额展示的场景
String fmtMoney2(num v) {
  final f = NumberFormat('#,##0.00', 'zh_CN');
  return f.format(v);
}

String fmtMoneySigned(num v, {bool expenseRed = false}) {
  final sign = v < 0 ? '-' : '';
  return '$sign${fmtMoney(v.abs())}';
}

/// 金额着色：支出红、收入绿
Color moneyColor(double v) =>
    v < 0 ? AppColorsExpense.income : AppColorsExpense.expense;

class AppColorsExpense {
  static const expense = Color(0xFFF04438);
  static const income = Color(0xFF2BA471);
}

String ym(DateTime d) => DateFormat('yyyy-MM').format(d);
String ymd(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
String ymdNow() => ymd(DateTime.now());

DateTime parseYmd(String s) => DateFormat('yyyy-MM-dd').parse(s);
DateTime parseYm(String s) => DateFormat('yyyy-MM').parse(s);

String monthLabel(String ymStr) {
  try {
    final d = parseYm(ymStr);
    return '${d.month}月';
  } catch (_) {
    return ymStr;
  }
}

/// 把后端返回的 flow_time (yyyy-MM-dd HH:mm:ss) 取日期部分
String datePart(String flowTime) {
  if (flowTime.length >= 10) return flowTime.substring(0, 10);
  return flowTime;
}

String weekdayCn(DateTime d) {
  const names = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  return names[(d.weekday - 1) % 7];
}
