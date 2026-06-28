import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 布局重置信号 —— 每次自增触发 AppShell 重建默认布局。
/// 用途：用户关掉某个面板(终端/智能体等)后，可一键找回，避免面板永久消失。
class LayoutResetNotifier extends Notifier<int> {
  @override
  int build() => 0;

  /// 触发一次重置（恢复所有面板到默认布局）
  void reset() => state++;
}

final layoutResetProvider =
    NotifierProvider<LayoutResetNotifier, int>(LayoutResetNotifier.new);
