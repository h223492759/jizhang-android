import 'dart:convert';

class User {
  final int id;
  final String username;
  final String nickname;
  final String role;
  final String? color;
  User({
    required this.id,
    required this.username,
    required this.nickname,
    required this.role,
    this.color,
  });
  factory User.fromJson(Map<String, dynamic> j) => User(
        id: j['id'],
        username: j['username'] ?? '',
        nickname: j['nickname'] ?? j['username'] ?? '',
        role: j['role'] ?? 'user',
        color: j['color'],
      );
  Map<String, dynamic> toJson() =>
      {'id': id, 'username': username, 'nickname': nickname, 'role': role, 'color': color};
  String toJsonString() => jsonEncode(toJson());
  factory User.fromJsonString(String s) => User.fromJson(jsonDecode(s));
}

class Book {
  final int id;
  final String name;
  final int ownerId;
  final String role;
  final int members;
  final int flows;
  Book({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.role,
    required this.members,
    required this.flows,
  });
  factory Book.fromJson(Map<String, dynamic> j) => Book(
        id: j['id'],
        name: j['name'] ?? '',
        ownerId: j['owner_id'] ?? 0,
        role: j['role'] ?? 'editor',
        members: j['members'] ?? 0,
        flows: j['flows'] ?? 0,
      );
  static List<Book> listFrom(dynamic v) =>
      (v as List? ?? []).map((e) => Book.fromJson(e)).toList();
  String toJsonString() => jsonEncode({
        'id': id,
        'name': name,
        'owner_id': ownerId,
        'role': role,
        'members': members,
        'flows': flows,
      });
  factory Book.fromJsonString(String s) => Book.fromJson(jsonDecode(s));
}

class Category {
  final int id;
  final int bookId;
  final String name;
  final String type; // expense | income
  final String icon;
  final String color;
  final int sort;
  Category({
    required this.id,
    required this.bookId,
    required this.name,
    required this.type,
    required this.icon,
    required this.color,
    required this.sort,
  });
  factory Category.fromJson(Map<String, dynamic> j) => Category(
        id: j['id'],
        bookId: j['book_id'] ?? 0,
        name: j['name'] ?? '',
        type: j['type'] ?? 'expense',
        icon: j['icon'] ?? '💰',
        color: j['color'] ?? '#7c8cff',
        sort: j['sort'] ?? 0,
      );
  static List<Category> listFrom(dynamic v) =>
      (v as List? ?? []).map((e) => Category.fromJson(e)).toList();
  bool get isExpense => type == 'expense';
}

class Flow {
  final int id;
  final String type;
  final double amount;
  final String category;
  final String paymentMethod;
  final String description;
  final String flowTime;
  final String attribution;
  final String? attributionColor;
  /// 来源：'' 手动 | 'ai' AI识别 | 'auto' 通知自动记账
  final String source;
  Flow({
    required this.id,
    required this.type,
    required this.amount,
    required this.category,
    required this.paymentMethod,
    required this.description,
    required this.flowTime,
    required this.attribution,
    this.attributionColor,
    this.source = '',
  });
  factory Flow.fromJson(Map<String, dynamic> j) => Flow(
        id: j['id'],
        type: j['type'] ?? 'expense',
        amount: (j['amount'] ?? 0).toDouble(),
        category: j['category'] ?? '',
        paymentMethod: j['payment_method'] ?? '',
        description: j['description'] ?? '',
        flowTime: j['flow_time'] ?? '',
        attribution: j['attribution'] ?? '',
        attributionColor: j['attribution_color'],
        source: j['source'] ?? '',
      );
  static List<Flow> listFrom(dynamic v) =>
      (v as List? ?? []).map((e) => Flow.fromJson(e)).toList();
  bool get isExpense => type == 'expense';
  /// 是否是 AI/自动记账来源（显示 AI 小标识）
  bool get isAiSource => source == 'ai' || source == 'auto';
}

class FlowPage {
  final int total;
  final double expense;
  final double income;
  final List<Flow> list;
  FlowPage({
    required this.total,
    required this.expense,
    required this.income,
    required this.list,
  });
  factory FlowPage.fromJson(Map<String, dynamic> j) => FlowPage(
        total: j['total'] ?? 0,
        expense: (j['expense'] ?? 0).toDouble(),
        income: (j['income'] ?? 0).toDouble(),
        list: Flow.listFrom(j['list']),
      );
}

