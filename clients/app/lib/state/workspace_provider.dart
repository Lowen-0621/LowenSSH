import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 主工作区：顶部分段导航只负责切换内容，不参与具体业务状态。
enum WorkspaceView { terminal, sftp, agent, monitor }

class WorkspaceNotifier extends Notifier<WorkspaceView> {
  @override
  WorkspaceView build() => WorkspaceView.terminal;

  void select(WorkspaceView view) => state = view;
}

final workspaceProvider = NotifierProvider<WorkspaceNotifier, WorkspaceView>(
  WorkspaceNotifier.new,
);
