import 'package:flutter/material.dart';
import '../theme.dart';
import 'top_bar.dart';
import 'status_bar.dart';
import 'left_bar.dart';
import 'right_bar.dart';
import 'center_panel.dart';

/// 应用主骨架 —— 三栏 IDE 布局
/// 纵向：顶栏(38) / 主体(三栏 Row) / 状态栏(26)
/// 主体横向：左栏(232) / 中栏(Expanded) / 右栏(300)
/// 对应设计稿 .window + .body
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.base,
      body: Column(
        children: [
          const TopBar(),
          Expanded(
            child: Row(
              children: [
                // 左栏
                const LeftBar(),
                // 中栏
                const Expanded(child: CenterPanel()),
                // 右栏
                const RightBar(),
              ],
            ),
          ),
          const StatusBar(),
        ],
      ),
    );
  }
}
