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
      final r = await api.parseText(widget.parsed.text);
      if (mounted) {
        setState(() {
          final aiCat = r.category ?? '';
          final aiDesc = r.description ?? '';
          if (aiCat.isNotEmpty) _category = aiCat;
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

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _pop(AutoRecordAction a) => Navigator.pop(context, a);

  @override
  Widget build(BuildContext context) {
    final p = widget.parsed;
    return AlertDialog(
      title: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text('AI 记账',
              style: TextStyle(fontSize: 11, color: AppColors.text, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 8),
        const Expanded(child: Text('确认记账', style: TextStyle(fontSize: 16))),
      ]),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text(p.isIncome ? '收入' : '支出',
                  style: TextStyle(
                      fontSize: 13,
                      color: p.isIncome ? AppColors.income : AppColors.expense,
                      fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Text('¥${fmtMoney(p.amount)}',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 6),
            Text(p.merchant, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            Text('${p.time.year}-${p.time.month.toString().padLeft(2, '0')}-${p.time.day.toString().padLeft(2, '0')}',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                  labelText: '名称', border: OutlineInputBorder(), isDense: true),
            ),
            const SizedBox(height: 10),
            // 分类选择
            Row(children: [
              const Text('分类', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(width: 10),
              Expanded(
                child: _aiLoading
                    ? const Text('AI 识别中…',
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary))
                    : Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          ..._cats.take(12).map((c) => ChoiceChip(
                                label: Text(c.name,
                                    style: const TextStyle(fontSize: 12)),
                                selected: c.name == _category,
                                visualDensity: VisualDensity.compact,
                                onSelected: (_) =>
                                    setState(() => _category = c.name),
                              )),
                          if (_cats.isEmpty)
                            Text(_category,
                                style: const TextStyle(fontSize: 12)),
                        ],
                      ),
              ),
            ]),
            const SizedBox(height: 6),
            Text('来源：${_pkgLabel(p.pkg)} 通知自动识别',
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
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
          onPressed: () => _pop(AutoRecordAction(
              ignore: false,
              neverAgain: false,
              isIncome: p.isIncome,
              amount: p.amount,
              description: _nameCtrl.text.trim(),
              category: _category,
              merchant: p.merchant,
              pkg: p.pkg,
              time: p.time)),
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
