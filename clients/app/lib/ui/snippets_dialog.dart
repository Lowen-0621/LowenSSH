import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme.dart';
import '../core/snippet_store.dart';
import '../state/snippet_provider.dart';
import '../state/settings_provider.dart';

/// 命令片段对话框 —— 列出预置/自定义片段，点击填进 AI 输入框，支持增删。
Future<void> showSnippetsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: AppColors.mantle,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.surface0),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 560),
        child: const Padding(
          padding: EdgeInsets.all(18),
          child: _SnippetsBody(),
        ),
      ),
    ),
  );
}

class _SnippetsBody extends ConsumerStatefulWidget {
  const _SnippetsBody();

  @override
  ConsumerState<_SnippetsBody> createState() => _SnippetsBodyState();
}

class _SnippetsBodyState extends ConsumerState<_SnippetsBody> {
  bool _adding = false;
  final _labelCtrl = TextEditingController();
  final _cmdCtrl = TextEditingController();

  @override
  void dispose() {
    _labelCtrl.dispose();
    _cmdCtrl.dispose();
    super.dispose();
  }

  void _submitNew() {
    final label = _labelCtrl.text.trim();
    final cmd = _cmdCtrl.text.trim();
    if (cmd.isEmpty) return;
    ref.read(snippetProvider.notifier).add(label.isEmpty ? cmd : label, cmd);
    _labelCtrl.clear();
    _cmdCtrl.clear();
    setState(() => _adding = false);
  }

  @override
  Widget build(BuildContext context) {
    final snippets = ref.watch(snippetProvider);
    final l = ref.watch(l10nProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 标题行
        Row(
          children: [
            const Icon(Icons.content_paste_outlined,
                size: 16, color: AppColors.text),
            const SizedBox(width: 8),
            Text(l.t('snip.title'),
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text)),
            const Spacer(),
            Text(l.t('snip.clickToFill'),
                style: const TextStyle(fontSize: 11, color: AppColors.overlay)),
          ],
        ),
        const SizedBox(height: 12),
        // 片段列表
        Flexible(
          child: snippets.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(l.t('snip.empty'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.overlay)),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: snippets.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 6),
                  itemBuilder: (ctx, i) => _row(snippets[i], i),
                ),
        ),
        const SizedBox(height: 10),
        // 新增区
        if (_adding)
          _addForm()
        else
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _adding = true),
              icon: const Icon(Icons.add, size: 16, color: AppColors.blue),
              label: Text(l.t('snip.addNew'),
                  style: const TextStyle(fontSize: 12, color: AppColors.blue)),
            ),
          ),
      ],
    );
  }

  // 单条片段行：点击填入输入框，右侧删除
  Widget _row(Snippet s, int index) => Container(
        decoration: BoxDecoration(
          color: AppColors.base,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.surface0),
        ),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  // 填进 AI 输入框并关闭对话框
                  ref.read(composerProvider.notifier).fill(s.command);
                  Navigator.of(context).pop();
                },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.label,
                          style: const TextStyle(
                              fontSize: 12.5, color: AppColors.text)),
                      const SizedBox(height: 2),
                      Text(s.command,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontFamily: kMonoFont,
                              fontSize: 11,
                              color: AppColors.overlay)),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 14, color: AppColors.overlay),
              splashRadius: 16,
              onPressed: () => ref.read(snippetProvider.notifier).removeAt(index),
            ),
          ],
        ),
      );

  // 新增表单：名称 + 命令
  Widget _addForm() {
    final l = ref.watch(l10nProvider);
    return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.base,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.surface1),
        ),
        child: Column(
          children: [
            _miniField(_labelCtrl, l.t('snip.nameOpt')),
            const SizedBox(height: 6),
            _miniField(_cmdCtrl, l.t('snip.cmdHint'), mono: true),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => setState(() => _adding = false),
                  child: Text(l.t('common.cancel'),
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.subtext)),
                ),
                const SizedBox(width: 4),
                FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.blue,
                      foregroundColor: AppColors.crust,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8)),
                  onPressed: _submitNew,
                  child: Text(l.t('common.add'),
                      style: const TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      );
  }

  Widget _miniField(TextEditingController c, String hint, {bool mono = false}) =>
      TextField(
        controller: c,
        style: TextStyle(
            fontSize: 12,
            fontFamily: mono ? kMonoFont : null,
            color: AppColors.text),
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          hintStyle: const TextStyle(fontSize: 12, color: AppColors.overlay),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: AppColors.surface1),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: AppColors.surface1),
          ),
        ),
      );
}
