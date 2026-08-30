import 'dart:async';
import 'package:jizhang_android/core/theme.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jizhang_android/core/util.dart';
import 'package:jizhang_android/state/session.dart';
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
  Future<void> loadPersistedLogs() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_logSpKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = (jsonDecode(raw) as List).cast<String>();
        _logs.addAll(list.where((x) => x.isNotEmpty));
        if (_logs.length > 50) _logs.removeRange(0, _logs.length - 50);
      } catch (_) {}
    }
    _logsListenable.value = List.from(_logs);
  }

  void clearLogs() {
    _logs.clear();
    _logsListenable.value = List.from(_logs);
    SharedPreferences.getInstance().then((sp) => sp.setString(_logSpKey, '[]'));
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

  void recordLog(String msg) {
    final ts = DateTime.now().toString().substring(11, 19);
    final line = "[$ts] $msg";
    _logs.add(line);
    if (_logs.length > 50) _logs.removeAt(0);
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
  static const _channel = MethodChannel('jizhang/auto_record');
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

  static AutoRecordService? _instance;
  static AutoRecordService get instance =>
      _instance ??= AutoRecordService._();

  Timer? _timer;
  // 重入保护：弹窗已经在展示时，轮询/再次 processNow 直接跳过，
  // 避免 6 秒定时轮轮把同一批通知堆出多个弹窗（用户截图里"点了很多次忽略
  // 后弹窗后面都变浅/变深"就是这个原因）。
  bool _showing = false;

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
    final pending = await fetchPending();
    if (pending.isEmpty) return;
    _showing = true;
    try {
      // 聚合通知合并：支付宝同一笔支付常常连续 2-3 条 heads-up
      //（'服务通知' + '交易提醒/你有一笔 6.89 元的支出'），
      // 按 pkg + 10 秒桶分组，取 text 最长的（通常含金额那条）——避免
      // 0 元占位+有金额分别记两笔。
      final merged = <String, Map<String, dynamic>>{};
      for (final raw in pending) {
        final t = (raw['time'] as int?) ?? 0;
        final pkg = (raw['pkg'] as String?) ?? '';
        final bucket = t ~/ 10000; // 10 秒窗口
        final key = '$pkg|$bucket';
        final txt = (raw['text'] as String?) ?? '';
        if (merged.containsKey(key)) {
          if (txt.length > ((merged[key]!['text'] as String?) ?? '').length) {
            merged[key] = Map<String, dynamic>.from(raw);
          }
        } else {
          merged[key] = Map<String, dynamic>.from(raw);
        }
      }
      // 原始队列全部出队（合并后只处理 1 条）
      for (final raw in pending) {
        await removePending(raw['id']?.toString() ?? '');
      }
      // 处理合并后的
      for (final raw in merged.values) {
        final parsed = _parse(raw);
        if (parsed == null) continue;
        if (await _excluded(parsed)) continue;
        final dedupKey = '${parsed.merchant}|${parsed.amount.toStringAsFixed(2)}';
        if (await _dedupHit(dedupKey)) continue;
        await _dedupMark(dedupKey);
        await _saveParsedFlow(ref, parsed);
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
    // 虚拟积分/非现金类通知黑名单：即使含「到账/入账」也直接丢弃
    // （支付宝积分到账、京豆、里程、信用分、金币、成长值等不是真实收支）
    const virtualKw = [
      '积分', '金币', '京豆', '里程', '成长值', '信用分', '蚂蚁积分',
      '积分到账', '积分入账', '返积分', '送积分', '领积分', '兑换积分',
      '豆', '金币到账', '星星', '等级', '经验值', '会员积分',
    ];
    // 营销/聊天黑名单：命中这些词且没有强支付信号 → 丢弃（接龙/价目/优惠等）
    // 注意：不含「红包/领红包」——微信红包是真实收入（收到红包/领取红包），不能拦
    const marketingKw = [
      '优惠', '秒杀', '限时', '活动', '领券', '抵扣', '接龙', '价目',
      '团购', '热卖', '返利', '折扣', '会员日', '特惠', '立减', '满减',
      '优惠券', '代金券', '促销', '特价', '砍价', '拼团', '商品推荐',
    ];
    final hasStrong = strongKw.any((kw) => text.contains(kw));
    if (!hasStrong) {
      // 无强信号：直接丢弃（哪怕是支付 App——营销/聊天也会在支付 App 里出现）
      recordLog("AI解析跳过:无强信号 text=${text.substring(0, text.length < 80 ? text.length : 80)}");
      return null;
    }
    // 虚拟积分类通知（支付宝积分/京豆/里程等）直接丢弃，不当作记账
    if (virtualKw.any((kw) => text.contains(kw))) {
      recordLog("AI解析跳过:虚拟积分词匹配 text=${text.substring(0, text.length < 80 ? text.length : 80)}");
      return null;
    }
    if (marketingKw.any((kw) => text.contains(kw))) {
      // 有强信号但混了营销词：只有当强信号词非常明确（成功/到账/扣款）才继续，
      // 否则视为营销截图误抓
      final clearSignal = ['支付成功', '付款成功', '成功付款', '收款成功', '到账', '入账', '扣款成功']
          .any((kw) => text.contains(kw));
      if (!clearSignal) { recordLog('AI解析跳过:营销词+信号不明 text=${text.substring(0, text.length < 80 ? text.length : 80)}'); return null; }
    }

    // ---- ② 金额提取（优先级：实付/支付/付款金额 > 紧跟支付词的 ¥ > 首个 ¥） ----
    double? amount;
    final amtRe = RegExp(r'[¥￥]\s*([0-9]+(?:\.[0-9]{1,2})?)');
    final amtYuanRe = RegExp(r'([0-9]+(?:\.[0-9]{1,2})?)\s*元');
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
    // 3) 兜底：首个 ¥ 或 xx元
    if (amount == null) {
      final m = amtRe.firstMatch(text) ?? amtYuanRe.firstMatch(text);
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
    // 信用卡还款：同时含「还款」+「信用卡」或「还款」+「花呗」才忽略（AND）
    if (ex['repay'] == true) {
      final hasRepay = p.text.contains('还款');
      final hasCard = p.text.contains('信用卡');
      final hasHuabei = p.text.contains('花呗');
      if (hasRepay && (hasCard || hasHuabei)) {
        skipReason = '信用卡还款规则';
        recordLog('跳过记账:${p.merchant} | ${skipReason}');
        return true;
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


// 工具：HH:mm 格式（待录入占位流水 name 用）
String _hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, "0")}:${t.minute.toString().padLeft(2, "0")}';
