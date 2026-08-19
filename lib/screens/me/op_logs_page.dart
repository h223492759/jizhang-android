import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jizhang_android/core/db.dart';
import 'package:jizhang_android/core/local_first_api.dart';
import 'package:jizhang_android/core/sync_engine.dart';
import 'package:jizhang_android/core/storage.dart';
import 'package:jizhang_android/core/theme.dart';
import 'package:jizhang_android/core/util.dart';
import 'package:jizhang_android/state/session.dart';

/// 操作日志页：本地操作记录（含失败/待同步状态）+ 服务器审计日志
class OpLogsPage extends ConsumerStatefulWidget {
  const OpLogsPage({super.key});
  @override
  ConsumerState<OpLogsPage> createState() => _OpLogsPageState();
}

class _OpLogsPageState extends ConsumerState<OpLogsPage> {
  int _tab = 0;
  List<Map<String, Object?>> _local = [];
  List<Map<String, dynamic>> _remote = [];
  bool _loading = true;
  int _pending = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final bookId = await Storage.getBookId() ?? 0;
    _local = await LocalDb.instance.listOpLogs(bookId);
    _pending = await LocalDb.instance.pendingOutboxCount();
    if (_tab == 1) {
      try {
        _remote = await ref.read(localApiProvider).getOpLogs();
      } catch (_) {
        _remote = [];
        if (mounted) toast('获取服务器日志失败（可能离线）');
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _syncNow() async {
    final bookId = await Storage.getBookId();
    if (bookId == null) return;
    final ok = await SyncEngine.instance.syncNow(bookId);
    if (ok) {
      ref.read(dataVersionProvider.notifier).state++;
      toast('同步完成');
      await _load();
    } else {
      toast('离线或同步失败，本地数据仍可正常使用');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('操作日志'),
        actions: [
          TextButton.icon(
            onPressed: _syncNow,
            icon: const Icon(Icons.sync, size: 18),
            label: const Text('立即同步'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_pending > 0)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '有 $_pending 项操作待同步，联网后自动补传（重复补传不会产生重复数据）',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
          Row(
            children: [
              _tabBtn(0, '本地操作'),
              _tabBtn(1, '服务器审计'),
            ],
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _tab == 0 ? _localList() : _remoteList(),
          ),
        ],
      ),
    );
  }

  Widget _tabBtn(int i, String label) {
    final active = _tab == i;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() => _tab = i);
          _load();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: active ? AppColors.primaryDark : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
              color: active ? AppColors.primaryDark : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _localList() {
    if (_local.isEmpty) {
      return const Center(
          child: Text('暂无操作记录', style: TextStyle(color: AppColors.textSecondary)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _local.length,
      itemBuilder: (_, i) {
        final r = _local[i];
        final status = (r['status'] as String?) ?? 'ok';
        final op = (r['op'] as String?) ?? '';
        final summary = (r['summary'] as String?) ?? '';
        final ts = (r['ts'] as String?) ?? '';
        final color = status == 'ok'
            ? AppColors.income
            : status == 'queued'
                ? AppColors.expense
                : AppColors.expense;
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            dense: true,
            leading: Icon(
              status == 'ok'
                  ? Icons.check_circle_outline
                  : status == 'queued'
                      ? Icons.schedule
                      : Icons.error_outline,
              size: 20,
              color: color,
            ),
            title: Text('$op  $summary',
                style: const TextStyle(fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            subtitle: Text(
              '${_fmtTs(ts)} · ${status == 'ok' ? '已同步' : status == 'queued' ? '待同步' : '失败'}',
              style: const TextStyle(fontSize: 11),
            ),
          ),
        );
      },
    );
  }

  Widget _remoteList() {
    if (_remote.isEmpty) {
      return const Center(
          child: Text('暂无服务器日志', style: TextStyle(color: AppColors.textSecondary)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _remote.length,
      itemBuilder: (_, i) {
        final r = _remote[i];
        final status = (r['status'] as num?)?.toInt() ?? 0;
        final ok = status < 400;
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            dense: true,
            leading: Icon(
              ok ? Icons.check_circle_outline : Icons.error_outline,
              size: 20,
              color: ok ? AppColors.income : AppColors.expense,
            ),
            title: Text(
              '${r['method']} ${r['path']}  ${r['summary'] ?? ''}',
              style: const TextStyle(fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${(r['created_at'] ?? '').toString()} · HTTP $status',
              style: const TextStyle(fontSize: 11),
            ),
          ),
        );
      },
    );
  }

  String _fmtTs(String iso) {
    final t = DateTime.tryParse(iso);
    if (t == null) return iso;
    return '${t.month}月${t.day}日 ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }
}
