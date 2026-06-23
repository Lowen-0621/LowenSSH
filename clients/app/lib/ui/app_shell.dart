import 'package:flutter/material.dart';
import 'package:docking/docking.dart';
import '../theme.dart';
import 'top_bar.dart';
import 'status_bar.dart';
import 'left_bar.dart';
import 'right_bar.dart';
import 'center_panel.dart';

/// 应用主骨架 —— 顶栏 + 可停靠区(VS Code 式) + 状态栏
/// 三大栏(主机/会话/面板)各为 DockingItem，可拖拽改宽、合并成 tab、分屏。
/// 顶栏下方整块交给 Docking，左栏因此自然顶起。
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
    // 初始布局：左(主机) | 中(会话) | 右(面板) 横排
    _layout = DockingLayout(
      root: DockingRow([
        DockingItem(
          name: '主机',
          widget: const LeftBar(),
          weight: 0.18,
          closable: false,
          keepAlive: true,
        ),
        DockingItem(
          name: '会话',
          widget: const CenterPanel(),
          weight: 0.60,
          closable: false,
          keepAlive: true,
        ),
        DockingItem(
          name: '面板',
          widget: const RightBar(),
          weight: 0.22,
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
              child: Docking(layout: _layout),
            ),
          ),
          const StatusBar(),
        ],
      ),
    );
  }
}
