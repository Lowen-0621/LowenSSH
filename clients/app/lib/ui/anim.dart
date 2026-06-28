import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 可复用动画封装 —— 集中放置入场/转场动画，避免散落各处。
/// 全部基于 Flutter 自带能力（AnimationController/AnimatedBuilder），不引第三方库。

/// 淡入 + 轻微上移入场。常用于卡片、表单区块。
/// [delay] 用于错峰（stagger）：多个元素依次延迟入场。
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final Duration delay;
  final double offsetY; // 起始下移量(px)，向上滑入

  const FadeSlideIn({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 420),
    this.delay = Duration.zero,
    this.offsetY = 16,
  });

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.duration);
  late final Animation<double> _t =
      CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    // 延迟启动以实现错峰入场
    if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      builder: (_, child) => Opacity(
        opacity: _t.value,
        child: Transform.translate(
          offset: Offset(0, widget.offsetY * (1 - _t.value)),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// 模糊浮现入场（blur-in）—— 从高斯模糊+透明到清晰，用于品牌/标题区。
class BlurIn extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final Duration delay;
  final double sigma; // 起始模糊强度

  const BlurIn({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 600),
    this.delay = Duration.zero,
    this.sigma = 10,
  });

  @override
  State<BlurIn> createState() => _BlurInState();
}

class _BlurInState extends State<BlurIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.duration);
  late final Animation<double> _t =
      CurvedAnimation(parent: _c, curve: Curves.easeOut);

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      builder: (_, child) {
        // sigma 必须 >0，收尾时给极小值避免无效滤镜
        final s = math.max(0.01, widget.sigma * (1 - _t.value));
        return Opacity(
          opacity: _t.value,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: s, sigmaY: s),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// 左右抖动（shake）—— 用于错误反馈（如密码输入错误）。
/// 每次 [trigger] 计数器变化触发一次阻尼抖动。
class Shake extends StatefulWidget {
  final Widget child;
  final int trigger; // 每次 +1 触发一次抖动
  final double amplitude; // 起始抖动幅度(px)

  const Shake({
    super.key,
    required this.child,
    required this.trigger,
    this.amplitude = 8,
  });

  @override
  State<Shake> createState() => _ShakeState();
}

class _ShakeState extends State<Shake>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 420));

  @override
  void didUpdateWidget(covariant Shake old) {
    super.didUpdateWidget(old);
    if (widget.trigger != old.trigger) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) {
        // 阻尼正弦：振幅随进度衰减，来回 3 次后归位
        final dx = widget.amplitude *
            (1 - _c.value) *
            math.sin(_c.value * 3 * 2 * math.pi);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: widget.child,
    );
  }
}
