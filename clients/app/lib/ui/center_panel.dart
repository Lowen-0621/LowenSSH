import 'package:flutter/material.dart';
import '../theme.dart';
import 'terminal_pane.dart';
import 'ai_pane.dart';
import 'sftp_view.dart';

/// 中栏 —— tab 栏 + (终端+AI 分屏 / SFTP 双栏) 视图切换
/// 对应设计稿 .center。点 tab 在 split 与 sftp 视图间切换。
class CenterPanel extends StatefulWidget {
  const CenterPanel({super.key});

  @override
  State<CenterPanel> createState() => _CenterPanelState();
}

class _CenterPanelState extends State<CenterPanel> {
  // 当前视图：split（终端+AI）/ sftp（文件管理器）
  String _view = 'split';

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.base,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _tabBar(),
          Expanded(
            child: _view == 'sftp'
                ? const SftpView()
                : Row(
                    children: const [
                      Expanded(child: TerminalPane()),
                      Expanded(child: AiPane()),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // tab 栏：web01(split) / SFTP·web01(sftp) / db01 + 右侧分屏标记
  Widget _tabBar() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.mantle,
        border: Border(bottom: BorderSide(color: AppColors.surface0)),
      ),
      child: Row(
        children: [
          _tab('split', '▸', 'web01', closable: true),
          _tab('sftp', '📁', 'SFTP · web01', closable: true),
          _tab(null, '▸', 'db01', closable: true),
          const Spacer(),
          // 分屏布局标记
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('⛶ 终端 + 智能体',
                style: TextStyle(fontSize: 12, color: AppColors.subtext)),
          ),
        ],
      ),
    );
  }

  // 单个 tab。view 为 null 表示该 tab 不参与视图切换（仅展示）
  Widget _tab(String? view, String icon, String label,
      {bool closable = false}) {
    final active = view != null && _view == view;
    return GestureDetector(
      onTap: view == null ? null : () => setState(() => _view = view),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.base : null,
          border: const Border(
            right: BorderSide(color: AppColors.surface0),
          ),
        ),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 7),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: active ? AppColors.text : AppColors.subtext)),
            if (closable) ...[
              const SizedBox(width: 4),
              const Text('✕',
                  style: TextStyle(fontSize: 12, color: AppColors.overlay)),
            ],
          ],
        ),
      ),
    );
  }
}
