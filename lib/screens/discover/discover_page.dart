import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jizhang_android/core/api.dart';
import 'package:jizhang_android/core/models.dart';
import 'package:jizhang_android/core/theme.dart';
import 'package:jizhang_android/core/util.dart';
import 'package:jizhang_android/state/session.dart';
import 'package:jizhang_android/core/local_first_api.dart';

class DiscoverPage extends ConsumerStatefulWidget {
  const DiscoverPage({super.key});
  @override
  ConsumerState<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends ConsumerState<DiscoverPage> {
  final _ctrl = TextEditingController();
  final List<_Msg> _msgs = [];
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    _ctrl.clear();
    setState(() => _msgs.add(_Msg(role: 'user', text: text)));
    setState(() => _busy = true);
    try {
      final r = await ref.read(localApiProvider).parseText(text);
      setState(() => _msgs.add(_Msg(role: 'ai', text: '已识别以下记账信息', parse: r)));
    } catch (e) {
      setState(() => _msgs.add(_Msg(role: 'ai', text: e.toString().replaceFirst('ApiException: ', ''))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _analyze() async {
    setState(() => _busy = true);
    try {
      final a = await ref.read(localApiProvider).analyzeMonth();
      setState(() => _msgs.add(_Msg(role: 'ai', text: a.analysis.isEmpty ? '（AI 未返回分析）' : a.analysis)));
    } catch (e) {
      setState(() => _msgs.add(_Msg(role: 'ai', text: e.toString().replaceFirst('ApiException: ', ''))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save(_Msg m) async {
    final p = m.parse;
    if (p == null) return;
    final amt = p.amount;
    if (amt == null || amt <= 0) {
      toast('解析结果缺少有效金额');
      return;
    }
    try {
      await ref.read(localApiProvider).createFlow({
        'type': p.type ?? 'expense',
        'amount': amt,
        'category': p.category ?? '其他',
        'description': p.description ?? '',
        'payment_method': p.paymentMethod ?? '',
        'flow_time': p.date ?? ymdNow(),
      });
      ref.read(dataVersionProvider.notifier).state++;
      toast('已保存');
      setState(() => m.saved = true);
    } catch (e) {
      toast(e.toString().replaceFirst('ApiException: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('发现'),
        actions: [
          TextButton(onPressed: _busy ? null : _analyze, child: const Text('本月分析', style: TextStyle(color: AppColors.text))),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _msgs.isEmpty
                ? _emptyGuide()
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _msgs.length,
                    itemBuilder: (_, i) => _bubble(_msgs[i]),
                  ),
          ),
          if (_busy) const LinearProgressIndicator(),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 84),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    decoration: InputDecoration(
                      hintText: '说点什么，如「午饭花了38元」',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                FloatingActionButton.small(onPressed: _send, child: const Icon(Icons.send)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyGuide() {
    final examples = [
      '午饭花了38元',
      '8月15号工资到账12000',
      '滴滴打车22.5，从公司回家',
      '这个月奶茶一共花了多少',
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('👋 用自然语言记账 & 问账',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.text)),
                SizedBox(height: 6),
                Text('直接说一句，比如「午饭花了38元」，AI 会自动识别金额、分类、时间，确认后即可入账。',
                    style: TextStyle(fontSize: 13, color: AppColors.text)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text('试试这些：', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: examples
                .map((e) => ActionChip(
                      label: Text(e, style: const TextStyle(fontSize: 13)),
                      backgroundColor: Colors.white,
                      side: BorderSide(color: AppColors.divider),
                      onPressed: () {
                        _ctrl.text = e;
                        _send();
                      },
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _bubble(_Msg m) {
    final isUser = m.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        decoration: BoxDecoration(
          color: isUser ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: isUser ? null : Border.all(color: AppColors.divider),
        ),
        child: m.parse != null ? _parseCard(m) : Text(m.text),
      ),
    );
  }

  Widget _parseCard(_Msg m) {
    final p = m.parse!;
    final typeLabel = p.type == 'income' ? '收入' : '支出';
    final color = p.type == 'income' ? AppColors.income : AppColors.expense;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(m.text, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 4, children: [
          Chip(label: Text(typeLabel, style: TextStyle(color: color)), backgroundColor: color.withOpacity(0.12)),
          if (p.amount != null) Chip(label: Text('¥${fmtMoney(p.amount!)}')),
          if (p.category != null) Chip(label: Text('分类：${p.category}')),
          if (p.description != null && p.description!.isNotEmpty) Chip(label: Text(p.description!)),
        ]),
        const SizedBox(height: 6),
        if (!m.saved)
          ElevatedButton(onPressed: () => _save(m), child: const Text('保存为流水'))
        else
          const Text('✓ 已保存', style: TextStyle(color: AppColors.income)),
      ],
    );
  }
}

class _Msg {
  final String role;
  final String text;
  final AiParseResult? parse;
  bool saved = false;
  _Msg({required this.role, required this.text, this.parse});
}
