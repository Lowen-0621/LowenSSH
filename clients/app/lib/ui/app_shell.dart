import 'package:flutter/material.dart';
import 'package:docking/docking.dart';
import '../theme.dart';
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
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late final DockingLayout _layout;

  @override
  void initState() {
    super.initState();
    // 初始布局：主机 | (终端/SFTP tab 组 + 智能体) | 侧面板
    _layout = DockingLayout(
      root: DockingRow([
        // 左：主机树
        DockingItem(
          name: '主机',
          widget: const LeftBar(),
          weight: 0.17,
          closable: false,
          keepAlive: true,
        ),
        // 中：终端与 SFTP 合并成 tab 组
        DockingTabs([
          DockingItem(
            name: '终端 · web01',
            widget: const TerminalPane(),
            keepAlive: true,
          ),
          DockingItem(
            name: 'SFTP · web01',
            widget: const SftpView(),
            keepAlive: true,
          ),
        ], weight: 0.32),
        // 中右：智能体（独立面板，可拖动）
        DockingItem(
          name: '智能体 · GLM-4.6',
          widget: const AiPane(),
          weight: 0.30,
          keepAlive: true,
        ),
        // 右：安全/文件/监控侧面板
        DockingItem(
          name: '面板',
          widget: const RightBar(),
          weight: 0.21,
          closable: false,
          keepAlive: true,
        ),
      ]),
    );
  }

  @override
  void dispose() {
    _layout.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
