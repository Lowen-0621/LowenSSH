import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme.dart';
import '../state/search_provider.dart';
import '../state/settings_provider.dart';
import 'dialogs.dart';
import 'settings_center.dart';

/// 顶栏 —— 搜索框 + 操作按钮
/// macOS 下标题栏透明、内容顶到最上方，故左侧留出红绿灯位置。
class TopBar extends ConsumerWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: AppColors.mantle,
        border: Border(bottom: BorderSide(color: AppColors.surface0)),
      ),
      // 左侧 78px 给 macOS 红绿灯让位
      padding: const EdgeInsets.only(left: 78, right: 12),
      // Stack 垂直居中所有内容；搜索框水平绝对居中，按钮组固定右侧
      child: Stack(
        children: [
          // 搜索框：相对顶栏正中
          Align(
            alignment: Alignment.center,
            child: SizedBox(width: 360, child: _searchBox(ref)),
          ),
          // 操作按钮组：右侧，垂直居中
          Align(
            alignment: Alignment.centerRight,
            child: _actions(context, ref),
          ),
        ],
      ),
    );
  }

  Widget _searchBox(WidgetRef ref) {
    final l = ref.watch(l10nProvider);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.base,
        border: Border.all(color: AppColors.surface0),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Row(
        children: [
          Icon(Icons.search, size: 15, color: AppColors.overlay),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              onChanged: (v) =>
                  ref.read(hostSearchProvider.notifier).update(v),
              style: TextStyle(color: AppColors.text, fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 6),
                hintText: l.t('top.search'),
                hintStyle: TextStyle(
                    color: AppColors.overlay, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actions(BuildContext context, WidgetRef ref) {
    final l = ref.watch(l10nProvider);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _TopBarButton(
            icon: Icons.add,
            label: l.t('top.newHost'),
            onTap: () => showAddHostDialog(context, ref)),
        const SizedBox(width: 6),
        _TopBarButton(
            icon: Icons.settings_outlined,
            onTap: () => showSettingsCenter(context)),
      ],
    );
  }
}

/// 顶栏按钮 —— 悬停高亮 + 手型光标（桌面端手感）
class _TopBarButton extends StatefulWidget {
  const _TopBarButton({required this.icon, this.label, this.onTap});

  final IconData icon;
  final String? label;
  final VoidCallback? onTap;

  @override
  State<_TopBarButton> createState() => _TopBarButtonState();
}

class _TopBarButtonState extends State<_TopBarButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    // 悬停时背景从 surface0 提亮到 surface1
    final Color bg = _hover ? AppColors.surface1 : AppColors.surface0;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 15, color: AppColors.text),
              if (widget.label != null) ...[
                const SizedBox(width: 5),
                Text(widget.label!,
                    style: TextStyle(fontSize: 12, color: AppColors.text)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