class Overview {
  final double expense;
  final double income;
  final double balance;
  final int count;
  final int totalCount;
  Overview({
    required this.expense,
    required this.income,
    required this.balance,
    required this.count,
    required this.totalCount,
  });
  factory Overview.fromJson(Map<String, dynamic> j) => Overview(
        expense: (j['expense'] ?? 0).toDouble(),
        income: (j['income'] ?? 0).toDouble(),
        balance: (j['balance'] ?? 0).toDouble(),
        count: j['count'] ?? 0,
        totalCount: j['totalCount'] ?? 0,
      );
}

class CatStat {
  final String name;
  final double value;
  final int count;
  final String? color;
  CatStat({required this.name, required this.value, required this.count, this.color});
  factory CatStat.fromJson(Map<String, dynamic> j) => CatStat(
        name: j['name'] ?? '',
        value: (j['value'] ?? 0).toDouble(),
        count: j['count'] ?? 0,
        color: j['color'],
      );
  static List<CatStat> listFrom(dynamic v) =>
      (v as List? ?? []).map((e) => CatStat.fromJson(e)).toList();
}

class DailyTopItem {
  final double amount;
  final String? category;
  final String? description;
  DailyTopItem({required this.amount, this.category, this.description});
  factory DailyTopItem.fromJson(Map<String, dynamic> j) => DailyTopItem(
        amount: (j['amount'] ?? 0).toDouble(),
        category: j['category'],
        description: j['description'],
      );
  static List<DailyTopItem> listFrom(dynamic v) =>
      (v as List? ?? []).map((e) => DailyTopItem.fromJson(e)).toList();
}

class DailyStat {
  final String date;
  final double expense;
  final double income;
  final Map<String, List<DailyTopItem>> top;
  DailyStat({required this.date, required this.expense, required this.income, required this.top});
  factory DailyStat.fromJson(Map<String, dynamic> j) {
    final topRaw = j['top'] as Map<String, dynamic>? ?? {};
    final top = <String, List<DailyTopItem>>{};
    topRaw.forEach((k, v) => top[k] = DailyTopItem.listFrom(v));
    return DailyStat(
      date: j['date'] ?? '',
      expense: (j['expense'] ?? 0).toDouble(),
      income: (j['income'] ?? 0).toDouble(),
      top: top,
    );
  }
  static List<DailyStat> listFrom(dynamic v) =>
      (v as List? ?? []).map((e) => DailyStat.fromJson(e)).toList();
}

class MonthlyStat {
  final String month;
  final double expense;
  final double income;
  MonthlyStat({required this.month, required this.expense, required this.income});
  factory MonthlyStat.fromJson(Map<String, dynamic> j) => MonthlyStat(
        month: j['month'] ?? '',
        expense: (j['expense'] ?? 0).toDouble(),
        income: (j['income'] ?? 0).toDouble(),
      );
  static List<MonthlyStat> listFrom(dynamic v) =>
      (v as List? ?? []).map((e) => MonthlyStat.fromJson(e)).toList();
}

class BudgetCat {
  final String category;
  final double amount;
  final String expression;
  final double spent;
  final double remaining;
  final int percent;
  BudgetCat({
    required this.category,
    required this.amount,
    required this.expression,
    required this.spent,
    required this.remaining,
    required this.percent,
  });
  factory BudgetCat.fromJson(Map<String, dynamic> j) => BudgetCat(
        category: j['category'] ?? '',
        amount: (j['amount'] ?? 0).toDouble(),
        expression: j['expression'] ?? '',
        spent: (j['spent'] ?? 0).toDouble(),
        remaining: (j['remaining'] ?? 0).toDouble(),
        percent: j['percent'] ?? 0,
      );
  static List<BudgetCat> listFrom(dynamic v) =>
      (v as List? ?? []).map((e) => BudgetCat.fromJson(e)).toList();
}

