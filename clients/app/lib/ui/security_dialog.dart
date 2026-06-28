import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme.dart';
import '../core/guard.dart';
import '../state/guard_provider.dart';
import '../state/settings_provider.dart';

/// 安全策略对话框 —— 完整列出门禁规则（deny/ask）+ 实时三态统计。
/// 纯展示，规则来自 core/guard.dart，与实际判定同源。
Future<void> showSecurityDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: AppColors.mantle,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.surface0),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: const Padding(
          padding: EdgeInsets.all(18),
          child: _SecurityBody(),
        ),
      ),
    ),
  );
}

class _SecurityBody extends ConsumerWidget {
  const _SecurityBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(guardProvider);
    final l = ref.watch(l10nProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 标题
        Row(
          children: [
            const Icon(Icons.shield_outlined, size: 16, color: AppColors.text),
            const SizedBox(width: 8),
            Text(l.t('sec.title'),
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text)),
            const SizedBox(width: 8),
            Text(l.t('sec.subtitle'),
                style: const TextStyle(fontSize: 11, color: AppColors.overlay)),
          ],
        ),
        const SizedBox(height: 12),
        // 三态统计卡（真实数据）
        Row(
          children: [
            _stat('${stats.denyCount}', l.t('state.denied'), AppColors.red),
            const SizedBox(width: 8),
            _stat('${stats.askCount}', l.t('state.ask'), AppColors.yellow),
            const SizedBox(width: 8),
            _stat('${stats.allowCount}', l.t('state.allowed'), AppColors.green),
          ],
        ),
        const SizedBox(height: 8),
        // 说明：判定原理
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.base,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
              '${l.t('sec.principle1')}${l.t('sec.principle2')}',
              style: const TextStyle(
                  fontSize: 10.5, height: 1.5, color: AppColors.subtext)),
        ),
        const SizedBox(height: 12),
        // 规则列表
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              _sectionTitle(
                  l.t('sec.denySection', {'n': '${denyRules.length}'}),
                  AppColors.red),
              for (final r in denyRules) _ruleRow(r),
              const SizedBox(height: 10),
              _sectionTitle(
                  l.t('sec.askSection', {'n': '${askRules.length}'}),
                  AppColors.yellow),
              for (final r in askRules) _ruleRow(r),
              const SizedBox(height: 10),
              _sectionTitle(l.t('sec.allowSection'), AppColors.green),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                child: Text(l.t('sec.allowDesc'),
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.overlay)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // 三态统计卡
  Widget _stat(String num, String label, Color color) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.surface0),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Text(num,
                  style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: color)),
              const SizedBox(height: 2),
              Text(label,
                  style:
                      const TextStyle(fontSize: 10, color: AppColors.overlay)),
            ],
          ),
        ),
      );

  Widget _sectionTitle(String text, Color color) => Padding(
        padding: const EdgeInsets.only(bottom: 6, top: 2),
        child: Row(
          children: [
            Container(width: 3, height: 12, color: color),
            const SizedBox(width: 7),
            Text(text,
                style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text)),
          ],
        ),
      );

  // 单条规则：tag + 正则 + 中文说明
  Widget _ruleRow(GuardRule r) {
    final (Color c, String text) = switch (r.level) {
      Decision.deny => (AppColors.red, 'DENY'),
      Decision.ask => (AppColors.yellow, 'ASK'),
      Decision.allow => (AppColors.green, 'ALLOW'),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.base,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: c.withValues(alpha: .18),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(text,
                style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .5,
                    color: c)),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.pattern,
                    style: const TextStyle(
                        fontFamily: kMonoFont,
                        fontSize: 11,
                        color: AppColors.peach)),
                const SizedBox(height: 2),
                Text(r.desc,
                    style: const TextStyle(
                        fontSize: 10.5, color: AppColors.subtext)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
