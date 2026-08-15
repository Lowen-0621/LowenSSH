import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/i18n.dart';
import '../state/agent_provider.dart';
import '../state/config_provider.dart';
import '../state/connection_provider.dart';
import '../state/guard_provider.dart';
import '../state/settings_provider.dart';
import '../theme.dart';

/// 只展示可验证的运行状态，悬浮在工作区底部，不再占据整条窗口。
class StatusBar extends ConsumerWidget {
  const StatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conn = ref.watch(connectionProvider);
    final guard = ref.watch(guardProvider);
    final llm = ref.watch(configProvider).llm;
    final agent = ref.watch(agentProvider);
    final l = ref.watch(l10nProvider);
    final rounds = agent.items
        .where((item) => item.kind == ChatItemKind.user)
        .length;

    return Container(
      height: 38,
      constraints: const BoxConstraints(maxWidth: 600),
      padding: const EdgeInsets.symmetric(horizontal: 15),
      decoration: BoxDecoration(
        color: AppColors.mantle.withValues(alpha: .94),
        border: Border.all(color: AppColors.surface0),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        boxShadow: AppShadows.soft(opacity: .05),
      ),
      child: DefaultTextStyle(
        style: TextStyle(fontSize: 11.5, color: AppColors.subtext),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _connection(conn, l),
            _divider(),
            Icon(Icons.rule_rounded, size: 15, color: AppColors.green),
            const SizedBox(width: 6),
            Text('${l.t('status.guard')} ${l.t('status.on')}'),
            if (guard.denyCount > 0 || guard.askCount > 0) ...[
              const SizedBox(width: 5),
              Text(
                '${guard.denyCount}/${guard.askCount}',
                style: TextStyle(
                  color: AppColors.yellow,
                  fontFamily: kMonoFont,
                ),
              ),
            ],
            _divider(),
            Icon(Icons.view_in_ar_outlined, size: 14, color: AppColors.overlay),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                llm.model.isEmpty ? l.t('status.notConfigured') : llm.model,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.text),
              ),
            ),
            _divider(),
            Text(
              '${l.t('status.context')} $rounds ${l.t('status.rounds', {'n': ''}).trim()}',
            ),
          ],
        ),
      ),
    );
  }

  Widget _connection(ConnState conn, L10n l) {
    final (color, label) = switch (conn.phase) {
      ConnPhase.connected => (
        AppColors.green,
        conn.host?.alias?.isNotEmpty == true
            ? conn.host!.alias!
            : conn.host?.host ?? '',
      ),
      ConnPhase.connecting => (AppColors.yellow, l.t('status.connecting')),
      ConnPhase.error => (AppColors.red, l.t('status.connFail')),
      _ => (AppColors.overlay, l.t('status.disconnected')),
    };
    return AnimatedSwitcher(
      duration: AppMotion.quick,
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: Row(
        key: ValueKey('${conn.phase}-$label'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(label, style: TextStyle(color: color)),
        ],
      ),
    );
  }

  Widget _divider() => Container(
    width: 1,
    height: 16,
    margin: const EdgeInsets.symmetric(horizontal: 14),
    color: AppColors.surface0,
  );
}