class BudgetData {
  final int year;
  final double totalAmount;
  final double totalSpent;
  final double totalRemaining;
  final int totalPercent;
  final List<BudgetCat> categories;
  final Map<String, double> spentByCategory;
  BudgetData({
    required this.year,
    required this.totalAmount,
    required this.totalSpent,
    required this.totalRemaining,
    required this.totalPercent,
    required this.categories,
    required this.spentByCategory,
  });
  factory BudgetData.fromJson(Map<String, dynamic> j) {
    final t = j['total'] ?? {};
    final sbc = <String, double>{};
    (j['spentByCategory'] as Map? ?? {}).forEach((k, v) => sbc[k] = (v ?? 0).toDouble());
    return BudgetData(
      year: j['year'] ?? DateTime.now().year,
      totalAmount: (t['amount'] ?? 0).toDouble(),
      totalSpent: (t['spent'] ?? 0).toDouble(),
      totalRemaining: (t['remaining'] ?? 0).toDouble(),
      totalPercent: t['percent'] ?? 0,
      categories: BudgetCat.listFrom(j['categories']),
      spentByCategory: sbc,
    );
  }
}

class BillRow {
  final String month;
  final String label;
  final double income;
  final double expense;
  final double balance;
  final int count;
  final int year;
  BillRow({
    required this.month,
    required this.label,
    required this.income,
    required this.expense,
    required this.balance,
    required this.count,
    this.year = 0,
  });
  factory BillRow.fromJson(Map<String, dynamic> j) => BillRow(
        month: j['month'] ?? '',
        label: j['label'] ?? '',
        income: (j['income'] ?? 0).toDouble(),
        expense: (j['expense'] ?? 0).toDouble(),
        balance: (j['balance'] ?? 0).toDouble(),
        count: j['count'] ?? 0,
        year: j['year'] ?? 0,
      );
  static List<BillRow> listFrom(dynamic v) =>
      (v as List? ?? []).map((e) => BillRow.fromJson(e)).toList();
}

class BillMonthly {
  final int year;
  final List<int> years;
  final BillRow summary;
  final List<BillRow> rows;
  BillMonthly({
    required this.year,
    required this.years,
    required this.summary,
    required this.rows,
  });
  factory BillMonthly.fromJson(Map<String, dynamic> j) => BillMonthly(
        year: j['year'] ?? DateTime.now().year,
        years: (j['years'] as List? ?? []).map((e) => e as int).toList(),
        summary: BillRow.fromJson(j['summary'] ?? {}),
        rows: BillRow.listFrom(j['rows']),
      );
}

class BillYearly {
  final BillRow summary;
  final List<BillRow> rows;
  BillYearly({required this.summary, required this.rows});
  factory BillYearly.fromJson(Map<String, dynamic> j) => BillYearly(
        summary: BillRow.fromJson(j['summary'] ?? {}),
        rows: BillRow.listFrom(j['rows']),
      );
}

class SavingsItem {
  final int id;
  final String name;
  final int sign;
  final double amount;
  final String note;
  final String asOf;
  final String asOfEnd;
  final int sort;
  SavingsItem({
    required this.id,
    required this.name,
    required this.sign,
    required this.amount,
    required this.note,
    required this.asOf,
    required this.asOfEnd,
    required this.sort,
  });
  factory SavingsItem.fromJson(Map<String, dynamic> j) => SavingsItem(
        id: j['id'],
        name: j['name'] ?? '',
        sign: j['sign'] ?? 1,
        amount: (j['amount'] ?? 0).toDouble(),
        note: j['note'] ?? '',
        asOf: j['as_of'] ?? '',
        asOfEnd: j['as_of_end'] ?? '',
        sort: j['sort'] ?? 0,
      );
  static List<SavingsItem> listFrom(dynamic v) =>
      (v as List? ?? []).map((e) => SavingsItem.fromJson(e)).toList();
  bool get isLiability => sign < 0;
}

class SavingsMonth {
  final String ymd;
  final double asset;
  final double liability;
  final double net;
  final String opUser;
  SavingsMonth({
    required this.ymd,
    required this.asset,
    required this.liability,
    required this.net,
    required this.opUser,
  });
  factory SavingsMonth.fromJson(Map<String, dynamic> j) => SavingsMonth(
        ymd: j['ymd'] ?? '',
        asset: (j['asset'] ?? 0).toDouble(),
        liability: (j['liability'] ?? 0).toDouble(),
        net: (j['net'] ?? 0).toDouble(),
        opUser: j['op_user'] ?? '',
      );
  static List<SavingsMonth> listFrom(dynamic v) =>
      (v as List? ?? []).map((e) => SavingsMonth.fromJson(e)).toList();
}

