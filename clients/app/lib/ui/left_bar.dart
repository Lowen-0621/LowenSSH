import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme.dart';
import '../core/config.dart';
import '../state/config_provider.dart';
import '../state/connection_provider.dart';
import '../state/guard_provider.dart';
import '../state/search_provider.dart';
import '../state/snippet_provider.dart';
import 'dialogs.dart';
import 'snippets_dialog.dart';
import 'audit_dialog.dart';
import 'security_dialog.dart';

/// 左栏 —— 主机列表 + 导航链接
/// 对应设计稿 .leftbar。图标统一 Material 线性图标。
/// 主机数据来自 configProvider，点击触发连接。
class LeftBar extends ConsumerWidget {
  const LeftBar({super.key});

  // 导航链接：图标/标题/badge。命令片段、审计日志、安全策略为真实功能，其余暂为装饰。
  static const _decorLinks = [
    (Icons.vpn_key_outlined, '密钥库', '3'),
    (Icons.swap_horiz_outlined, '端口转发', null),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allHosts = ref.watch(hostsProvider);
    final conn = ref.watch(connectionProvider);
    final query = ref.watch(hostSearchProvider).trim().toLowerCase();
    // 按搜索词过滤：匹配别名或主机地址
    final hosts = query.isEmpty
        ? allHosts
        : allHosts
            .where((h) =>
                (h.alias ?? '').toLowerCase().contains(query) ||
                h.host.toLowerCase().contains(query))
            .toList();

    return Container(
      color: AppColors.mantle,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            _navTitle(context, ref, '主机'),
            if (hosts.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                child: Text(
                    query.isEmpty ? '暂无主机，点 + 添加' : '未找到匹配「$query」的主机',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.overlay)),
              )
            else
              for (final h in hosts) _hostItem(context, ref, h, conn),
            // 连接错误显示（定位失败原因）
            if (conn.phase == ConnPhase.error && conn.error != null)
              Container(
                margin: const EdgeInsets.fromLTRB(14, 4, 14, 4),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.red.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('连接失败：${conn.error}',
                    style: const TextStyle(
                        fontSize: 10.5, color: AppColors.red)),
              ),
            _divider(),
            // 命令片段：真实功能，点击弹片段面板，badge 显示真实数量
            _navLink(Icons.content_paste_outlined, '命令片段',
                '${ref.watch(snippetProvider).length}',
                onTap: () => showSnippetsDialog(context)),
            for (final l in _decorLinks) _navLink(l.$1, l.$2, l.$3),
            // 安全策略：真实功能，点击弹策略面板，badge 显示累计拦截数（deny+ask）
            _navLink(Icons.shield_outlined, '安全策略',
                _guardBadge(ref),
                onTap: () => showSecurityDialog(context)),
            // 审计日志：真实功能，点击弹审计面板，badge 显示总条数
            _navLink(Icons.receipt_long_outlined, '审计日志',
                '${ref.watch(auditProvider).length}',
                onTap: () => showAuditDialog(context)),
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

  // 主机条目：点击连接。当前主机左侧蓝条高亮，已连绿点/连接中转圈。右键删除。
  Widget _hostItem(
      BuildContext context, WidgetRef ref, Host h, ConnState conn) {
    final isCurrent = conn.host?.id == h.id;
    // 多连接并存：已连接看整池 connectedIds，不只看当前主机
    final connected = conn.connectedIds.contains(h.id);
    final connecting = isCurrent && conn.phase == ConnPhase.connecting;
    final failed = isCurrent && conn.phase == ConnPhase.error;
    final name = h.alias?.isNotEmpty == true ? h.alias! : h.host;

    return GestureDetector(
      // 右键弹出删除菜单（桌面交互习惯）
      onSecondaryTapDown: (d) =>
          _showHostMenu(context, ref, h, d.globalPosition),
      child: InkWell(
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
              // 状态：连接中转圈 / error红点 / 已连绿点 / 未连灰点
              if (connecting)
                const SizedBox(
                  width: 9,
                  height: 9,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.5, color: AppColors.blue),
                )
              else if (failed)
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                      color: AppColors.red, shape: BoxShape.circle),
                )
              else
                _onlineDot(connected),
              const SizedBox(width: 9),
              const Icon(Icons.dns_outlined,
                  size: 15, color: AppColors.subtext),
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
                    // IP:端口 也用 Flexible+省略，避免主机名+IP 过长时 Row 溢出
                    Flexible(
                      child: Text('${h.host}:${h.port}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 10.5, color: AppColors.overlay)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 主机右键菜单：目前仅删除
  void _showHostMenu(
      BuildContext context, WidgetRef ref, Host h, Offset pos) {
    showMenu<String>(
      context: context,
      color: AppColors.mantle,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: const [
        PopupMenuItem(
          value: 'delete',
          height: 36,
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 15, color: AppColors.red),
              SizedBox(width: 8),
              Text('删除主机',
                  style: TextStyle(fontSize: 13, color: AppColors.text)),
            ],
          ),
        ),
      ],
    ).then((v) {
      if (v == 'delete' && context.mounted) {
        _confirmDelete(context, ref, h);
      }
    });
  }

  // 删除确认。若正连着这台，先断开再删。
  void _confirmDelete(BuildContext context, WidgetRef ref, Host h) {
    final name = h.alias?.isNotEmpty == true ? h.alias! : h.host;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.mantle,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: AppColors.surface0),
        ),
        title: const Text('删除主机',
            style: TextStyle(fontSize: 15, color: AppColors.text)),
        content: Text('确定删除「$name」（${h.host}:${h.port}）？此操作不可撤销。',
            style: const TextStyle(fontSize: 13, color: AppColors.subtext)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消',
                style: TextStyle(color: AppColors.subtext)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.red,
                foregroundColor: AppColors.crust),
            onPressed: () {
              // 正连着这台就先断开，避免操作已删主机
              final conn = ref.read(connectionProvider);
              if (conn.host?.id == h.id) {
                ref.read(connectionProvider.notifier).disconnect();
              }
              ref.read(configProvider.notifier).deleteHost(h.id);
              Navigator.pop(ctx);
            },
            child: const Text('删除'),
          ),
        ],
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

  // 安全策略 badge：累计拦截数（deny+ask），为 0 时不显示
  String? _guardBadge(WidgetRef ref) {
    final s = ref.watch(guardProvider);
    final n = s.denyCount + s.askCount;
    return n > 0 ? '$n' : null;
  }

  // 导航链接（图标 + 标题 + 可选 badge）。传 onTap 则可点击。
  Widget _navLink(IconData icon, String label, String? badge,
          {VoidCallback? onTap}) =>
      InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(
            children: [
              Icon(icon, size: 16, color: AppColors.subtext),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.subtext)),
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
        ),
      );
}
