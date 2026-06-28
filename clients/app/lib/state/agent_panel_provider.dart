import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 智能体面板显隐状态 —— 仿 VSCode 插件：顶栏图标开/关，× 关闭。
/// 默认隐藏（false），用户点顶栏图标显示。
class AgentPanelNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void show() => state = true;
  void hide() => state = false;
  void toggle() => state = !state;
}

final agentPanelProvider =
    NotifierProvider<AgentPanelNotifier, bool>(AgentPanelNotifier.new);
