import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:docking/docking.dart';
import '../theme.dart';
import '../core/i18n.dart';
import '../state/settings_provider.dart';
import '../state/layout_provider.dart';
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
  int _builtResetTick = 0; // 上次构建时的重置计数，变化则重建

  // 按当前语言构建布局。语言切换时重建（会重置拖拽布局，低频可接受）。
  DockingLayout _buildLayout(L10n l) {
    return DockingLayout(
      root: DockingRow([
        // 左：主机树
        DockingItem(
          name: l.t('panel.hosts'),
          widget: const LeftBar(),
          weight: 0.17,
          minimalSize: 200, // 防拖到过窄导致内容溢出
          closable: false,
          keepAlive: true,
        ),
        // 中：终端与 SFTP 合并成 tab 组
        DockingTabs([
          DockingItem(
            name: '${l.t('panel.terminal')} · web01',
            widget: const TerminalPane(),
            minimalSize: 200,
            keepAlive: true,
          ),
          DockingItem(
            name: 'SFTP · web01',
            widget: const SftpView(),
            minimalSize: 200,
            keepAlive: true,
          ),
        ], weight: 0.32),
        // 中右：智能体（独立面板，可拖动）
        DockingItem(
          name: l.t('panel.agent'),
          widget: const AiPane(),
          weight: 0.30,
          minimalSize: 240, // 智能体内含输入框+多按钮，留宽一点
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
      ]),
    );
  }

  @override
  void dispose() {
    _layout?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 监听语言 + 布局重置信号：任一变化都重建 layout
    final lang = ref.watch(settingsProvider.select((s) => s.lang));
    final resetTick = ref.watch(layoutResetProvider);
    final l = ref.watch(l10nProvider);
    if (_layout == null || _builtLang != lang || _builtResetTick != resetTick) {
      _layout?.dispose();
      _layout = _buildLayout(l);
      _builtLang = lang;
      _builtResetTick = resetTick;
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
                  child: Docking(layout: _layout),
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
