import 'package:flutter/material.dart';
import '../theme.dart';

/// 底部状态栏 —— 连接/门禁/SFTP/GLM缓存/上下文/延迟（高 26px）
/// 对应设计稿 .statusbar，等宽字体
class StatusBar extends StatelessWidget {
  const StatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      decoration: const BoxDecoration(
        color: AppColors.crust,
        border: Border(top: BorderSide(color: AppColors.surface0)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: DefaultTextStyle(
        style: const TextStyle(
            fontFamily: kMonoFont, fontSize: 11, color: AppColors.subtext),
        child: Row(
          children: [
            // 连接状态
            _seg([
              _statusDot(AppColors.green),
              const SizedBox(width: 6),
              const Text('web01 已连接', style: TextStyle(color: AppColors.green)),
            ]),
            const SizedBox(width: 16),
            // 门禁
            _seg([
              const Text('门禁 ', style: TextStyle(color: AppColors.overlay)),
              const Text('ON', style: TextStyle(color: AppColors.green)),
              const Text(' · ', style: TextStyle(color: AppColors.overlay)),
              const Text('拦2', style: TextStyle(color: AppColors.red)),
              const Text(' · ', style: TextStyle(color: AppColors.overlay)),
              const Text('待确认1', style: TextStyle(color: AppColors.yellow)),
            ]),
            const SizedBox(width: 16),
            // SFTP 路径
            _seg([
              const Text('SFTP ', style: TextStyle(color: AppColors.overlay)),
              const Text('/var/www', style: TextStyle(color: AppColors.text)),
            ]),
            const Spacer(),
            // GLM 缓存
            _seg([
              const Text('GLM-4.6 ', style: TextStyle(color: AppColors.overlay)),
              const Text('缓存 98%', style: TextStyle(color: AppColors.green)),
            ]),
            const SizedBox(width: 16),
            // 上下文
            _seg([
              const Text('上下文 ', style: TextStyle(color: AppColors.overlay)),
              const Text('12 轮 · 8.2k tok',
                  style: TextStyle(color: AppColors.text)),
            ]),
            const SizedBox(width: 16),
            // 延迟
            _seg([
              const Text('延迟 ', style: TextStyle(color: AppColors.overlay)),
              const Text('42ms', style: TextStyle(color: AppColors.text)),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _seg(List<Widget> children) =>
      Row(mainAxisSize: MainAxisSize.min, children: children);

  Widget _statusDot(Color c) => Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      );
}
