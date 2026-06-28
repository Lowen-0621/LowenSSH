import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:docking/docking.dart';
import '../theme.dart';
import '../core/i18n.dart';
import '../state/settings_provider.dart';
import '../state/agent_panel_provider.dart';
import 'top_bar.dart';
import 'status_bar.dart';
import 'left_bar.dart';
import 'right_bar.dart';
import 'terminal_pane.dart';
import 'ai_pane.dart';
import 'sftp_view.dart';
import 'dock_theme.dart';

/// 应用主骨架 —— 顶栏 + 可停靠区(VS Code 式) + 状态栏
/// 所有面板(主机/终端/SFTP/智能体/侧面板)均为独立 DockingItem，
/// 可自由拖拽、合并成 tab、分屏。顶栏下方整块交给 Docking，左栏因此自然顶起。
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  DockingLayout? _layout;
  AppLang? _builtLang; // 上次构建 layout 用的语言，变化则重建
  bool _builtAgentVisible = false; // 上次构建时智能体是否可见，变化则重建

  // 按当前语言构建布局。语言切换时重建（会重置拖拽布局，低频可接受）。
  // agentVisible 控制智能体面板是否加入布局（仿 VSCode 插件显隐）。
  DockingLayout _buildLayout(L10n l, bool agentVisible) {
    final items = <DockingArea>[
      // 左：主机树
      DockingItem(
        name: l.t('panel.hosts'),
        widget: const LeftBar(),
        weight: 0.17,
        minimalSize: 200, // 防拖到过窄导致内容溢出
        closable: false,
        keepAlive: true,
      ),
      // 中：终端与 SFTP 合并成 tab 组（不可关闭）
      DockingTabs([
        DockingItem(
          id: 'terminal',
          name: l.t('panel.terminal'),
          widget: const TerminalPane(),
          minimalSize: 200,
          closable: false,
          keepAlive: true,
        ),
        DockingItem(
          id: 'sftp',
          name: 'SFTP',
          widget: const SftpView(),
          minimalSize: 200,
          closable: false,
          keepAlive: true,
        ),
      ], weight: agentVisible ? 0.32 : 0.55),
      // 中右：智能体（仅在显示时加入，× 关闭走 agentPanelProvider.hide）
      if (agentVisible)
        DockingItem(
          name: l.t('panel.agent'),
          widget: const AiPane(),
          weight: 0.30,
          minimalSize: 240, // 智能体内含输入框+多按钮，留宽一点
          closable: false, // 关闭走面板内 × 按钮，不用 docking 自带关闭
          keepAlive: true,
        ),
      // 右：安全/文件/监控侧面板
      DockingItem(
        name: l.t('panel.side'),
        widget: const RightBar(),
        weight: 0.21,
        minimalSize: 220,
        closable: false,
        keepAlive: true,
      ),
    ];
    return DockingLayout(root: DockingRow(items));
  }

  // 判断某 tab 组是否为终端/SFTP 组（组内含 id=='terminal' 的项）
  bool _isTerminalGroup(DockingTabs tabs) {
    for (var i = 0; i < tabs.childrenCount; i++) {
      if (tabs.childAt(i).id == 'terminal') return true;
    }
    return false;
  }

  @override
  void dispose() {
    _layout?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 监听语言 + 智能体显隐：任一变化都重建 layout
    final lang = ref.watch(settingsProvider.select((s) => s.lang));
    final agentVisible = ref.watch(agentPanelProvider);
    final l = ref.watch(l10nProvider);
    if (_layout == null ||
        _builtLang != lang ||
        _builtAgentVisible != agentVisible) {
      _layout?.dispose();
      _layout = _buildLayout(l, agentVisible);
      _builtLang = lang;
      _builtAgentVisible = agentVisible;
    }
    return Scaffold(
      backgroundColor: AppColors.base,
      body: Column(
        children: [
          const TopBar(),
          Expanded(
            child: DockingTheme(
              data: DockingThemeData(),
              // tab 栏样式
              child: TabbedViewTheme(
                data: buildTabbedTheme(),
                // 分隔条样式（docking 内部 MultiSplitView 从 context 取）
                child: MultiSplitViewTheme(
                  data: buildSplitTheme(),
                  // 关掉三个最大化入口（去掉 tab 上的最大化方块按钮）
                  child: Docking(
                    layout: _layout,
                    maximizableItem: false,
                    maximizableTab: false,
                    maximizableTabsArea: false,
                    // 终端/SFTP tab 组右侧放「打开智能体」按钮；
                    // 智能体已展开时不显示（此时由智能体面板自己的顶栏控制）。
                    dockingButtonsBuilder: (ctx, tabs, item) {
                      if (agentVisible) return [];
                      if (tabs == null || !_isTerminalGroup(tabs)) return [];
                      return [
                        TabButton(
                          icon: IconProvider.data(Icons.auto_awesome),
                          toolTip: l.t('panel.agent'),
                          color: AppColors.subtext,
                          onPressed: () =>
                              ref.read(agentPanelProvider.notifier).show(),
                        ),
                      ];
                    },
                  ),
                ),
              ),
            ),
          ),
          const StatusBar(),
        ],
      ),
    );
  }
}
