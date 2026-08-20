import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  // 从网页端 /presets 同步过来的常用名建议（点一下填到输入框，由用户确认/修改再发送）
  List<_PresetChip> _suggest = [];
  bool _loadingSuggest = false;

  @override
  void initState() {
    super.initState();
    _loadSuggest();
  }

  Future<void> _loadSuggest() async {
    if (!mounted) return;
    setState(() => _loadingSuggest = true);
    try {
      // 一次性拉两个类型（合并去重），按"已收藏优先 + 未收藏按频次降序"排序
      // 走 localApiProvider：本地镜像直读（秒开）+ 过期 5 分钟后台自动同步
      final s = ref.read(sessionProvider);
      if (!s.hasToken || !s.hasBook) return;
      final ex = await ref.read(localApiProvider).getPresets(type: 'expense');
      final inc = await ref.read(localApiProvider).getPresets(type: 'income');
      final chips = <_PresetChip>[];
      for (final p in ex.presets) {
        chips.add(_PresetChip(name: p.name, type: 'expense', pinned: true));
      }
      for (final p in ex.frequent) {
        if (!chips.any((c) => c.name == p.name)) {
          chips.add(_PresetChip(
              name: p.name, type: 'expense', pinned: false, count: p.count));
        }
      }
      for (final p in inc.presets) {
        chips.add(_PresetChip(name: p.name, type: 'income', pinned: true));
      }
      for (final p in inc.frequent) {
        if (!chips.any((c) => c.name == p.name)) {
          chips.add(_PresetChip(
              name: p.name, type: 'income', pinned: false, count: p.count));
        }
      }
      if (mounted) setState(() => _suggest = chips);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingSuggest = false);
    }
  }

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
      if ((r.amount ?? 0) <= 0) {
        // 问句/叙述（如「这个月奶茶一共花了多少」）→ 不当作记账，友好提示
        setState(() => _msgs.add(
            _Msg(role: 'ai', text: '没有识别到金额：这似乎不是一笔消费。请直接说「XX花了X元」这类的话。')));
      } else {
        setState(() => _msgs.add(_Msg(role: 'ai', text: '已识别以下记账信息', parse: r)));
      }
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
          // 网页端常用名（★ + ×N），点一下把名称填到输入框，由用户补金额/修改后再发送
          if (_suggest.isNotEmpty) ...[
            const Text('你的常用名称（来自网页端，点击填到输入框）',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _suggest.map((c) {
                final label = c.pinned
                    ? '★ ${c.name}'
                    : (c.count > 0 ? '${c.name} ×${c.count}' : c.name);
                return ActionChip(
                  label: Text(label, style: const TextStyle(fontSize: 13)),
                  backgroundColor: c.pinned ? AppColors.primarySoft : Colors.white,
                  side: BorderSide(color: AppColors.divider),
                  onPressed: () {
                    // 只填名称到输入框，不自动发送——避免误记（数据不靠推荐默认）
                    _ctrl.text = c.name;
                    _ctrl.selection = TextSelection.collapsed(offset: c.name.length);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],
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
                        // 与上方常用名称一致：只填到输入框，由用户确认/修改后再发送，
                        // 避免示例直接记账造成误记
                        _ctrl.text = e;
                        _ctrl.selection = TextSelection.collapsed(offset: e.length);
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

/// 网页端常用名在发现页的展示项
class _PresetChip {
  final String name;
  final String type; // expense | income
  final bool pinned; // true=已收藏 ★ / false=未收藏 ×N
  final int count; // 仅未收藏有值
  _PresetChip({required this.name, required this.type, required this.pinned, this.count = 0});
}
