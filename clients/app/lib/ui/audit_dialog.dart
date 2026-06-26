import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme.dart';
import '../core/audit_store.dart';
import '../state/guard_provider.dart';

/// 审计日志对话框 —— 全局命令审计列表，支持按决策筛选 + 清空。
Future<void> showAuditDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: AppColors.mantle,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.surface0),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 600),
        child: const Padding(
          padding: EdgeInsets.all(18),
          child: _AuditBody(),
        ),
      ),
    ),
  );
}

class _AuditBody extends ConsumerStatefulWidget {
  const _AuditBody();

  @override
  ConsumerState<_AuditBody> createState() => _AuditBodyState();
}

class _AuditBodyState extends ConsumerState<_AuditBody> {
  String _filter = 'all'; // all / deny / ask / allow

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(auditProvider);
    final list = _filter == 'all'
        ? all
        : all.where((e) => e.decision == _filter).toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 标题 + 清空
        Row(
          children: [
            const Icon(Icons.receipt_long_outlined,
                size: 16, color: AppColors.text),
            const SizedBox(width: 8),
            const Text('审计日志',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text)),
            const SizedBox(width: 8),
            Text('共 ${all.length} 条',
                style: const TextStyle(fontSize: 11, color: AppColors.overlay)),
            const Spacer(),
            if (all.isNotEmpty)
              TextButton(
                onPressed: () => ref.read(auditProvider.notifier).clear(),
                child: const Text('清空',
                    style: TextStyle(fontSize: 12, color: AppColors.red)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        // 筛选标签
        Row(
          children: [
            _chip('all', '全部'),
            _chip('deny', '已阻止'),
            _chip('ask', '待确认'),
            _chip('allow', '已放行'),
          ],
        ),
        const SizedBox(height: 12),
        // 列表
        Flexible(
          child: list.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 30),
                  child: Text('暂无审计记录',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 12, color: AppColors.overlay)),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: list.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 5),
                  itemBuilder: (ctx, i) => _row(list[i]),
                ),
        ),
      ],
    );
  }

  Widget _chip(String id, String label) {
    final active = _filter == id;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _filter = id),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          decoration: BoxDecoration(
            color: active ? AppColors.surface1 : AppColors.base,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: active ? AppColors.blue : AppColors.surface0),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 11.5,
                  color: active ? AppColors.text : AppColors.subtext)),
        ),
      ),
    );
  }

  // 决策对应的标记色
  Color _color(String d) => switch (d) {
        'deny' => AppColors.red,
        'ask' => AppColors.yellow,
        _ => AppColors.green,
      };
  String _label(String d) => switch (d) {
        'deny' => 'DENY',
        'ask' => 'ASK',
        _ => 'ALLOW',
      };

  Widget _row(AuditEntry e) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.base,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.surface0),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 决策徽标
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _color(e.decision).withValues(alpha: .15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(_label(e.decision),
                  style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                      color: _color(e.decision))),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.command,
                      style: const TextStyle(
                          fontFamily: kMonoFont,
                          fontSize: 11.5,
                          color: AppColors.text)),
                  const SizedBox(height: 2),
                  Text('${e.host} · ${_fmtTime(e.time)}${e.executed ? '' : ' · 未执行'}',
                      style: const TextStyle(
                          fontSize: 10, color: AppColors.overlay)),
                ],
              ),
            ),
          ],
        ),
      );

  static String _fmtTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }
}
