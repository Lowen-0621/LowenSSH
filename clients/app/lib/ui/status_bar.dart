import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme.dart';
import '../state/connection_provider.dart';
import '../state/config_provider.dart';
import '../state/guard_provider.dart';
import '../state/agent_provider.dart';
import '../state/settings_provider.dart';
import '../core/i18n.dart';

/// 底部状态栏 —— 连接状态 / 门禁统计 / 模型 / 上下文（高 26px，等宽字体）
/// 数据全部来自真实 provider，无可靠来源的指标不展示（不放假数据）。
class StatusBar extends ConsumerWidget {
  const StatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conn = ref.watch(connectionProvider);
    final guard = ref.watch(guardProvider);
    final llm = ref.watch(configProvider).llm;
    final agent = ref.watch(agentProvider);
    final l = ref.watch(l10nProvider);
    // 上下文轮数：对话流里用户消息条数
    final rounds =
        agent.items.where((i) => i.kind == ChatItemKind.user).length;

    return Container(
      height: 26,
      decoration: BoxDecoration(
        color: AppColors.crust,
        border: Border(top: BorderSide(color: AppColors.surface0)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: DefaultTextStyle(
        style: TextStyle(
            fontFamily: kMonoFont, fontSize: 11, color: AppColors.subtext),
        child: Row(
          children: [
            // 连接状态
            _connSeg(conn, l),
            const SizedBox(width: 16),
            // 门禁：ON + 阻止/待确认实时计数
            _seg([
              Text(l.t('status.guard'),
                  style: TextStyle(color: AppColors.overlay)),
              Text(l.t('status.on'), style: TextStyle(color: AppColors.green)),
              Text(' · ', style: TextStyle(color: AppColors.overlay)),
              Text(l.t('status.blocked', {'n': '${guard.denyCount}'}),
                  style: TextStyle(color: AppColors.red)),
              Text(' · ', style: TextStyle(color: AppColors.overlay)),
              Text(l.t('status.pending', {'n': '${guard.askCount}'}),
                  style: TextStyle(color: AppColors.yellow)),
            ]),
            const Spacer(),
            // 模型
            _seg([
              Text(l.t('status.model'),
                  style: TextStyle(color: AppColors.overlay)),
              Text(llm.model.isEmpty ? l.t('status.notConfigured') : llm.model,
                  style: TextStyle(color: AppColors.text)),
            ]),
            const SizedBox(width: 16),
            // 上下文轮数
            _seg([
              Text(l.t('status.context'),
                  style: TextStyle(color: AppColors.overlay)),
              Text(l.t('status.rounds', {'n': '$rounds'}),
                  style: TextStyle(color: AppColors.text)),
            ]),
          ],
        ),
      ),
    );
  }

  // 连接状态段：已连绿点+主机名 / 未连灰点
  Widget _connSeg(ConnState conn, L10n l) {
    final (Color c, String label) = switch (conn.phase) {
      ConnPhase.connected => (
          AppColors.green,
          '${conn.host?.alias?.isNotEmpty == true ? conn.host!.alias! : conn.host?.host ?? ''} ${l.t('status.connected')}'
        ),
      ConnPhase.connecting => (AppColors.yellow, l.t('status.connecting')),
      ConnPhase.error => (AppColors.red, l.t('status.connFail')),
      _ => (AppColors.overlay, l.t('status.disconnected')),
    };
    return _seg([
      Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(label, style: TextStyle(color: c)),
    ]);
  }

  Widget _seg(List<Widget> children) =>
      Row(mainAxisSize: MainAxisSize.min, children: children);
}
