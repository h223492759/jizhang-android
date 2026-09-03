import 'dart:async';
import 'package:jizhang_android/core/theme.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jizhang_android/core/util.dart';
import 'package:jizhang_android/state/session.dart';
import 'package:path_provider/path_provider.dart';
import 'package:jizhang_android/core/local_first_api.dart';
import 'package:jizhang_android/screens/record/auto_record_dialog.dart';

/// 自动记账服务：从原生通知监听队列拉取待处理记录，
/// 解析金额/方向/商户 → 排除规则 → 去重 → 直接自动记账（source=auto，带 AI 标识）。
/// 误记时在流水详情页点「不再记」删除并加入忽略名单。
class AutoRecordService {
  // 运行日志（最近 50 条，可一键复制给开发者）
  final List<String> _logs = [];
  final ValueNotifier<List<String>> _logsListenable = ValueNotifier([]);
  static const _logSpKey = 'auto_record_logs';
  ValueNotifier<List<String>> get logsListenable => _logsListenable;
  List<String> getLogs() => List.unmodifiable(_logs);

  /// 启动时把持久化的日志（含 native 弹窗记录）载入内存显示
  /// - 进入时先清空 _logs（修复 issue：之前不清空就 addAll，
  ///   导致多次进入 settings 页时把同一批 SP+native 日志叠加、UI 看似 50 条
  ///   但里面有大量重复行）
  /// - 合并去重后按 [yyyy-MM-dd HH:mm:ss] 时间戳统一【降序】存储（最新 index0），
  ///   UI 顺序渲染即最新在上、复制按钮输出同序（v1.5.5 起不再依赖 reverse 技巧）
  Future<void> loadPersistedLogs() async {
    // 1) Flutter 端 SharedPreferences 日志
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_logSpKey);
    final loaded = <String>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        loaded.addAll((jsonDecode(raw) as List).cast<String>().where((x) => x.isNotEmpty));
      } catch (_) {}
    }
    // 2) native 端弹窗日志（写在 app 私有 files/native_logs.json，跨沙箱不共享 sp）
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/native_logs.json');
      if (file.existsSync()) {
        loaded.addAll((jsonDecode(file.readAsStringSync()) as List).cast<String>().where((x) => x.isNotEmpty));
      }
    } catch (_) {}
    // 去重（按行精确匹配，避免 sp/file 重复行）
    final unique = <String>[];
    final seen = <String>{};
    for (final l in loaded) {
      if (seen.add(l)) unique.add(l);
    }
    // 按 [YYYY-MM-DD HH:mm:ss] 时间戳【降序】排序：最新在最前（UI 顺序渲染即最新在上）。
    // ⚠️ v1.5.5 修复：旧实现 group(1).replaceAll(':','') 后仍是 "2026-09-02 153705"
    // （残留 '-' 与空格）→ int.tryParse 全部 null → 全落到 -1 → sort 完全失效，
    // 日志永远按「SP 组 + native 组」两块拼接显示（用户看到的"按类型分组"乱序）。
    unique.sort(_logCmpDesc);
    if (unique.length > 50) unique.removeRange(50, unique.length);
    _logs
      ..clear()
      ..addAll(unique);
    _logsListenable.value = List.from(_logs);
  }

  void clearLogs() {
    _logs.clear();
    _logsListenable.value = List.from(_logs);
    SharedPreferences.getInstance().then((sp) => sp.setString(_logSpKey, '[]'));
    // 同时清 native 弹窗日志文件
    getApplicationSupportDirectory().then((dir) {
      final f = File('${dir.path}/native_logs.json');
      if (f.existsSync()) f.writeAsStringSync('[]');
    }).catchError((_) {});
  }

  // 监听 native 端弹窗日志推送（native 用 _channel.invokeMethod 调）
  void _initMethodHandler() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'nativeLog' && call.arguments is String) {
        recordLog(call.arguments as String);
      }
      return null;
    });
  }

  // v1.5.5：日志行时间 key 与降序比较器（最新在前）。双端日志前缀统一为
  // "[yyyy-MM-dd HH:mm:ss]"；直接字符串比较（ISO 字典序==时间序），修复旧实现
  // replaceAll(':') 残留 '-'/空格 → int.tryParse 全 null → sort 失效的分组乱序。
  static String? _logTs(String line) =>
      RegExp(r'^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\]').firstMatch(line)?.group(1);

  static int _logCmpDesc(String a, String b) {
    final ka = _logTs(a);
    final kb = _logTs(b);
    if (ka == null && kb == null) return 0;
    if (ka == null) return 1; // 无时间戳排最后
    if (kb == null) return -1;
    return kb.compareTo(ka);
  }

  void recordLog(String msg) {
    // v1.5.4 加日期前缀：跨天不会因 HH:mm:ss 撞车而乱序；与 native 端 SimpleDateFormat
    // ("yyyy-MM-dd HH:mm:ss") 保持一致（双端统一，loadPersistedLogs 排序正则一并改）
    final ts = DateTime.now().toString().substring(0, 19);
    final line = "[$ts] $msg";
    // v1.5.5：运行期追加也保持降序时间线（add 后整体重排，≤50 条开销可忽略），
    // 否则 UI 显示的日志会混入未排序的实时行
    _logs.add(line);
    _logs.sort(_logCmpDesc);
    if (_logs.length > 50) _logs.removeRange(50, _logs.length);
    _logsListenable.value = List.from(_logs);
    // 持久化（native 弹窗记录也写同一个 key，重启不清空）
    SharedPreferences.getInstance().then((sp) async {
      var raw = sp.getString(_logSpKey) ?? '[]';
      List<String> list;
      try {
        list = (jsonDecode(raw) as List).cast<String>();
      } catch (_) {
        list = [];
      }
      list.add(line);
      if (list.length > 50) list.removeAt(0);
      await sp.setString(_logSpKey, jsonEncode(list));
    });
  }
  static const _kChannel = 'jizhang/auto_record';
  // v1.5.4 修复：与 native 端通信的 MethodChannel 实例（native MainActivity.kt
  // 以同名 "jizhang/auto_record" 注册 handler；重构时误删字段只剩常量导致 CI
  // analyze 报 Undefined name '_channel'）。初始化必须先于 _initMethodHandler() 使用。
  static const MethodChannel _channel = MethodChannel(_kChannel);
  static const _kEnabled = 'auto_record_enabled';
  static const _kExcludeRepay = 'auto_exclude_repay';
  static const _kExcludeSelfTransfer = 'auto_exclude_self_transfer';
  static const _kExcludeToUsers = 'auto_exclude_to_users';
  static const _kExcludeFromUsers = 'auto_exclude_from_users';
  static const _kUserList = 'auto_user_list';
  static const _kAndGroups = 'auto_exclude_and_groups';
  static const _kOrKeywords = 'auto_exclude_or_keywords';
  static const _kIgnoreMerchants = 'auto_ignore_merchants';
  static const _kDedupSeen = 'auto_dedup_seen';
  static const _kSystemKw = 'auto_system_keywords'; // v1.5.4 系统跳过词（分组可编辑）
  static const _kSystemRepayGroups = 'auto_system_repay_groups'; // v1.5.4 信用卡还款 AND 规则

  static AutoRecordService? _instance;
  static AutoRecordService get instance =>
      _instance ??= AutoRecordService._();

  Timer? _timer;
  // 重入保护：弹窗已经在展示时，轮询/再次 processNow 直接跳过，
  // 避免 6 秒定时轮轮把同一批通知堆出多个弹窗（用户截图里"点了很多次忽略
  // 后弹窗后面都变浅/变深"就是这个原因）。
  bool _showing = false;
  // v1.5.4：缓存系统跳过词（每次 _processQueue 开头预取，供 _parse 同步使用）
  Map<String, List<String>>? _cachedSystemKw;
  List<List<String>>? _cachedRepayGroups;

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

  // 自定义「同时出现才屏蔽」规则：每组 = 多个关键词，全部同时出现才忽略
  Future<List<List<String>>> get andGroups async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_kAndGroups);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List).map((g) => (g as List).cast<String>()).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> setAndGroups(List<List<String>> groups) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kAndGroups, jsonEncode(groups));
  }

  // 自定义「单词出现就屏蔽」：任一关键词出现即忽略
  Future<List<String>> get orKeywords async {
    final sp = await SharedPreferences.getInstance();
    return sp.getStringList(_kOrKeywords) ?? [];
  }

  Future<void> setOrKeywords(List<String> kws) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList(_kOrKeywords, kws);
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

  // ============== v1.5.4 系统跳过词（分组可编辑：设置页能删/恢复默认） ==============
  // 虚拟积分类通知黑名单（v1.5.3 收紧后的精确词组；用户可在设置页删除某条）
  static const _defaultVirtualKw = [
    '金币', '京豆', '里程', '成长值', '信用分', '蚂蚁积分',
    '积分到账', '积分入账', '积分商城', '兑换积分',
    '返积分', '送积分', '领积分', '已领积分', '积分兑换',
    '金币到账', '获得金币', '领取金币', '兑换金币', '送金币',
    '京豆到账', '送京豆', '领取京豆', '送里程', '返金币',
    '星星', '等级', '经验值', '会员积分', '待领取积分',
  ];
  // 营销/聊天黑名单（v1.5.3；用户可编辑）
  static const _defaultMarketingKw = [
    '优惠', '秒杀', '限时', '活动', '领券', '抵扣', '接龙', '价目',
    '团购', '热卖', '返利', '折扣', '会员日', '特惠', '立减', '满减',
    '优惠券', '代金券', '促销', '特价', '砍价', '拼团', '商品推荐',
  ];
  // 信用卡还款 AND 规则（v1.5.4 改成"两组 AND 规则"可编辑）
  // 默认：含"还款"+"信用卡" → 屏蔽；含"还款"+"花呗" → 屏蔽
  // 0.65 漏记复测：删掉"花呗"那条 AND 规则后，"花呗+还款"通知不再被拦
  static const _defaultRepayGroups = [
    ['还款', '信用卡'],
    ['还款', '花呗'],
  ];

  /// 返回系统跳过词分组（供设置页编辑/展示）
  Future<Map<String, List<String>>> get systemKeywords async {
    final sp = await SharedPreferences.getInstance();
    var raw = sp.getString(_kSystemKw);
    Map<String, dynamic> parsed;
    if (raw == null || raw.isEmpty) {
      // 首次：写入默认值（v1.5.4 默认值就是收紧后的词表）
      parsed = {
        '虚拟积分': List<String>.from(_defaultVirtualKw),
        '营销聊天': List<String>.from(_defaultMarketingKw),
      };
      await sp.setString(_kSystemKw, jsonEncode(parsed));
    } else {
      try {
        parsed = (jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        parsed = {};
      }
    }
    // 兼容旧数据：确保三个默认分组都存在
    final out = <String, List<String>>{};
    for (final k in ['虚拟积分', '营销聊天']) {
      final v = parsed[k];
      out[k] = v is List ? v.cast<String>().toList() : [];
    }
    return out;
  }

  Future<void> setSystemKeywords(Map<String, List<String>> v) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kSystemKw, jsonEncode(v));
  }

  /// 信用卡还款 AND 规则组（每组 = 全部同时出现才屏蔽）
  Future<List<List<String>>> get systemRepayGroups async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_kSystemRepayGroups);
    if (raw == null || raw.isEmpty) {
      // 首次：写入默认值
      final groups = _defaultRepayGroups.map((g) => List<String>.from(g)).toList();
      await sp.setString(_kSystemRepayGroups, jsonEncode(groups));
      return groups;
    }
    try {
      return (jsonDecode(raw) as List).map((g) => (g as List).cast<String>()).toList();
    } catch (_) {
      return _defaultRepayGroups.map((g) => List<String>.from(g)).toList();
    }
  }

  Future<void> setSystemRepayGroups(List<List<String>> groups) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kSystemRepayGroups, jsonEncode(groups));
  }

  /// 一键恢复所有系统跳过词为默认值（虚拟积分 / 营销聊天 / 信用卡还款 AND 组）
  Future<void> resetSystemKeywords() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kSystemKw, jsonEncode({
      '虚拟积分': List<String>.from(_defaultVirtualKw),
      '营销聊天': List<String>.from(_defaultMarketingKw),
    }));
    await sp.setString(_kSystemRepayGroups,
        jsonEncode(_defaultRepayGroups.map((g) => List<String>.from(g)).toList()));
  }

  // ---------------- 去重指纹（持久化） ----------------
  Future<bool> _dedupHit(String key) async {
    final sp = await SharedPreferences.getInstance();
    final map = sp.getString(_kDedupSeen) ?? '';
    if (map.isEmpty) return false;
    try {
      final seen = jsonDecode(map) as Map<String, dynamic>;
      final now = DateTime.now().millisecondsSinceEpoch;
      // v1.5.5：命中窗口从"1 天内存在即吞"收紧为"3 分钟内同 key 才算重复"。
      // dedup 本意是拦同一笔通知被 native 多包名/重复推送的瞬间重复；旧逻辑下
      // 一天内同额同商户（如两笔早餐 12.00）或同「平台名|0.00」的第二笔起会被
      // 静默吞掉 → 正是"有弹窗没记账/莫名少记"的元凶之一。
      final hit = seen[key] != null &&
          now - (seen[key] as num).toInt() <
              const Duration(minutes: 3).inMilliseconds;
      // 清理超过 1 天的指纹，防止无限膨胀
      seen.removeWhere((k, v) => now - (v as num).toInt() >
          const Duration(days: 1).inMilliseconds);
      await sp.setString(_kDedupSeen, jsonEncode(seen));
      return hit;
    } catch (_) {
      return false;
    }
  }

  // native id 去重：防同一条通知被 native 重复入队（合并支付的多笔不合并）
  static const _kIdSeen = 'auto_record_id_seen';
  Future<bool> _idDedupHit(String id) async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_kIdSeen);
    if (raw == null) return false;
    try { return ((jsonDecode(raw) as List).cast<String>()).contains(id); } catch (_) { return false; }
  }
  Future<void> _idDedupMark(String id) async {
    final sp = await SharedPreferences.getInstance();
    var list = (jsonDecode(sp.getString(_kIdSeen) ?? '[]') as List).cast<String>();
    list.add(id);
    if (list.length > 200) list.removeRange(0, list.length - 200);
    await sp.setString(_kIdSeen, jsonEncode(list));
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

  // ---------------- v1.5.6：0 元占位配对 ----------------
  // 同一次支付（碰一碰/扫码/快捷支付）常触发两条通知：有金额的「交易提醒/支付凭证」+
  // 无金额的「服务通知/付款成功」（金额画在卡片图里，通知文本没有）。
  // 若 5 秒内（用户观察弹窗间隔基本 3 秒内，留余量）同支付方式已有金额>0 的记录，
  // 无金额那条就不入账（否则一次支付记两笔：0 元占位 + 真实金额 → 账本出现 -0 脏行）。
  // 找不到配对才走 B 方案：0 元照记待录入（保底防漏，v1.5.5 已让 0 元不参与同额去重）。
  static const int _zeroPairWindowMs = 5000;
  // 最近成功记账的有金额记录（payName/notifTime/amount/ts），供跨批配对判断
  final List<Map<String, dynamic>> _recentlyRecorded = [];

  /// 轻量判断文本中是否含金额表述（与 _parse 金额提取正则族一致，无日志副作用）
  bool _textHasAmount(String text) {
    if (RegExp(r'[¥￥]\s*[0-9]+(?:\.[0-9]{1,2})?').hasMatch(text)) return true;
    if (RegExp(r'[0-9]+(?:\.[0-9]{1,2})?\s*(?:元|人民币)').hasMatch(text)) return true;
    if (RegExp(r'(?:人民币|RMB)\s*[0-9]+(?:\.[0-9]{1,2})?').hasMatch(text)) return true;
    return false;
  }

  /// v1.5.6：0 元占位是否应被「同批未处理 or 最近已记账」的有金额通知配对吞掉
  Future<bool> _zeroPaired(Map<String, dynamic> raw,
      List<Map<String, dynamic>> pending, Set<String> handledRids) async {
    final rid = raw['id']?.toString() ?? '';
    final payName = _pkgName(raw['pkg']?.toString() ?? '');
    final t = (raw['time'] as num?)?.toInt() ?? 0;
    // 1) 同批 pending 中未处理的其他通知：同支付方式、含金额文字、通知时间差 ≤5s
    for (final o in pending) {
      final oid = o['id']?.toString() ?? '';
      if (oid == rid || handledRids.contains(oid)) continue;
      if (_pkgName(o['pkg']?.toString() ?? '') != payName) continue;
      final ot = (o['time'] as num?)?.toInt() ?? 0;
      if (t != 0 && ot != 0 && (ot - t).abs() > _zeroPairWindowMs) continue;
      final otext = '${o['title'] ?? ''} ${o['text'] ?? ''}';
      if (_textHasAmount(otext)) return true;
    }
    // 2) 最近刚记账的有金额通知（上一轮已处理、已从 pending 移除的跨批场景）
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final r in _recentlyRecorded) {
      if (r['payName'] != payName) continue;
      if (now - (r['ts'] as int) > 60 * 1000) continue; // 只认 1 分钟内，防误配老通知
      final nt = r['notifTime'] as int;
      if (nt != 0 && t != 0 && (nt - t).abs() <= _zeroPairWindowMs &&
          (r['amount'] as num).toDouble() > 0) {
        return true;
      }
    }
    return false;
  }

  /// v1.5.6：登记一笔刚记账的有金额记录（供后续 0 元占位配对）
  void _recordRecently(Map<String, dynamic> raw, ParsedNotification p) {
    if (p.amount <= 0) return; // 只认有金额的
    _recentlyRecorded.add({
      'payName': _pkgName(p.pkg),
      'notifTime': (raw['time'] as num?)?.toInt() ?? 0,
      'amount': p.amount,
      'ts': DateTime.now().millisecondsSinceEpoch,
    });
    if (_recentlyRecorded.length > 20) {
      _recentlyRecorded.removeRange(0, _recentlyRecorded.length - 20);
    }
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
    _initMethodHandler(); // 兜底：startPolling 之前也能监听 native 日志
    try {
      await _processQueue(ref, context);
    } catch (_) {}
  }

  // ---------------- 主流程 ----------------
  // 自动记账模式：识别到支付通知 → 直接落库（source=auto → 流水带 AI 标识），
  // 不再弹确认框；误记在流水详情页点「不再记」删除并加入忽略名单。
  Future<void> _processQueue(WidgetRef ref, BuildContext context) async {
    if (_showing) return; // 重入保护（快速轮询/并发触发）
    if (!(await enabled)) return;
    final s = ref.read(sessionProvider);
    if (!s.hasToken || !s.hasBook) return;
    // v1.5.4：预取系统跳过词缓存（_parse 同步使用，避免每次都读 SP）
    _cachedSystemKw = await systemKeywords;
    _cachedRepayGroups = await systemRepayGroups;
    final pending = await fetchPending();
    if (pending.isEmpty) return;
    _showing = true;
    try {
      // 逐条处理（不再按 10 秒桶合并）：
      // - native 同 id 的同一条通知会被 _idDedupHit 跳过（防 native 重复入队），
      //   这能解决 v1.4.58 之前的'0 元占位+有金额分别记两笔'问题
      // - 不同 id（合并支付多笔）保留 → 多笔就记多笔（v1.5.2 行为）
      final handledRids = <String>{};
      for (final raw in pending) {
        final rid = raw['id']?.toString() ?? '';
        if (rid.isEmpty) {
          await removePending(rid);
          continue;
        }
        if (await _idDedupHit(rid)) {
          // v1.5.5：去重也留痕，避免"弹窗了却没记账"无从排查
          recordLog('去重跳过:同一条通知已被处理过');
          handledRids.add(rid);
          await removePending(rid);
          continue;
        }
        final parsed = _parse(raw);
        if (parsed == null) {
          handledRids.add(rid);
          await removePending(rid);
          continue;
        }
        if (await _excluded(parsed)) {
          handledRids.add(rid);
          await removePending(rid);
          continue;
        }
        // v1.5.6：0 元占位配对吞掉——同支付方式 5 秒内出现「有金额通知」
        // （如支付宝：交易提醒 ¥16.92 + 服务通知(无金额) 同时到达），说明是同一次
        // 支付的两条通知，只记有金额那条，避免账本出现 -0 脏行。
        // 找不到配对才继续走 B 方案：0 元照记「待录入」保底（防漏）。
        if (parsed.amount == 0 && await _zeroPaired(raw, pending, handledRids)) {
          recordLog('配对吞掉:0元占位同支付方式5s内有金额通知（不记重复占位）');
          await _idDedupMark(rid); // 吞掉的也打 id 指纹，防 native 重复入队再来
          handledRids.add(rid);
          await removePending(rid);
          continue;
        }
        // v1.5.5：0 元占位（通知没解析到金额）【不参与】同额去重——
        // 不同时间的两笔无金额消费若都解析成「平台名|0.00」，第二笔起会被
        // 静默吞掉（无日志、无流水），正是"碰一碰/服务通知有弹窗但没记账"的
        // 主要嫌疑路径。仍保留同通知 id 去重防 native 重复入队。
        final dedupKey = '${parsed.merchant}|${parsed.amount.toStringAsFixed(2)}';
        if (parsed.amount != 0) {
          if (await _dedupHit(dedupKey)) {
            // v1.5.5：同额去重命中也要留痕
            recordLog('去重跳过:同额已记账 ${dedupKey}');
            handledRids.add(rid);
            await removePending(rid);
            continue;
          }
          await _dedupMark(dedupKey);
        }
        await _idDedupMark(rid);
        await _saveParsedFlow(ref, parsed);
        _recordRecently(raw, parsed); // v1.5.6：供后续 0 元占位配对
        handledRids.add(rid);
        await removePending(rid);
      }
    } catch (_) {
    } finally {
      _showing = false;
    }
  }

  /// 解析后的通知直接落库（自动记账）
  Future<void> _saveParsedFlow(WidgetRef ref, ParsedNotification p) async {
    // AI 自动记账统一 name 规则：支付方式hh:mm关键词（如「支付宝12:07交易提醒」）
    // 0 元占位额外加「待录入」
    final pay = _pkgName(p.pkg);
    final kw = p.merchant;
    final hhmm = _hhmm(p.time);
    final base = pay == kw ? '$pay$hhmm' : '$pay$hhmm$kw';
    final desc = p.amount == 0 ? '${base}待录入' : base;
    final body = <String, dynamic>{
      'type': p.isIncome ? 'income' : 'expense',
      'amount': p.amount,
      'category': _autoCategory('', p.isIncome),
      'description': desc,
      'flow_time':
          '${p.time.year}-${p.time.month.toString().padLeft(2, '0')}-${p.time.day.toString().padLeft(2, '0')}',
      'payment_method': _pkgName(p.pkg),
      'source': 'auto',
    };
    try {
      // 走 localApiProvider：断网时本地入队 + enqueue outbox，连上后自动重试
      // （与手动记账行为一致：断网也能写本地）
      await ref.read(localApiProvider).createFlow(body);
      ref.read(dataVersionProvider.notifier).state++;
      recordLog("已记账：${p.merchant} ¥${p.amount.toStringAsFixed(2)} ");
      toast('已记账：${p.merchant} ¥${p.amount.toStringAsFixed(2)}');
    } catch (e) {
      // 真正的非网络错（如参数错）才提示失败
      recordLog('记账失败：${e.toString().replaceFirst("ApiException: ", "")}');
      toast('记账失败：${e.toString().replaceFirst("ApiException: ", "")}');
    }
  }

  /// 商户 → 忽略名单（流水详情页「不再记」调用）
  Future<void> addIgnoreMerchant(String merchant) async {
    final list = await ignoreMerchants;
    if (merchant.isNotEmpty && !list.contains(merchant)) {
      list.add(merchant);
      await setIgnoreMerchants(list);
    }
  }

  /// 自动记账默认分类（通知解析未显式给出分类时）
  String _autoCategory(String category, bool isIncome) {
    if (category.isNotEmpty && category != '其他' && category != '其它') {
      return category;
    }
    // 无分类信息的支出通知保底用「餐饮」不符合直觉；改为「其他」（用户可在详情改）
    return isIncome ? '其他' : '其他';
  }

  // 解析通知文本 → 结构化记录
  // v1.5.4：virtualKw/marketingKw 改为从 SP 读取（设置页可编辑/恢复默认）；
  // hardcoded 常量保留 _defaultVirtualKw/_defaultMarketingKw 仅作首启动默认值
  ParsedNotification? _parse(Map<String, dynamic> raw) {
    final text = '${raw['title'] ?? ''} ${raw['text'] ?? ''}';
    if (text.trim().isEmpty) { recordLog('AI解析跳过:text为空'); return null; }

    // ---- ① 误识别过滤：强信号词（完成时态） ----
    // 含微信/支付宝转账：转账成功/已存入零钱/收到转账
    const strongKw = [
      '支付成功', '付款成功', '成功付款', '支付成功通知', '已支付', '已付款',
      '收款成功', '已收款', '收款通知', '收款到账', '收款',
      '转账成功', '转账', '已存入', '收到转账', '转入',
      '扣款成功', '已扣款', '已消费', '消费', '扣款', '交易提醒',
      '入账', '到账', '还款成功', '已还款', '退款成功', '已退款',
    ];
    // virtualKw/marketingKw 从 SP 异步读取（v1.5.4：设置页可编辑/恢复默认），
    // 这里同步读取需要预加载——放在 _processQueue 调用 _parse 前预取并缓存
    final virtualKw = _cachedSystemKw?['虚拟积分'] ?? const <String>[];
    final marketingKw = _cachedSystemKw?['营销聊天'] ?? const <String>[];
    final hasStrong = strongKw.any((kw) => text.contains(kw));
    if (!hasStrong) {
      recordLog("AI解析跳过:无强信号 text=${text.substring(0, text.length < 80 ? text.length : 80)}");
      return null;
    }
    // 虚拟积分类通知直接丢弃，不当作记账（v1.5.4 从 SP 取）
    if (virtualKw.isNotEmpty && virtualKw.any((kw) => text.contains(kw))) {
      recordLog("AI解析跳过:虚拟积分词匹配 text=${text.substring(0, text.length < 80 ? text.length : 80)}");
      return null;
    }
    if (marketingKw.isNotEmpty && marketingKw.any((kw) => text.contains(kw))) {
      // 有强信号但混了营销词：只有当强信号词非常明确（成功/到账/扣款）才继续，
      // 否则视为营销截图误抓
      const clearSignal = ['支付成功', '付款成功', '成功付款', '收款成功', '到账', '入账', '扣款成功'];
      if (!clearSignal.any((kw) => text.contains(kw))) {
        recordLog('AI解析跳过:营销词+信号不明 text=${text.substring(0, text.length < 80 ? text.length : 80)}');
        return null;
      }
    }

    // ---- ② 金额提取（优先级：实付/支付/付款金额 > 紧跟支付词的 ¥ > 首个 ¥） ----
    double? amount;
    final amtRe = RegExp(r'[¥￥]\s*([0-9]+(?:\.[0-9]{1,2})?)');
    // v1.5.5：补充「29.30 人民币」「人民币29.30」等无 ¥、无"元"的银行/碰一碰文案
    final amtYuanRe = RegExp(r'([0-9]+(?:\.[0-9]{1,2})?)\s*(?:元|人民币)');
    final amtRmbPreRe = RegExp(r'(?:人民币|RMB)\s*([0-9]+(?:\.[0-9]{1,2})?)');
    final paidRe = RegExp(
        r'(?:实付|实际支付|支付金额|付款金额|实付金额|支付成功[^¥￥]{0,8})(?:[¥￥]\s*)?([0-9]+(?:\.[0-9]{1,2})?)');
    // 1) 实付/支付金额 上下文
    final paidM = paidRe.firstMatch(text);
    if (paidM != null) {
      final v = double.tryParse(paidM.group(1) ?? '');
      if (v != null && v > 0) amount = v;
    }
    // 2) "¥xx" 且前文紧跟支付/付款/成功
    if (amount == null) {
      final m = RegExp(r'(?:支付|付款|成功|实付)[^¥￥\n]{0,10}[¥￥]\s*([0-9]+(?:\.[0-9]{1,2})?)')
          .firstMatch(text);
      if (m != null) {
        final v = double.tryParse(m.group(1) ?? '');
        if (v != null && v > 0) amount = v;
      }
    }
    // 3) 兜底：首个 ¥ 或 xx元 / xx人民币 / 人民币xx
    if (amount == null) {
      final m = amtRe.firstMatch(text) ??
          amtYuanRe.firstMatch(text) ??
          amtRmbPreRe.firstMatch(text);
      if (m != null) {
        final v = double.tryParse(m.group(1) ?? '');
        if (v != null && v > 0) amount = v;
      }
    }
    // 4) 强信号下识别裸数字（X.XX 两位小数）：支付宝'转账红包'类通知故意不显示金额文字，
    // 但通知原文如'给你转了1笔钱'可能不含数字，改为识别'0.27'这种'纯小数'形式。
    // 仅在 hasStrong（强信号词）下启用，避免误识别其他场景的数字（如 1.50 版本号）。
    if (amount == null && hasStrong) {
      final m = RegExp(r'(?:^|[^\d.])([0-9]+\.[0-9]{2})(?=[^\d.]|$)').firstMatch(text);
      if (m != null) {
        final v = double.tryParse(m.group(1) ?? '');
        if (v != null && v > 0 && v <= 100000) amount = v;
      }
    }
    // amount 解析失败但命中强信号 → 生成 0 元待录入占位流水（user 后续补金额）
    // amount 解析成功 → 常规记录
    if (amount == null) {
      if (!hasStrong) return null;  // 无强信号直接丢
      amount = 0;  // 占位：让 user 后续在流水列表补金额
    }
    // 金额合理性区间（0.01 ~ 10万），防异常识别。占位 0 跳过此检查
    if (amount != 0 && (amount <= 0 || amount > 100000)) return null;

    // ---- ③ 方向 ----
    final isIncome =
        text.contains('收入') || text.contains('收款') || text.contains('入账') ||
        text.contains('到账') || text.contains('已收款');

    // ---- ④ 商户提取（升级版） ----
    // 平台词：出现即视为"未识别到商户"，需要从 text 里找
    const platformWords = ['微信支付', '支付宝', '微信', '零钱', '云闪付', '银行卡', '银联'];
    String merchant = (raw['title'] ?? '').toString().trim();
    if (merchant.isEmpty ||
        platformWords.any((w) => merchant == w || merchant.contains(w))) {
      // 优先级：收款方：XX / 商户：XX / 向XX付款 / XX收款 / 支付给XX / 付款给XX / 给XX付款
      final patterns = [
        RegExp(r'(?:收款方|商户|商家|交易对象|收款单位)\s*[:：]\s*([\u4e00-\u9fa5A-Za-z0-9·]{2,20})'),
        RegExp(r'(?:向|给|转给)\s*([\u4e00-\u9fa5A-Za-z0-9·]{2,12})\s*(?:付款|支付|转账)'),
        RegExp(r'(?:支付|付款)(?:给)?\s*([\u4e00-\u9fa5A-Za-z0-9·]{2,12})\s*(?:的)?(?:收款|账单)'),
        RegExp(r'([\u4e00-\u9fa5A-Za-z0-9·]{2,12})\s*(?:收款|到账|入账)'),
      ];
      for (final re in patterns) {
        final m = re.firstMatch(text);
        if (m != null) {
          final cand = m.group(1) ?? '';
          // 过滤掉平台词/金额残留
          if (cand.isNotEmpty &&
              !platformWords.any((w) => cand == w || cand.contains(w))) {
            merchant = cand;
            break;
          }
        }
      }
      if (merchant.isEmpty || platformWords.any((w) => merchant == w)) {
        // 保底：优先用平台名（微信支付/支付宝/云闪付），比笼统的「支出/收款」更有意义
        final pkgName = _pkgName(raw['pkg']?.toString() ?? '');
        merchant = pkgName.isNotEmpty
            ? pkgName
            : (isIncome ? '收款' : '支出');
      }
    }
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
    final andGroups = await this.andGroups;
    final orKws = await orKeywords;
    String? skipReason; // 记录为什么被忽略（用户调试用）
    // 商户忽略名单（弹窗「不再记」加入）
    if (ignore.contains(p.merchant)) {
      skipReason = '商户忽略名单:${p.merchant}';
      recordLog('跳过记账:${p.merchant} | ${skipReason}');
      return true;
    }
    // 信用卡还款：每组 AND 规则全部命中 → 屏蔽（v1.5.4：缓存的 systemRepayGroups 可编辑）
    if (ex['repay'] == true) {
      final groups = _cachedRepayGroups ?? (await systemRepayGroups);
      for (final group in groups) {
        if (group.isNotEmpty && group.every((k) => p.text.contains(k))) {
          skipReason = '信用卡还款规则:${group.join("+")}';
          recordLog('跳过记账:${p.merchant} | ${skipReason}');
          return true;
        }
      }
    }
    // 自定义「同时出现才屏蔽」：每组全部关键词同时出现 → 忽略
    for (final group in andGroups) {
      if (group.isNotEmpty && group.every((k) => p.text.contains(k))) {
        skipReason = '同时出现组:${group.join("+")}';
        recordLog('跳过记账:${p.merchant} | ${skipReason}');
        return true;
      }
    }
    // 自定义「单词出现就屏蔽」：任一关键词出现 → 忽略
    for (final kw in orKws) {
      if (kw.isNotEmpty && p.text.contains(kw)) {
        skipReason = '单词屏蔽:${kw}';
        recordLog('跳过记账:${p.merchant} | ${skipReason}');
        return true;
      }
    }
    // 转给指定用户（支出）/ 指定用户转来（收入）
    if (users.isNotEmpty) {
      final hitUser = users.where((u) => p.text.contains(u)).isNotEmpty;
      if (hitUser) {
        if (p.isIncome && ex['fromUsers'] == true) {
          skipReason = '指定用户转来:${users.join(",")}';
          recordLog('跳过记账:${p.merchant} | ${skipReason}');
          return true;
        }
        if (!p.isIncome && ex['toUsers'] == true) {
          skipReason = '转给指定用户:${users.join(",")}';
          recordLog('跳过记账:${p.merchant} | ${skipReason}');
          return true;
        }
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
      case 'com.tencent.wepay':
        return '微信支付';
      case 'com.unionpay':
        return '云闪付';
      case 'com.cmbchina.cc':
      case 'com.cmbchina.biz':
      case 'com.cmbchina.mobilebank':
        return '招行信用卡';
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


// 工具：HH:mm 格式（待录入占位流水 name 用）
String _hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, "0")}:${t.minute.toString().padLeft(2, "0")}';
