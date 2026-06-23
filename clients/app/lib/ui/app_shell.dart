import 'package:flutter/material.dart';
import '../theme.dart';
import 'top_bar.dart';
import 'status_bar.dart';
import 'left_bar.dart';

/// 应用主骨架 —— 三栏 IDE 布局
/// 纵向：顶栏(38) / 主体(三栏 Row) / 状态栏(26)
/// 主体横向：左栏(232) / 中栏(Expanded) / 右栏(300)
/// 对应设计稿 .window + .body
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.base,
      body: Column(
        children: [
          TopBar(),
          Expanded(
            child: Row(
              children: [
                // 左栏
                LeftBar(),
                // 中栏（批次C 替换为 CenterPanel）
                Expanded(
                  child: _Placeholder(
                      color: AppColors.base, label: '中栏 · 终端 + 智能体'),
                ),
                // 右栏（批次D 替换为 RightBar）
                _Placeholder(
                    width: 300,
                    color: AppColors.mantle,
                    label: '右栏 · 安全 / 文件 / 监控',
                    border:
                        Border(left: BorderSide(color: AppColors.surface0))),
              ],
            ),
          ),
          StatusBar(),
        ],
      ),
    );
  }
}

/// 临时占位（各栏批次实现后替换）
class _Placeholder extends StatelessWidget {
  final double? width;
  final Color color;
  final String label;
  final Border? border;
  const _Placeholder({
    this.width,
    required this.color,
    required this.label,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: BoxDecoration(color: color, border: border),
      child: Center(
        child: Text(label,
            style: const TextStyle(color: AppColors.overlay, fontSize: 12)),
      ),
    );
  }
}
