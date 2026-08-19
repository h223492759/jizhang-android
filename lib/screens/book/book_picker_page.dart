import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jizhang_android/core/theme.dart';
import 'package:jizhang_android/core/util.dart';
import 'package:jizhang_android/state/session.dart';
import 'package:jizhang_android/core/local_first_api.dart';

class BookPickerPage extends ConsumerStatefulWidget {
  const BookPickerPage({super.key});
  @override
  ConsumerState<BookPickerPage> createState() => _BookPickerPageState();
}

class _BookPickerPageState extends ConsumerState<BookPickerPage> {
  bool _loading = false;

  Future<void> _select(int id) async {
    await ref.read(sessionProvider.notifier).selectBook(id);
    // RootRouter 会自动进入主界面
  }

  Future<void> _create() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建账本'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: '账本名称', border: OutlineInputBorder()),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    setState(() => _loading = true);
    try {
      await ref.read(localApiProvider).createBook(name);
      await ref.read(sessionProvider.notifier).refreshBooks();
      final books = ref.read(sessionProvider).books;
      final created = books.firstWhere((b) => b.name == name, orElse: () => books.last);
      await _select(created.id);
    } catch (e) {
      toast(e.toString().replaceFirst('ApiException: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final books = ref.watch(sessionProvider).books;
    return Scaffold(
      appBar: AppBar(title: const Text('选择账本')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('我的账本', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ...books.map((b) => Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.primarySoft,
                    child: Icon(Icons.book, color: AppColors.primaryDark),
                  ),
                  title: Text(b.name),
                  subtitle: Text('${b.members} 人 · ${b.flows} 笔'),
                  trailing: b.role == 'owner' ? const Text('拥有者') : const Text('成员'),
                  onTap: () => _select(b.id),
                ),
              )),
          if (books.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('还没有账本，点击下方按钮新建', textAlign: TextAlign.center),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _loading ? null : _create,
        child: const Icon(Icons.add),
      ),
    );
  }
}
