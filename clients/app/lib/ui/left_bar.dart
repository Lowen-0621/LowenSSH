import 'package:flutter/material.dart';
import '../theme.dart';

/// 主机条目占位 model（Step 4 替换为 core/config.dart 的 HostEntry）
class _Host {
  final String name;
  final String addr;
  final bool online;
  final String osIcon;
  final bool active;
  const _Host(this.name, this.addr, this.online, this.osIcon,
      {this.active = false});
}

/// 主机分组占位 model
class _Group {
  final String label;
  final List<_Host> hosts;
  const _Group(this.label, this.hosts);
}

/// 左栏 —— 主机分组树 + 导航链接（宽 232px）
/// 对应设计稿 .leftbar
class LeftBar extends StatelessWidget {
  const LeftBar({super.key});

  // 静态占位数据（Step 4 接 provider）
  static const _groups = [
    _Group('生产组', [
      _Host('web01', '10.0.1.21', true, '🐧', active: true),
      _Host('web02', '10.0.1.22', true, '🐧'),
      _Host('db01', '10.0.1.30', false, '🐧'),
    ]),
    _Group('测试组', [
      _Host('win-test', '10.0.2.5', false, '🪟'),
    ]),
  ];

  // 导航链接：图标/标题/badge
  static const _links = [
    ('🔑', '密钥库', '3'),
    ('📋', '命令片段', '12'),
    ('🔀', '端口转发', null),
    ('🛡️', '安全策略', null),
    ('📜', '审计日志', null),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.mantle,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            _navTitle('主机'),
            for (final g in _groups) ...[
              _groupLabel(g.label),
              for (final h in g.hosts) _hostItem(h),
            ],
            _divider(),
            for (final l in _links) _navLink(l.$1, l.$2, l.$3),
          ],
        ),
      ),
    );
  }

  // 区块标题（带 + 添加）
  Widget _navTitle(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
        child: Row(
          children: [
            Text(title.toUpperCase(),
                style: const TextStyle(
                    fontSize: 10.5,
                    letterSpacing: 1,
                    color: AppColors.overlay)),
            const Spacer(),
            const Text('＋',
                style: TextStyle(fontSize: 14, color: AppColors.subtext)),
          ],
        ),
      );

  // 分组折叠标签
  Widget _groupLabel(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 5, 14, 5),
        child: Row(
          children: [
            const Text('▾',
                style: TextStyle(fontSize: 9, color: AppColors.overlay)),
            const SizedBox(width: 6),
            Text(label,
                style:
                    const TextStyle(fontSize: 11, color: AppColors.subtext)),
          ],
        ),
      );

  // 主机条目（在线点 + OS图标 + 名称 + 地址，active 左边蓝条高亮）
  Widget _hostItem(_Host h) => Container(
        padding: const EdgeInsets.fromLTRB(30, 6, 14, 6),
        decoration: BoxDecoration(
          color: h.active ? AppColors.base : null,
          border: Border(
            left: BorderSide(
              color: h.active ? AppColors.blue : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          children: [
            _onlineDot(h.online),
            const SizedBox(width: 8),
            Text(h.osIcon, style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 8),
            Expanded(
              child: Row(
                children: [
                  Text(h.name,
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.text)),
                  const SizedBox(width: 6),
                  Text(h.addr,
                      style: const TextStyle(
                          fontSize: 10.5, color: AppColors.overlay)),
                ],
              ),
            ),
          ],
        ),
      );

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

  // 导航链接（图标 + 标题 + 可选 badge）
  Widget _navLink(String icon, String label, String? badge) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        child: Row(
          children: [
            SizedBox(
                width: 16,
                child: Text(icon,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13))),
            const SizedBox(width: 9),
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
