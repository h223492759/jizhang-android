import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jizhang_android/core/util.dart';
import 'package:jizhang_android/state/session.dart';
import 'package:jizhang_android/screens/record/auto_record_dialog.dart';

/// 自动记账服务：从原生通知监听队列拉取待处理记录，
/// 解析金额/方向/商户 → 排除规则 → 去重 → 弹窗确认 → AI 分类落库。
class AutoRecordService {
  static const _channel = MethodChannel('jizhang/auto_record');
  static const _kEnabled = 'auto_record_enabled';
  static const _kExcludeRepay = 'auto_exclude_repay';
  static const _kExcludeSelfTransfer = 'auto_exclude_self_transfer';
  static const _kExcludeToUsers = 'auto_exclude_to_users';
  static const _kExcludeFromUsers = 'auto_exclude_from_users';
  static const _kUserList = 'auto_user_list';
  static const _kIgnoreMerchants = 'auto_ignore_merchants';
  static const _kDedupSeen = 'auto_dedup_seen';

  static AutoRecordService? _instance;
  static AutoRecordService get instance =>
      _instance ??= AutoRecordService._();

  Timer? _timer;

  AutoRecordService._();

  // ---------------- 设置存取 ----------------
  Future<bool> get enabled async =>
      (await SharedPreferences.getInstance()).getBool(_kEnabled) ?? false;

