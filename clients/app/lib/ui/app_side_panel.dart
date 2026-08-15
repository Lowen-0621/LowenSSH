import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme.dart';
import 'app_hover_surface.dart';

/// 从左侧工具栏旁滑入的统一功能面板。
///
/// 轻微位移负责表达面板来源，淡入建立空间层级；关闭时反向播放。
Future<T?> showAppSidePanel<T>({
  required BuildContext context,
  required Widget child,
  double width = 520,
  double maxHeight = 640,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: const Color(0xFF15171A).withValues(alpha: .14),
    transitionDuration: AppMotion.panel,
    pageBuilder: (dialogContext, _, _) => SafeArea(
      child: Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(248, 76, 24, 68),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width, maxHeight: maxHeight),
            child: Material(
              color: Colors.transparent,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.large),
                  boxShadow: AppShadows.floating(opacity: .11),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.large),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.mantle.withValues(alpha: .97),
                        border: Border.all(
                          color: AppColors.surface0.withValues(alpha: .92),
                        ),
                      ),
                      child: Stack(
                        children: [
                          Padding(
                            // 给右上角关闭按钮留出独立点击区，避免与标题操作重叠。
                            padding: const EdgeInsets.fromLTRB(20, 20, 52, 20),
                            child: child,
                          ),
                          Positioned(
                            top: 10,
                            right: 10,
                            child: _CloseButton(
                              onTap: () => Navigator.of(dialogContext).pop(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (_, animation, _, child) {
      final curve = CurvedAnimation(
        parent: animation,
        curve: AppMotion.standard,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curve,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(-.035, 0),
            end: Offset.zero,
          ).animate(curve),
          child: child,
        ),
      );
    },
  );
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 30,
    height: 30,
    child: AppHoverSurface(
      onTap: onTap,
      hoverColor: AppColors.text.withValues(alpha: .07),
      borderRadius: BorderRadius.circular(15),
      child: Icon(Icons.close_rounded, size: 16, color: AppColors.subtext),
    ),
  );
}