class SavingsOverview {
  final Map<String, dynamic> goal;
  final List<SavingsItem> items;
  final List<SavingsItem> expiredItems;
  final Map<String, dynamic> current;
  final List<SavingsMonth> months;
  SavingsOverview({
    required this.goal,
    required this.items,
    required this.expiredItems,
    required this.current,
    required this.months,
  });
  factory SavingsOverview.fromJson(Map<String, dynamic> j) => SavingsOverview(
        goal: j['goal'] ?? {},
        items: SavingsItem.listFrom(j['items']),
        expiredItems: SavingsItem.listFrom(j['expiredItems']),
        current: j['current'] ?? {},
        months: SavingsMonth.listFrom(j['months']),
      );
  double get target => (goal['target'] ?? 0).toDouble();
  double get net => (current['net'] ?? 0).toDouble();
  double get asset => (current['asset'] ?? 0).toDouble();
  double get liability => (current['liability'] ?? 0).toDouble();
  int get percent => current['percent'] ?? 0;
  double get remaining => (current['remaining'] ?? 0).toDouble();
}

class Wallet {
  final int id;
  final String name;
  final String icon;
  final double target;
  final String note;
  final String linkFrom;
  final String linkCategory;
  final double manualBalance;
  final double linked;
  final double balance;
  final double totalIn;
  final double totalOut;
  final int count;
  final String lastYmd;
  final int percent;
  Wallet({
    required this.id,
    required this.name,
    required this.icon,
    required this.target,
    required this.note,
    required this.linkFrom,
    required this.linkCategory,
    required this.manualBalance,
    required this.linked,
    required this.balance,
    required this.totalIn,
    required this.totalOut,
    required this.count,
    required this.lastYmd,
    required this.percent,
  });
  factory Wallet.fromJson(Map<String, dynamic> j) => Wallet(
        id: j['id'],
        name: j['name'] ?? '',
        icon: j['icon'] ?? '👛',
        target: (j['target'] ?? 0).toDouble(),
        note: j['note'] ?? '',
        linkFrom: j['link_from'] ?? '',
        linkCategory: j['link_category'] ?? '',
        manualBalance: (j['manualBalance'] ?? 0).toDouble(),
        linked: (j['linked'] ?? 0).toDouble(),
        balance: (j['balance'] ?? 0).toDouble(),
        totalIn: (j['total_in'] ?? 0).toDouble(),
        totalOut: (j['total_out'] ?? 0).toDouble(),
        count: j['count'] ?? 0,
        lastYmd: j['last_ymd'] ?? '',
        percent: j['percent'] ?? 0,
      );
  static List<Wallet> listFrom(dynamic v) =>
      (v as List? ?? []).map((e) => Wallet.fromJson(e)).toList();
}

class WalletsData {
  final List<Wallet> wallets;
  final double totalBalance;
  final double totalTarget;
  WalletsData({
    required this.wallets,
    required this.totalBalance,
    required this.totalTarget,
  });
  factory WalletsData.fromJson(Map<String, dynamic> j) => WalletsData(
        wallets: Wallet.listFrom(j['wallets']),
        totalBalance: (j['totalBalance'] ?? 0).toDouble(),
        totalTarget: (j['totalTarget'] ?? 0).toDouble(),
      );
}

class AiStatus {
  final bool enabled;
  final String? provider;
  final String? model;
  final String? imageModel;
  AiStatus({
    required this.enabled,
    this.provider,
    this.model,
    this.imageModel,
  });
  factory AiStatus.fromJson(Map<String, dynamic> j) => AiStatus(
        enabled: j['enabled'] ?? false,
        provider: j['provider'],
        model: j['model'],
        imageModel: j['imageModel'],
      );
}

class AiParseResult {
  final String? type;
  final double? amount;
  final String? category;
  final String? description;
  final String? paymentMethod;
  final String? date;
  final String? raw;
  AiParseResult({
    this.type,
    this.amount,
    this.category,
    this.description,
    this.paymentMethod,
    this.date,
    this.raw,
  });
  factory AiParseResult.fromJson(Map<String, dynamic> j) => AiParseResult(
        type: j['type'],
        amount: j['amount'] != null ? (j['amount']).toDouble() : null,
        category: j['category'],
        description: j['description'],
        paymentMethod: j['payment_method'],
        date: j['date'],
        raw: j['raw'],
      );
}

class AiAnalyze {
  final Map<String, dynamic> summary;
  final String analysis;
  final bool ai;
  AiAnalyze({required this.summary, required this.analysis, required this.ai});
  factory AiAnalyze.fromJson(Map<String, dynamic> j) => AiAnalyze(
        summary: j['summary'] ?? {},
        analysis: j['analysis'] ?? '',
        ai: j['ai'] ?? false,
      );
}

