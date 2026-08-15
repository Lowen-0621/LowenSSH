import 'package:flutter/material.dart';

import '../theme.dart';

/// LowenSSH 统一悬停交互。
///
/// 外层命中区域始终固定，悬停只连续插值背景与边框。
///
/// 不做位移、缩放或阴影，避免鼠标进入/离开时出现二次明暗变化。
class AppHoverSurface extends StatefulWidget {
  const AppHoverSurface({
    super.key,
    required this.child,
    required this.onTap,
    this.padding = EdgeInsets.zero,
    this.color = Colors.transparent,
    this.hoverColor,
    this.pressedColor,
    this.borderRadius = const BorderRadius.all(Radius.circular(10)),
    this.border,
    this.hoverBorder,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color color;

  /// 叠加在基础颜色上的悬停状态层，而不是目标背景色。
  final Color? hoverColor;
  final Color? pressedColor;
  final BorderRadius borderRadius;
  final Border? border;
  final Border? hoverBorder;
  final bool enabled;

  @override
  State<AppHoverSurface> createState() => _AppHoverSurfaceState();
}

class _AppHoverSurfaceState extends State<AppHoverSurface>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.hover,
    reverseDuration: AppMotion.hoverExit,
  );
  bool _pressed = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: MouseRegion(
      cursor: widget.enabled && widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) {
        if (widget.enabled) _controller.forward();
      },
      onExit: (_) => _controller.reverse(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.enabled ? widget.onTap : null,
        onTapDown: widget.enabled
            ? (_) => setState(() => _pressed = true)
            : null,
        onTapUp: widget.enabled
            ? (_) => setState(() => _pressed = false)
            : null,
        onTapCancel: widget.enabled
            ? () => setState(() => _pressed = false)
            : null,
        child: AnimatedBuilder(
          animation: _controller,
          child: Padding(padding: widget.padding, child: widget.child),
          builder: (context, child) {
            final value = _controller.value;
            final hoverColor =
                widget.hoverColor ?? AppColors.text.withValues(alpha: .065);
            final pressedColor =
                widget.pressedColor ?? AppColors.text.withValues(alpha: .115);
            final stateLayer = _pressed
                ? pressedColor
                : Color.lerp(Colors.transparent, hoverColor, value)!;
            return DecoratedBox(
              decoration: BoxDecoration(
                color: Color.alphaBlend(stateLayer, widget.color),
                borderRadius: widget.borderRadius,
                border: Border.lerp(
                  widget.border,
                  widget.hoverBorder ?? widget.border,
                  value,
                ),
              ),
              child: child,
            );
          },
        ),
      ),
    ),
  );
}
