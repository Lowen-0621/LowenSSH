import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/connection_provider.dart';
import '../state/agent_provider.dart';
import '../state/workspace_provider.dart';
import '../theme.dart';
import 'ai_pane.dart';
import 'app_hover_surface.dart';
import 'connection_empty_state.dart';
import 'dialogs.dart';
import 'left_bar.dart';
import 'right_bar.dart';
import 'sftp_view.dart';
import 'status_bar.dart';
import 'terminal_pane.dart';
import 'top_bar.dart';

/// 应用主骨架。
///
/// 未连接时，电影场景铺满窗口底层，顶栏和侧栏只是磨砂覆盖层；连接后场景收敛为
/// 暖灰白工作台，终端与 Agent 同屏，避免在执行任务时来回切换。
class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(workspaceProvider);
    final conn = ref.watch(connectionProvider);
    final immersiveHome = view == WorkspaceView.terminal && !conn.isConnected;

    return Scaffold(
      backgroundColor: AppColors.base,
      body: Stack(
        children: [
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: AppMotion.page,
              switchInCurve: AppMotion.standard,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: immersiveHome
                  ? const ConnectionEmptyState(key: ValueKey('passage-home'))
                  : ColoredBox(
                      key: const ValueKey('workbench-background'),
                      color: AppColors.base,
                    ),
            ),
          ),
          Column(
            children: [
              TopBar(immersive: immersiveHome),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 232,
                      child: LeftBar(immersive: immersiveHome),
                    ),
                    VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: AppColors.surface0.withValues(alpha: .72),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 60),
                        child: AnimatedSwitcher(
                          duration: AppMotion.page,
                          switchInCurve: AppMotion.standard,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, animation) {
                            final curved = CurvedAnimation(
                              parent: animation,
                              curve: AppMotion.standard,
                            );
                            return FadeTransition(
                              opacity: curved,
                              child: child,
                            );
                          },
                          child: _workspace(view, conn),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Positioned(
            left: 270,
            right: 38,
            bottom: 12,
            child: Align(alignment: Alignment.center, child: StatusBar()),
          ),
        ],
      ),
    );
  }

  Widget _workspace(WorkspaceView view, ConnState conn) {
    if (view == WorkspaceView.terminal && !conn.isConnected) {
      return const SizedBox.expand(key: ValueKey('transparent-home-space'));
    }

    return switch (view) {
      WorkspaceView.terminal => const _Workbench(key: ValueKey('workbench')),
      WorkspaceView.sftp => const SftpView(key: ValueKey('sftp')),
      WorkspaceView.agent => const _CenteredPane(
        key: ValueKey('agent'),
        maxWidth: 980,
        child: AiPane(),
      ),
      WorkspaceView.monitor => const _CenteredPane(
        key: ValueKey('monitor'),
        maxWidth: 1080,
        child: RightBar(),
      ),
    };
  }
}

class _Workbench extends StatelessWidget {
  const _Workbench({super.key});

  @override
  Widget build(BuildContext context) => Container(
    color: AppColors.base,
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.large),
        boxShadow: AppShadows.floating(opacity: .06),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.large),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.mantle,
            border: Border.all(color: AppColors.surface0),
          ),
          child: Row(
            children: [
              const Expanded(flex: 58, child: _TerminalSurface()),
              Container(
                width: 1,
                color: AppColors.surface0.withValues(alpha: .82),
              ),
              const Expanded(flex: 42, child: AiPane()),
            ],
          ),
        ),
      ),
    ),
  );
}

class _TerminalSurface extends ConsumerWidget {
  const _TerminalSurface();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conn = ref.watch(connectionProvider);
    final host = conn.host;
    final title = host?.alias?.isNotEmpty == true
        ? host!.alias!
        : host?.host ?? 'Terminal';

    return ColoredBox(
      color: AppColors.crust,
      child: Column(
        children: [
          Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: AppColors.mantle,
              border: Border(bottom: BorderSide(color: AppColors.surface0)),
            ),
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: AppColors.green,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (host != null) ...[
                  const SizedBox(width: 12),
                  Container(width: 1, height: 16, color: AppColors.surface0),
                  const SizedBox(width: 12),
                  Text(
                    '${host.user}@${host.host}',
                    style: TextStyle(
                      color: AppColors.subtext,
                      fontSize: 11.5,
                      fontFamily: kMonoFont,
                    ),
                  ),
                ],
                const Spacer(),
                _HeaderAction(
                  icon: Icons.add_rounded,
                  tooltip: '新建连接',
                  onTap: () => showAddHostDialog(context, ref),
                ),
                const SizedBox(width: 6),
                _DisconnectAction(
                  onTap: () => _confirmDisconnect(context, ref, title),
                ),
              ],
            ),
          ),
          const Expanded(child: TerminalPane()),
        ],
      ),
    );
  }

  Future<void> _confirmDisconnect(
    BuildContext context,
    WidgetRef ref,
    String title,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.mantle,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.large),
          side: BorderSide(color: AppColors.surface0),
        ),
        title: Text(
          '断开 $title？',
          style: TextStyle(
            color: AppColors.text,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          '当前终端会话将关闭，并返回连接主页。正在执行的命令也会随连接中断。',
          style: TextStyle(
            color: AppColors.subtext,
            fontSize: 13,
            height: 1.55,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('取消', style: TextStyle(color: AppColors.subtext)),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.text,
              foregroundColor: AppColors.mantle,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.logout_rounded, size: 16),
            label: const Text('断开并返回'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    ref.read(agentProvider.notifier).newConversation();
    ref.read(connectionProvider.notifier).disconnectAndReturnHome();
    ref.read(workspaceProvider.notifier).select(WorkspaceView.terminal);
  }
}

class _DisconnectAction extends StatelessWidget {
  const _DisconnectAction({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 30,
    child: AppHoverSurface(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      hoverColor: AppColors.red.withValues(alpha: .08),
      border: Border.all(color: AppColors.surface0),
      hoverBorder: Border.all(color: AppColors.red.withValues(alpha: .28)),
      borderRadius: BorderRadius.circular(9),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.logout_rounded, size: 14, color: AppColors.red),
          const SizedBox(width: 6),
          Text(
            '断开',
            style: TextStyle(
              color: AppColors.red,
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    ),
  );
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: SizedBox(
      width: 30,
      height: 30,
      child: AppHoverSurface(
        onTap: onTap,
        hoverColor: AppColors.text.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(9),
        child: Icon(icon, size: 17, color: AppColors.subtext),
      ),
    ),
  );
}

class _CenteredPane extends StatelessWidget {
  const _CenteredPane({super.key, required this.child, required this.maxWidth});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Container(
    color: AppColors.base,
    alignment: Alignment.topCenter,
    padding: const EdgeInsets.fromLTRB(28, 20, 28, 24),
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.large),
          boxShadow: AppShadows.soft(opacity: .04),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.large),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.mantle,
              border: Border.all(color: AppColors.surface0),
            ),
            child: child,
          ),
        ),
      ),
    ),
  );
}
