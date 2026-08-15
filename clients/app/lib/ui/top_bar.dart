import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/search_provider.dart';
import '../state/settings_provider.dart';
import '../state/workspace_provider.dart';
import '../theme.dart';
import 'dialogs.dart';
import 'app_hover_surface.dart';
import 'settings_center.dart';

/// 紧凑顶栏。主页时让场景光线透进来，工作时保持同一套暖灰白材质。
class TopBar extends ConsumerWidget {
  const TopBar({super.key, this.immersive = false});

  final bool immersive;

  @override
  Widget build(BuildContext context, WidgetRef ref) => RepaintBoundary(
    child: Container(
      height: 60,
      padding: const EdgeInsets.only(left: 96, right: 22),
      decoration: BoxDecoration(
        color: immersive
            ? AppColors.mantle.withValues(alpha: .94)
            : AppColors.mantle,
        border: Border(
          bottom: BorderSide(color: AppColors.surface0.withValues(alpha: .72)),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 1050;
          return Row(
            children: [
              const _Brand(),
              const Spacer(),
              const _WorkspaceSwitch(),
              const Spacer(),
              if (!compact) ...[
                SizedBox(width: 276, child: _SearchBox()),
                const SizedBox(width: 12),
              ],
              _FlatAction(
                icon: Icons.add_rounded,
                tooltip: ref.watch(l10nProvider).t('top.newHost'),
                onTap: () => showAddHostDialog(context, ref),
              ),
              const SizedBox(width: 4),
              _FlatAction(
                icon: Icons.settings_outlined,
                tooltip: '设置',
                onTap: () => showSettingsCenter(context),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 142,
    child: Row(
      children: [
        const SizedBox(width: 26, height: 26, child: _BrandMark()),
        const SizedBox(width: 9),
        Text(
          'LowenSSH',
          style: TextStyle(
            color: AppColors.text,
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: -.45,
          ),
        ),
      ],
    ),
  );
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _BrandPainter());
}

class _BrandPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // “远端之门”：克制的建筑拱门轮廓，对应 SSH 通道与主页场景。
    final portal = Paint()
      ..color = AppColors.text
      ..strokeWidth = 1.7
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(5, 22)
      ..lineTo(5, 11)
      ..cubicTo(5, 5.5, 8.6, 3, 13, 3)
      ..cubicTo(17.4, 3, 21, 5.5, 21, 11)
      ..lineTo(21, 22);
    canvas.drawPath(path, portal);
    canvas.drawLine(const Offset(9, 22), const Offset(17, 22), portal);
    canvas.drawLine(
      const Offset(16.8, 7),
      const Offset(16.8, 17.5),
      Paint()
        ..color = AppColors.sapphire
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      const Offset(16.8, 7),
      3.8,
      Paint()..color = AppColors.sapphire.withValues(alpha: .14),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _WorkspaceSwitch extends ConsumerWidget {
  const _WorkspaceSwitch();

  static const _items = [
    (WorkspaceView.terminal, '工作台'),
    (WorkspaceView.sftp, 'SFTP'),
    (WorkspaceView.monitor, '监控'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(workspaceProvider);
    return SizedBox(
      height: 40,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final item in _items)
            _NavItem(
              label: item.$2,
              selected: item.$1 == selected,
              onTap: () => ref.read(workspaceProvider.notifier).select(item.$1),
            ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AppHoverSurface(
    onTap: onTap,
    hoverColor: AppColors.text.withValues(alpha: .045),
    borderRadius: BorderRadius.circular(10),
    child: SizedBox(
      width: label == '工作台' ? 84 : 72,
      height: 40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              color: selected ? AppColors.text : AppColors.subtext,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
          Positioned(
            bottom: 1,
            child: AnimatedContainer(
              duration: AppMotion.switcher,
              curve: AppMotion.standard,
              width: selected ? 20 : 0,
              height: 1.5,
              decoration: BoxDecoration(
                color: AppColors.text,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _SearchBox extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = ref.watch(l10nProvider);
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.mantle.withValues(alpha: .58),
        border: Border.all(color: AppColors.surface0.withValues(alpha: .8)),
        borderRadius: BorderRadius.circular(AppRadius.small),
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 17, color: AppColors.overlay),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              onChanged: (value) =>
                  ref.read(hostSearchProvider.notifier).update(value),
              style: TextStyle(color: AppColors.text, fontSize: 12.5),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: l.t('top.search'),
                hintStyle: TextStyle(color: AppColors.overlay, fontSize: 12.5),
              ),
            ),
          ),
          Text(
            '⌘ K',
            style: TextStyle(color: AppColors.overlay, fontSize: 10.5),
          ),
        ],
      ),
    );
  }
}

class _FlatAction extends StatelessWidget {
  const _FlatAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: SizedBox(
      width: 34,
      height: 34,
      child: AppHoverSurface(
        onTap: onTap,
        hoverColor: AppColors.text.withValues(alpha: .07),
        child: Icon(icon, size: 21, color: AppColors.subtext),
      ),
    ),
  );
}
