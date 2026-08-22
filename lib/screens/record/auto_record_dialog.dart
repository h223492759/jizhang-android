import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jizhang_android/core/models.dart';
import 'package:jizhang_android/core/theme.dart';
import 'package:jizhang_android/core/util.dart';
import 'package:jizhang_android/state/session.dart';
import 'package:jizhang_android/screens/record/auto_record_service.dart';

/// 弹窗结果：记一笔 / 修改后记 / 忽略 / 加入排除规则
class AutoRecordAction {
  final bool ignore;
  final bool neverAgain;
  final bool isIncome;
  final double amount;
  final String description;
  final String category;
  final String merchant;
  final String pkg;
  final DateTime time;
  AutoRecordAction({
    required this.ignore,
    required this.neverAgain,
    required this.isIncome,
    required this.amount,
    required this.description,
    required this.category,
    required this.merchant,
    required this.pkg,
    required this.time,
  });
}

class AutoRecordDialog extends ConsumerStatefulWidget {
  final ParsedNotification parsed;
  const AutoRecordDialog({super.key, required this.parsed});

  @override
  ConsumerState<AutoRecordDialog> createState() => _AutoRecordDialogState();
}

class _AutoRecordDialogState extends ConsumerState<AutoRecordDialog> {
  late final TextEditingController _nameCtrl;
  late String _category;
  String? _aiCategory; // AI/映射给的初始分类（用于判断用户是否改过 → 学习）
  bool _aiLoading = true;
  List<Category> _cats = [];

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.parsed.merchant);
    _category = widget.parsed.isIncome ? '其他' : '餐饮';
    _loadCats();
    _aiClassify();
  }

  Future<void> _loadCats() async {
    try {
      final cats = await ref.read(apiProvider).getCategories();
      if (mounted) setState(() => _cats = cats);
    } catch (_) {}
  }

  Future<void> _aiClassify() async {
    try {
      final api = ref.read(apiProvider);
      // 学习闭环：先查 商户→分类 映射（命中直接返回），否则 AI 分类
      final r = await api.classifyMerchant(
        merchant: widget.parsed.merchant,
        text: widget.parsed.text,
        amount: widget.parsed.amount,
        type: widget.parsed.isIncome ? 'income' : 'expense',
      );
      if (mounted) {
        setState(() {
          final aiCat = r.category ?? '';
          final aiDesc = r.description ?? '';
          if (aiCat.isNotEmpty) {
            _category = aiCat;
            _aiCategory = aiCat;
          }
          if (aiDesc.isNotEmpty &&
              !_nameCtrl.text.contains(aiDesc) &&
              aiDesc != widget.parsed.merchant) {
            _nameCtrl.text = aiDesc;
          }
          _aiLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _aiLoading = false;
        });
      }
    }
  }

  /// 学习闭环：用户点了「记一笔」，若分类被改过（与 AI/映射不同）且商户明确 → 写入映射
  Future<void> _maybeLearn() async {
    final p = widget.parsed;
    if (p.merchant.isEmpty) return;
    if (p.merchant == '支出' || p.merchant == '收款') return;
    if (_aiCategory != null && _category == _aiCategory) return; // 没改过，不学
    try {
      await ref.read(apiProvider).learnMerchant(p.merchant, _category);
    } catch (_) {}
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _pop(AutoRecordAction a) => Navigator.pop(context, a);

  @override
  Widget build(BuildContext context) {
    final p = widget.parsed;
    final dateText =
        '${p.time.year}-${p.time.month.toString().padLeft(2, '0')}-${p.time.day.toString().padLeft(2, '0')}';
    final payLabel = _pkgLabel(p.pkg);
    return AlertDialog(
      // 第一区：确认记账（左）+ 来源小字（右对齐）
      title: Row(children: [
        const Expanded(
            child: Text('确认记账', style: TextStyle(fontSize: 16))),
        if (payLabel.isNotEmpty)
          Text(payLabel,
              style: TextStyle(
                  fontSize: 11, color: AppPalette.textSecondary(context))),
      ]),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 第二区：支出金额（左）+ 支付方式/日期（右侧 2 行右对齐）
            Row(children: [
              Text(p.isIncome ? '收入' : '支出',
                  style: TextStyle(
                      fontSize: 13,
                      color: p.isIncome ? AppColors.income : AppColors.expense,
                      fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Text('¥${fmtMoney(p.amount)}',
                  style:
                      const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (payLabel.isNotEmpty)
                    Text(payLabel,
                        style: TextStyle(
                            fontSize: 12, color: AppPalette.textSecondary(context))),
                  const SizedBox(height: 2),
                  Text(dateText,
                      style: TextStyle(
                          fontSize: 12, color: AppPalette.textSecondary(context))),
                ],
              ),
            ]),
            const SizedBox(height: 4),
            Text(p.merchant,
                style:
                    TextStyle(fontSize: 13, color: AppPalette.textSecondary(context))),
            const SizedBox(height: 12),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                  labelText: '名称', border: OutlineInputBorder(), isDense: true),
            ),
            const SizedBox(height: 10),
            // 第三区：分类（无"分类"文字，四行网格放完整，不截断）
            _aiLoading
                ? SizedBox(
                    height: 80,
                    child: Center(
                      child: Text('AI 识别中…',
                          style: TextStyle(
                              fontSize: 12, color: AppPalette.textSecondary(context))),
                    ),
                  )
                : GridView.count(
                    crossAxisCount: 6,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 4,
                    crossAxisSpacing: 4,
                    childAspectRatio: 2.4,
                    children: _cats.isEmpty
                        ? [
                            Center(
                                child: Text(_category,
                                    style:
                                        const TextStyle(fontSize: 12)))
                          ]
                        : _cats.map((c) {
                            final on = c.name == _category;
                            return InkWell(
                              onTap: () =>
                                  setState(() => _category = c.name),
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                alignment: Alignment.center,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 2),
                                decoration: BoxDecoration(
                                  color: on
                                      ? AppColors.primary
                                      : AppPalette.background(context),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: on
                                        ? AppColors.primaryDark
                                        : AppPalette.divider(context),
                                    width: on ? 1.2 : 1,
                                  ),
                                ),
                                child: Text(
                                  c.name,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: on
                                        ? Colors.white
                                        : AppPalette.text(context),
                                    fontWeight:
                                        on ? FontWeight.w600 : FontWeight.normal,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                  ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => _pop(AutoRecordAction(
              ignore: true,
              neverAgain: false,
              isIncome: p.isIncome,
              amount: p.amount,
              description: _nameCtrl.text.trim(),
              category: _category,
              merchant: p.merchant,
              pkg: p.pkg,
              time: p.time)),
          child: const Text('忽略'),
        ),
        TextButton(
          onPressed: () => _pop(AutoRecordAction(
              ignore: true,
              neverAgain: true,
              isIncome: p.isIncome,
              amount: p.amount,
              description: _nameCtrl.text.trim(),
              category: _category,
              merchant: p.merchant,
              pkg: p.pkg,
              time: p.time)),
          child: const Text('不再记', style: TextStyle(color: AppColors.expense)),
        ),
        TextButton(
          onPressed: () {
            _maybeLearn(); // 学习闭环：改过分类则写入 商户→分类 映射（不影响记账）
            _pop(AutoRecordAction(
                ignore: false,
                neverAgain: false,
                isIncome: p.isIncome,
                amount: p.amount,
                description: _nameCtrl.text.trim(),
                category: _category,
                merchant: p.merchant,
                pkg: p.pkg,
                time: p.time));
          },
          child: const Text('记一笔', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  String _pkgLabel(String pkg) {
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