class AiModel {
  final String id;
  final String name;
  final String provider;
  final String baseUrl;
  final String apiKey;
  final String model;
  final String imageModel;
  final bool isDefault;
  AiModel({
    required this.id,
    required this.name,
    required this.provider,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.imageModel,
    required this.isDefault,
  });
  factory AiModel.fromJson(Map<String, dynamic> j) => AiModel(
        id: j['id'] ?? '',
        name: j['name'] ?? '',
        provider: j['provider'] ?? '',
        baseUrl: j['baseUrl'] ?? '',
        apiKey: j['apiKey'] ?? '',
        model: j['model'] ?? '',
        imageModel: j['imageModel'] ?? '',
        isDefault: j['isDefault'] ?? false,
      );
  static List<AiModel> listFrom(dynamic v) =>
      (v as List? ?? []).map((e) => AiModel.fromJson(e)).toList();
}

class Meta {
  final String name;
  final String version;
  Meta({required this.name, required this.version});
  factory Meta.fromJson(Map<String, dynamic> j) =>
      Meta(name: j['name'] ?? '记账本', version: j['version'] ?? '');
}

class PresetName {
  final String name;
  final String? category;
  final String? paymentMethod;
  final double? amount;
  PresetName({
    required this.name,
    this.category,
    this.paymentMethod,
    this.amount,
  });
  factory PresetName.fromJson(Map<String, dynamic> j) => PresetName(
        name: j['name'] ?? '',
        category: j['category'],
        paymentMethod: j['payment_method'],
        amount: j['amount'] != null ? (j['amount']).toDouble() : null,
      );
  static List<PresetName> listFrom(dynamic v) =>
      (v as List? ?? []).map((e) => PresetName.fromJson(e)).toList();
}

class PresetsData {
  final List<PresetName> presets;
  final List<PresetName> frequent;
  final List<PresetName> recent;
  PresetsData({
    required this.presets,
    required this.frequent,
    required this.recent,
  });
  factory PresetsData.fromJson(Map<String, dynamic> j) => PresetsData(
        presets: PresetName.listFrom(j['presets']),
        frequent: PresetName.listFrom(j['frequent']),
        recent: PresetName.listFrom(j['recent']),
      );
}

/// 定期记账模板
class Recurring {
  final int id;
  final String type; // expense | income
  final String category;
  final String description;
  final double amount;
  final String paymentMethod;
  final String freq; // monthly | yearly
  final int dayOfMonth;
  final int monthOfYear;
  final String note;
  final String nextRun;
  final int? attributionUid;
  final String attribution;
  Recurring({
    required this.id,
    required this.type,
    required this.category,
    required this.description,
    required this.amount,
    required this.paymentMethod,
    required this.freq,
    required this.dayOfMonth,
    required this.monthOfYear,
    required this.note,
    required this.nextRun,
    this.attributionUid,
    this.attribution = '',
  });
  factory Recurring.fromJson(Map<String, dynamic> j) => Recurring(
        id: j['id'],
        type: j['type'] ?? 'expense',
        category: j['category'] ?? '',
        description: j['description'] ?? '',
        amount: (j['amount'] ?? 0).toDouble(),
        paymentMethod: j['payment_method'] ?? '',
        freq: j['freq'] ?? 'monthly',
        dayOfMonth: j['day_of_month'] ?? 1,
        monthOfYear: j['month_of_year'] ?? 1,
        note: j['note'] ?? '',
        nextRun: j['next_run'] ?? '',
        attributionUid: j['attribution_uid'],
        attribution: j['attribution'] ?? '',
      );
  static List<Recurring> listFrom(dynamic v) =>
      (v as List? ?? []).map((e) => Recurring.fromJson(e as Map<String, dynamic>)).toList();
  bool get isExpense => type == 'expense';
  String get freqText => freq == 'yearly'
      ? '每年 $monthOfYear 月 $dayOfMonth 号'
      : '每月 $dayOfMonth 号';
}

/// 账本成员（归属下拉用）
class AttributionMember {
  final int id;
  final String nickname;
  AttributionMember({required this.id, required this.nickname});
  factory AttributionMember.fromJson(Map<String, dynamic> j) =>
      AttributionMember(id: j['id'], nickname: j['nickname'] ?? '');
}
