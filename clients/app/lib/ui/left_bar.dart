import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme.dart';
import '../core/config.dart';
import '../state/config_provider.dart';
import '../state/connection_provider.dart';
import 'dialogs.dart';

/// 左栏 —— 主机列表 + 导航链接
/// 对应设计稿 .leftbar。图标统一 Material 线性图标。
/// 主机数据来自 configProvider，点击触发连接。
class LeftBar extends ConsumerWidget {
  const LeftBar({super.key});

  // 导航链接：图标/标题/badge（暂为静态展示项）
  static const _links = [
    (Icons.vpn_key_outlined, '密钥库', '3'),
    (Icons.content_paste_outlined, '命令片段', '12'),
    (Icons.swap_horiz_outlined, '端口转发', null),
    (Icons.shield_outlined, '安全策略', null),
    (Icons.receipt_long_outlined, '审计日志', null),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hosts = ref.watch(hostsProvider);
    final conn = ref.watch(connectionProvider);

    return Container(
      color: AppColors.mantle,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            _navTitle(context, ref, '主机'),
            if (hosts.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(14, 8, 14, 8),
                child: Text('暂无主机，点 + 添加',
                    style: TextStyle(fontSize: 11, color: AppColors.overlay)),
              )
            else
              for (final h in hosts) _hostItem(context, ref, h, conn),
            _divider(),
            for (final l in _links) _navLink(l.$1, l.$2, l.$3),
          ],
        ),
      ),
    );
  }

  // 区块标题（带 + 添加主机）
  Widget _navTitle(BuildContext context, WidgetRef ref, String title) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
        child: Row(
          children: [
            Text(title.toUpperCase(),
                style: const TextStyle(
                    fontSize: 10.5,
                    letterSpacing: 1,
                    color: AppColors.overlay)),
            const Spacer(),
            InkWell(
              onTap: () => showAddHostDialog(context, ref),
              child: const Icon(Icons.add, size: 15, color: AppColors.subtext),
            ),
          ],
        ),
      );

  // 主机条目：点击连接。当前主机左侧蓝条高亮，已连绿点/连接中转圈。
  Widget _hostItem(
      BuildContext context, WidgetRef ref, Host h, ConnState conn) {
    final isCurrent = conn.host?.id == h.id;
    final connected = isCurrent && conn.phase == ConnPhase.connected;
    final connecting = isCurrent && conn.phase == ConnPhase.connecting;
    final name = h.alias?.isNotEmpty == true ? h.alias! : h.host;

    return InkWell(
      onTap: connecting
          ? null
          : () => ref.read(connectionProvider.notifier).connect(h),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 7, 14, 7),
        decoration: BoxDecoration(
          color: isCurrent ? AppColors.base : null,
          border: Border(
            left: BorderSide(
              color: isCurrent ? AppColors.blue : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          children: [
            // 状态：连接中转圈 / 否则绿(已连)灰(未连)点
            if (connecting)
              const SizedBox(
                width: 9,
                height: 9,
                child: CircularProgressIndicator(
                    strokeWidth: 1.5, color: AppColors.blue),
              )
            else
              _onlineDot(connected),
            const SizedBox(width: 9),
            const Icon(Icons.dns_outlined, size: 15, color: AppColors.subtext),
            const SizedBox(width: 8),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.text)),
                  ),
                  const SizedBox(width: 6),
                  Text('${h.host}:${h.port}',
                      style: const TextStyle(
                          fontSize: 10.5, color: AppColors.overlay)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 在线状态点（绿色带辉光 / 灰色）
  Widget _onlineDot(bool online) => Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: online ? AppColors.green : AppColors.overlay,
          shape: BoxShape.circle,
          boxShadow: online
              ? [
                  BoxShadow(
                      color: AppColors.green.withValues(alpha: .6),
                      blurRadius: 6)
                ]
              : null,
        ),
      );

  Widget _divider() => Container(
        height: 1,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        color: AppColors.surface0,
      );

  // 导航链接（图标 + 标题 + 可选 badge）。固定行高，间距统一。
  Widget _navLink(IconData icon, String label, String? badge) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppColors.subtext),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label,
                  style:
                      const TextStyle(fontSize: 13, color: AppColors.subtext)),
            ),
            if (badge != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.surface0,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(badge,
                    style: const TextStyle(
                        fontSize: 10, color: AppColors.subtext)),
              ),
          ],
        ),
      );
}
