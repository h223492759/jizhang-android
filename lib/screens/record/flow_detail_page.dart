import 'package:flutter/material.dart' hide Flow;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jizhang_android/core/models.dart';
import 'package:jizhang_android/core/theme.dart';
import 'package:jizhang_android/core/util.dart';
import 'package:jizhang_android/core/category_icon.dart';
import 'package:jizhang_android/core/owner_color.dart';
import 'package:jizhang_android/state/session.dart';
import 'package:jizhang_android/core/local_first_api.dart';
import 'auto_record_service.dart';
import 'record_page.dart';

class FlowDetailPage extends ConsumerStatefulWidget {
  final Flow flow;
  const FlowDetailPage({super.key, required this.flow});

  @override
  ConsumerState<FlowDetailPage> createState() => _FlowDetailPageState();
}

class _FlowDetailPageState extends ConsumerState<FlowDetailPage> {
  late List<Category> _cats;
  bool _loaded = false;
  // 流水最新 source（widget.flow 不可变，每次进页面从本地重新读）
  late String _source;

  @override
  void initState() {
    super.initState();
    _cats = [];
    _source = widget.flow.source;
    _load();
  }

  Future<void> _load() async {
    try {
      _cats = await ref.read(localApiProvider).getCategories();
    } catch (_) {
      _cats = [];
    }
    // 从本地 DB 读最新 source（widget.flow 不可变，用户隐藏/恢复后再次进入要反映最新）
    try {
      final row = await LocalDb.instance.flowById(widget.flow.id);
      if (row != null && mounted) {
        _source = (row['source'] as String?) ?? widget.flow.source;
      }
    } catch (_) {}
    if (mounted) setState(() => _loaded = true);
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.flow;
    final expense = f.isExpense;
    final date = parseYmd(datePart(f.flowTime));
    final iconMap = buildCatIconMap(_cats);
    final user = ref.watch(sessionProvider).user;
    final ownerColor = ownerColorFor(f, ref.watch(ownerColorsProvider), user);
    final ownerLabel = f.attribution.isEmpty ? '我' : f.attribution;
    return Scaffold(
      backgroundColor: AppPalette.background(context),
      appBar: AppBar(
        backgroundColor: AppPalette.primaryDim(context),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('查看明细'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: AppPalette.primaryDim(context),
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppPalette.card(context),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    catIconOf(iconMap, f.category),
                    style: const TextStyle(fontSize: 32),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  f.category,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _row('类型', expense ? '支出' : '收入'),
                  const Divider(height: 24),
                  _row('金额', '${expense ? '-' : '+'}${fmtMoney(f.amount)}',
                      valueColor: expense ? AppColors.expense : AppColors.income),
                  const Divider(height: 24),
                  _row('日期', '${ymd(date)} ${weekdayCn(date)}'),
                  if (f.description.isNotEmpty) ...[
                    const Divider(height: 24),
                    _row('名称', f.description,
                        prefix: f.isAiSource ? _aiTag() : null),
                  ],
                  // AI 记账流水显示来源（支付方式），方便核对：微信支付/支付宝支付/XX银行卡等
                  if (f.isAiSource) ...[
                    const Divider(height: 24),
                    _row('来源', f.paymentMethod.isNotEmpty ? f.paymentMethod : 'AI 自动记账'),
                  ],
                  const Divider(height: 24),
                  Row(
                    children: [
                      Text('归属人',
                          style: TextStyle(fontSize: 15, color: AppPalette.textSecondary(context))),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: ownerColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              ownerLabel,
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.bold, color: AppPalette.text(context)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // 操作按钮（从左到右：删除 / 归属 / 修改；AI 自动记账流水额外有「拉黑删」）
          // 「删除」只删除不拉黑（可能有记错的时候）；「拉黑删」= 删除 + 商户拉黑不再自动记账
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _deleteFlow,
                        icon: Icon(Icons.delete_outline, size: 18, color: AppColors.expense),
                        label: const Text('删除', style: TextStyle(color: AppColors.expense)),
                        style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.expense)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _changeAttribution,
                        icon: const Icon(Icons.person_outline, size: 18),
                        label: const Text('归属'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _editFlow,
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('修改'),
                      ),
                    ),
                  ],
                ),
                // _source == 'auto' 时显示 "隐藏 AI 标签"按钮；source 空时显示 "恢复 AI 标签"
                if (f.isAiSource || _source == 'auto') ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _source == 'auto' ? _hideAiTag : _showAiTag,
                      icon: Icon(
                        _source == 'auto' ? Icons.label_off_outlined : Icons.label_outlined,
                        size: 18,
                        color: AppColors.blue,
                      ),
                      label: Text(
                        _source == 'auto'
                            ? '隐藏 AI 标签（清除来源标记，保留流水）'
                            : '恢复 AI 标签（标记为 AI 自动记账）',
                        style: const TextStyle(color: AppColors.blue, fontSize: 13),
                      ),
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.blue)),
                    ),
                  ),
                  // 拉黑删只在有 AI 来源时显示（隐藏后保留该选项，避免 user 困惑）
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _neverAgain,
                      icon: Icon(Icons.block, size: 18, color: AppColors.expense),
                      label: const Text('拉黑删（删除该笔，以后该商户不再自动记账）',
                          style: TextStyle(color: AppColors.expense, fontSize: 13)),
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.expense)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 修改：跳到记账页（编辑模式）
  void _editFlow() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RecordPage(initialFlow: widget.flow)),
    );
    if (mounted) Navigator.pop(context);
  }

  // 归属：弹窗改归属人
  Future<void> _changeAttribution() async {
    final ctrl = TextEditingController(text: widget.flow.attribution);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('更换归属人'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '归属人昵称',
            hintText: '如：老婆 / 老板 / 室友',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (name == null) return;
    try {
      await ref.read(localApiProvider).updateFlow(widget.flow.id, {
        'attribution': name,
        'attribution_uid': null,
      });
      ref.read(dataVersionProvider.notifier).state++;
      toast('归属已更新');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      toast(e.toString().replaceFirst('ApiException: ', ''));
    }
  }

  // 隐藏 AI 标签：清空 source 字段（保留流水，只去掉「AI」标记 + 来源信息）
  Future<void> _hideAiTag() async {
    await _toggleAiSource(toRestore: false);
  }

  // 恢复：把 source 从 '' 改回 'auto'，列表/详情立即显示 AI 标签
  Future<void> _showAiTag() async {
    await _toggleAiSource(toRestore: true);
  }

  Future<void> _toggleAiSource({required bool toRestore}) async {
    try {
      await ref.read(localApiProvider).updateFlow(
        widget.flow.id,
        {"source": toRestore ? "auto" : ""},
      );
      // 关键：通知首页/列表刷新（home_page 监听 dataVersionProvider 自动 _load）
      ref.read(dataVersionProvider.notifier).state++;
      if (mounted) {
        toast(toRestore ? "已恢复 AI 标签" : "已隐藏 AI 标签");
        Navigator.pop(context, true);
      }
    } catch (e) {
      toast(e.toString().replaceFirst('ApiException: ', ''));
    }
  }

  // 拉黑删：AI 自动记账误记时，删除该笔 + 商户加入忽略名单（以后不再自动记账）
  Future<void> _neverAgain() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('拉黑删除这笔？'),
        content: Text('将删除「${widget.flow.description}」这笔流水，'
            '并把该商户拉黑，以后它不会自动记账。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('拉黑删', style: TextStyle(color: AppColors.expense)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await AutoRecordService.instance.addIgnoreMerchant(widget.flow.description);
      await ref.read(localApiProvider).deleteFlow(widget.flow.id);
      ref.read(dataVersionProvider.notifier).state++;
      toast('已拉黑「${widget.flow.description}」，以后不再自动记账');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      toast(e.toString().replaceFirst('ApiException: ', ''));
    }
  }

  // 删除：二次确认后调 deleteFlow
  Future<void> _deleteFlow() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这笔流水？'),
        content: const Text('此操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: AppColors.expense)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(localApiProvider).deleteFlow(widget.flow.id);
      ref.read(dataVersionProvider.notifier).state++;
      toast('已删除');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      toast(e.toString().replaceFirst('ApiException: ', ''));
    }
  }

  Widget _row(String label, String value, {Color? valueColor, Widget? prefix}) {
    return Row(
      children: [
        Text(label,
            style: TextStyle(fontSize: 15, color: AppPalette.textSecondary(context))),
        const SizedBox(width: 16),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (prefix != null) ...[prefix, const SizedBox(width: 6)],
              Flexible(
                child: Text(
                  value,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: valueColor ?? AppPalette.text(context)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _aiTag() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      decoration: BoxDecoration(
        color: AppColors.blue,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text('AI',
          style: TextStyle(
              fontSize: 8, color: AppPalette.onPrimary(context), fontWeight: FontWeight.bold, height: 1.2)),
    );
  }
}
