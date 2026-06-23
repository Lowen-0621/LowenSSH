import 'package:flutter/material.dart';
import '../theme.dart';
import 'top_bar.dart';
import 'status_bar.dart';
import 'left_bar.dart';
import 'right_bar.dart';

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
                // 中栏（批次C 替换为 CenterPanel）
                const Expanded(
                  child: _Placeholder(
                      color: AppColors.base, label: '中栏 · 终端 + 智能体'),
                ),
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

/// 临时占位（中栏 批次C 实现后替换）
class _Placeholder extends StatelessWidget {
  final Color color;
  final String label;
  const _Placeholder({
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: color),
      child: Center(
        child: Text(label,
            style: const TextStyle(color: AppColors.overlay, fontSize: 12)),
      ),
    );
  }
}
