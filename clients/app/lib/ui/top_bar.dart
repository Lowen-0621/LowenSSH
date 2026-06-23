import 'package:flutter/material.dart';
import '../theme.dart';

/// 顶栏 —— 红绿灯 + Logo + 搜索框 + 操作按钮（高 38px）
/// 对应设计稿 .topbar
class TopBar extends StatelessWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      decoration: const BoxDecoration(
        color: AppColors.mantle,
        border: Border(bottom: BorderSide(color: AppColors.surface0)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          // Logo
          Row(
            children: const [
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
          // 搜索框
          _searchBox(),
          const Spacer(),
          // 操作按钮组
          _actions(),
        ],
      ),
    );
  }

  Widget _searchBox() {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: AppColors.base,
        border: Border.all(color: AppColors.surface0),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Row(
        children: const [
          Text('🔍', style: TextStyle(fontSize: 12)),
          SizedBox(width: 6),
          Text('搜索主机、命令片段…',
              style: TextStyle(color: AppColors.overlay, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _actions() {
    return Row(
      children: [
        _btn(icon: '⚡', label: '连接', primary: true),
        const SizedBox(width: 6),
        _btn(icon: '＋', label: '新建主机'),
        const SizedBox(width: 6),
        _btn(icon: '📁', label: 'SFTP'),
        const SizedBox(width: 6),
        _btn(icon: '⛶', label: '分屏'),
        const SizedBox(width: 6),
        _btn(icon: '⚙'),
      ],
    );
  }

  Widget _btn({required String icon, String? label, bool primary = false}) {
    return Container(
      decoration: BoxDecoration(
        color: primary ? AppColors.blue : AppColors.surface0,
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon, style: const TextStyle(fontSize: 13)),
          if (label != null) ...[
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: primary ? FontWeight.w600 : FontWeight.normal,
                    color: primary ? AppColors.crust : AppColors.text)),
          ],
        ],
      ),
    );
  }
}
