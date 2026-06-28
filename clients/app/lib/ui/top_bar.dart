import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme.dart';
import '../state/search_provider.dart';
import '../state/settings_provider.dart';
import '../state/layout_provider.dart';
import 'dialogs.dart';
import 'settings_center.dart';

/// 顶栏 —— Logo + 搜索框 + 操作按钮（高 38px）
/// 对应设计稿 .topbar
class TopBar extends ConsumerWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: AppColors.mantle,
        border: Border(bottom: BorderSide(color: AppColors.surface0)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          // Logo
          Row(
            children: [
              Text('◈', style: TextStyle(color: AppColors.blue, fontSize: 14)),
              SizedBox(width: 5),
              Text('LowenSSH',
                  style: TextStyle(
                      color: AppColors.lavender,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .3)),
            ],
          ),
          const SizedBox(width: 12),
          // 搜索框（弹性占据中间剩余空间，窄窗口下自动收缩，避免溢出）
          Expanded(child: _searchBox(ref)),
          const SizedBox(width: 12),
          // 操作按钮组
          _actions(context, ref),
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
      children: [
        _btn(icon: Icons.bolt, label: l.t('top.connect'), primary: true),
        const SizedBox(width: 6),
        _btn(
            icon: Icons.add,
            label: l.t('top.newHost'),
            onTap: () => showAddHostDialog(context, ref)),
        const SizedBox(width: 6),
        _btn(icon: Icons.folder_outlined, label: 'SFTP'),
        const SizedBox(width: 6),
        _btn(icon: Icons.splitscreen_outlined, label: l.t('top.split')),
        const SizedBox(width: 6),
        // 重置布局：找回被关掉的面板（终端/智能体等）
        _btn(
            icon: Icons.restart_alt,
            label: l.t('top.resetLayout'),
            onTap: () => ref.read(layoutResetProvider.notifier).reset()),
        const SizedBox(width: 6),
        _btn(
            icon: Icons.settings_outlined,
            onTap: () => showSettingsCenter(context)),
      ],
    );
  }

  Widget _btn(
      {required IconData icon,
      String? label,
      bool primary = false,
      VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        decoration: BoxDecoration(
          color: primary ? AppColors.blue : AppColors.surface0,
          borderRadius: BorderRadius.circular(6),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 15, color: primary ? AppColors.crust : AppColors.text),
            if (label != null) ...[
              const SizedBox(width: 5),
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          primary ? FontWeight.w600 : FontWeight.normal,
                      color: primary ? AppColors.crust : AppColors.text)),
            ],
          ],
        ),
      ),
    );
  }
}