  Future<void> setEnabled(bool v) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kEnabled, v);
  }

  Future<Map<String, bool>> get excludes async {
    final sp = await SharedPreferences.getInstance();
    return {
      'repay': sp.getBool(_kExcludeRepay) ?? false,
      'selfTransfer': sp.getBool(_kExcludeSelfTransfer) ?? false,
      'toUsers': sp.getBool(_kExcludeToUsers) ?? false,
      'fromUsers': sp.getBool(_kExcludeFromUsers) ?? false,
    };
  }

  Future<void> setExcludes(Map<String, bool> v) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kExcludeRepay, v['repay'] ?? false);
    await sp.setBool(_kExcludeSelfTransfer, v['selfTransfer'] ?? false);
    await sp.setBool(_kExcludeToUsers, v['toUsers'] ?? false);
    await sp.setBool(_kExcludeFromUsers, v['fromUsers'] ?? false);
  }

  Future<List<String>> get userList async =>
      (await SharedPreferences.getInstance())
              .getStringList(_kUserList) ??
          [];

  Future<void> setUserList(List<String> list) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList(_kUserList, list);
  }

  Future<List<String>> get ignoreMerchants async =>
      (await SharedPreferences.getInstance())
              .getStringList(_kIgnoreMerchants) ??
          [];

  Future<void> setIgnoreMerchants(List<String> list) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList(_kIgnoreMerchants, list);
  }

  // ---------------- 去重指纹（持久化） ----------------
  Future<bool> _dedupHit(String key) async {
    final sp = await SharedPreferences.getInstance();
    final map = sp.getString(_kDedupSeen) ?? '';
    if (map.isEmpty) return false;
    try {
      final seen = jsonDecode(map) as Map<String, dynamic>;
      final hit = seen[key] != null;
      // 清理超过 1 天的指纹，防止无限膨胀
      final now = DateTime.now().millisecondsSinceEpoch;
      seen.removeWhere((k, v) => now - (v as num).toInt() >
          const Duration(days: 1).inMilliseconds);
      await sp.setString(_kDedupSeen, jsonEncode(seen));
      return hit;
    } catch (_) {
      return false;
    }
  }

  Future<void> _dedupMark(String key) async {
    final sp = await SharedPreferences.getInstance();
    final map = (sp.getString(_kDedupSeen) ?? '');
    Map<String, dynamic> seen;
    try {
      seen = (jsonDecode(map) as Map<String, dynamic>? ?? {});
    } catch (_) {
      seen = {};
    }
    seen[key] = DateTime.now().millisecondsSinceEpoch;
    await sp.setString(_kDedupSeen, jsonEncode(seen));
  }

  // ---------------- 原生队列 ----------------
  Future<List<Map<String, dynamic>>> fetchPending() async {
    try {
      final r = await _channel.invokeMethod('fetchPending');
      if (r is! List) return [];
      return r.map((e) => (e as String)).map((s) {
        try {
          return jsonDecode(s) as Map<String, dynamic>;
        } catch (_) {
          return <String, dynamic>{};
        }
      }).where((m) => m.isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> removePending(String id) async {
    try {
      await _channel.invokeMethod('removePending', {'id': id});
    } catch (_) {}
  }

  // ---------------- 轮询 ----------------
  void startPolling(WidgetRef ref, BuildContext context) {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!context.mounted) return;
      processNow(ref, context);
    });
  }

  void stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  /// 立即处理一次待处理队列（App 启动 / 回到前台时调用）
  Future<void> processNow(WidgetRef ref, BuildContext context) async {
    try {
      await _processQueue(ref, context);
    } catch (_) {}
  }

  // ---------------- 主流程 ----------------
  Future<void> _processQueue(WidgetRef ref, BuildContext context) async {
    if (!(await enabled)) return;
    final s = ref.read(sessionProvider);
    if (!s.hasToken || !s.hasBook) return;
    final pending = await fetchPending();
    if (pending.isEmpty) return;
    for (final raw in pending) {
      if (!context.mounted) return;
      final parsed = _parse(raw);
      if (parsed == null) {
        await removePending(raw['id']?.toString() ?? '');
        continue;
      }
      // 排除规则
      if (await _excluded(parsed)) {
        await removePending(raw['id']?.toString() ?? '');
        continue;
      }
      // 去重：商户+金额+2分钟
      final dedupKey = '${parsed.merchant}|${parsed.amount.toStringAsFixed(2)}';
      if (await _dedupHit(dedupKey)) {
        await removePending(raw['id']?.toString() ?? '');
        continue;
      }
      // 弹窗确认（强制）
      if (!context.mounted) return;
      final result = await showDialog<AutoRecordAction>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AutoRecordDialog(parsed: parsed),
      );
      if (!context.mounted) continue;
      await removePending(raw['id']?.toString() ?? '');
      if (result == null) continue; // 忽略
      if (result.ignore) continue;
      if (result.neverAgain) {
        await _addExcludeFromDialog(result);
        continue;
      }
      await _dedupMark(dedupKey);
      await _saveFlow(ref, result);
    }
  }

  // 解析通知文本 → 结构化记录
  ParsedNotification? _parse(Map<String, dynamic> raw) {
    final text = '${raw['title'] ?? ''} ${raw['text'] ?? ''}';
    if (text.trim().isEmpty) return null;
    // 金额
    final amtMatch = RegExp(r'[¥￥]\s*([0-9]+(?:\.[0-9]{1,2})?)')
            .firstMatch(text) ??
        RegExp(r'([0-9]+(?:\.[0-9]{1,2})?)\s*元').firstMatch(text);
    if (amtMatch == null) return null;
    final amount = double.tryParse(amtMatch.group(1) ?? '');
    if (amount == null || amount <= 0) return null;
    // 方向：收入/收款 → income；否则 expense
    final isIncome =
        text.contains('收入') || text.contains('收款') || text.contains('入账');
    // 商户：title（支付宝通知 title 通常是商户名），或 text 里「给XX付款/支付给XX」
    String merchant = (raw['title'] ?? '').toString().trim();
    if (merchant.isEmpty || merchant == '支付宝' || merchant == '微信支付') {
      final m = RegExp(r'(?:支付|付款|转给|给|收款方)\s*([\u4e00-\u9fa5A-Za-z0-9·]{2,20})')
          .firstMatch(text);
      merchant = m?.group(1) ?? '';
    }
    if (merchant.isEmpty) merchant = isIncome ? '收款' : '支出';
    return ParsedNotification(
      id: raw['id']?.toString() ?? '',
      pkg: raw['pkg']?.toString() ?? '',
      title: raw['title']?.toString() ?? '',
      text: text.trim(),
      time: raw['time'] != null
          ? DateTime.fromMillisecondsSinceEpoch((raw['time'] as num).toInt())
          : DateTime.now(),
      amount: amount,
      isIncome: isIncome,
      merchant: merchant,
    );
  }

  // 排除规则引擎
  Future<bool> _excluded(ParsedNotification p) async {
    final ex = await excludes;
    final users = await userList;
    final ignore = await ignoreMerchants;
    // 商户忽略名单（弹窗「不再记」加入）
    if (ignore.contains(p.merchant)) return true;
    // 信用卡还款
    if (ex['repay'] == true &&
        (p.text.contains('还款') || p.text.contains('信用卡'))) {
      return true;
    }
    // 本人银行卡转账
    if (ex['selfTransfer'] == true &&
        (p.text.contains('转账') || p.text.contains('转入'))) {
      return true;
    }
    // 转给指定用户（支出）/ 指定用户转来（收入）
    if (users.isNotEmpty) {
      final hitUser = users.where((u) => p.text.contains(u)).isNotEmpty;
      if (hitUser) {
        if (p.isIncome && ex['fromUsers'] == true) return true;
        if (!p.isIncome && ex['toUsers'] == true) return true;
      }
    }
    return false;
  }

  // 弹窗「不再记」：把商户加入忽略名单
  Future<void> _addExcludeFromDialog(AutoRecordAction result) async {
    final list = await ignoreMerchants;
    if (result.merchant.isNotEmpty && !list.contains(result.merchant)) {
      list.add(result.merchant);
      await setIgnoreMerchants(list);
    }
  }

  // 落库
  Future<void> _saveFlow(WidgetRef ref, AutoRecordAction result) async {
    final body = <String, dynamic>{
      'type': result.isIncome ? 'income' : 'expense',
      'amount': result.amount,
      'category': result.category,
      'description': result.description,
      'flow_time':
          '${result.time.year}-${result.time.month.toString().padLeft(2, '0')}-${result.time.day.toString().padLeft(2, '0')}',
      'payment_method': _pkgName(result.pkg),
      'source': 'auto',
    };
    try {
      await ref.read(apiProvider).createFlow(body);
      toast('已记账：${result.description}');
    } catch (e) {
      toast(e.toString().replaceFirst('ApiException: ', ''));
    }
  }

  String _pkgName(String pkg) {
    switch (pkg) {
      case 'com.eg.android.AlipayGphone':
        return '支付宝';
      case 'com.tencent.mm':
        return '微信支付';
      case 'com.unionpay':
        return '云闪付';
      default:
        return '';
    }
  }
}

/// 解析后的通知记录
class ParsedNotification {
  final String id;
  final String pkg;
  final String title;
  final String text;
  final DateTime time;
  final double amount;
  final bool isIncome;
  final String merchant;
  ParsedNotification({
    required this.id,
    required this.pkg,
    required this.title,
    required this.text,
    required this.time,
    required this.amount,
    required this.isIncome,
    required this.merchant,
  });
}
