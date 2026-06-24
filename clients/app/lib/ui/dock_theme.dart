import 'package:flutter/material.dart';
import 'package:docking/docking.dart';
import '../theme.dart';

/// VS Code 风格的 dock 主题 —— 扁平、细线、无圆角
/// 统一 tab 栏(tabbed_view) 与 分隔条(multi_split_view) 视觉。

/// tab 主题：扁平 tab，选中态顶部 2px 蓝线，内容区无边框
TabbedViewThemeData buildTabbedTheme() {
  final theme = TabbedViewThemeData();

  // tab 栏整体
  theme.tabsArea
    ..color = AppColors.mantle
    ..border = const Border(
        bottom: BorderSide(color: AppColors.surface0)) // 底部一条细分隔
    ..initialGap = 0
    ..middleGap = 0;

  // 单个 tab：无圆角无边框，紧凑
  theme.tab
    ..textStyle = const TextStyle(fontSize: 12, color: AppColors.subtext)
    ..padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 8)
    ..decoration = const BoxDecoration(color: AppColors.mantle)
    ..normalButtonColor = AppColors.overlay
    ..hoverButtonColor = AppColors.text;

  // 选中态：背景提亮 + 顶部 2px 蓝线（VS Code 活动 tab 标志）
  theme.tab.selectedStatus
    ..fontColor = AppColors.text
    ..decoration = const BoxDecoration(
      color: AppColors.base,
      border: Border(top: BorderSide(color: AppColors.blue, width: 2)),
    );

  // hover 态：轻微提亮
  theme.tab.highlightedStatus.decoration =
      const BoxDecoration(color: AppColors.surface0);

  // 内容区：去掉默认粗边框
  theme.contentArea.decoration = const BoxDecoration(color: AppColors.base);

  return theme;
}

/// 分隔条主题：VS Code 式 sash —— 平时 1px 浅灰细线，hover 变蓝
MultiSplitViewThemeData buildSplitTheme() {
  return MultiSplitViewThemeData(
    dividerThickness: 1, // 1px 细线，不糊
    dividerPainter: DividerPainters.background(
      color: AppColors.surface0, // 平时：浅灰细线（可见但低调）
      highlightedColor: AppColors.blue, // hover/拖拽：蓝色高亮
    ),
  );
}
