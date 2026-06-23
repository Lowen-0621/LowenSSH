import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'theme.dart';

void main() {
  runApp(const ProviderScope(child: LowenSshApp()));
}

class LowenSshApp extends StatelessWidget {
  const LowenSshApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LowenSSH',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const _Placeholder(),
    );
  }
}

/// 临时占位页 —— Step 1 仅验证脚手架可编译运行
/// Step 3 会替换为设计稿的三栏 IDE 布局
class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('◈', style: TextStyle(fontSize: 48, color: AppColors.blue)),
            const SizedBox(height: 12),
            const Text('LowenSSH',
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppColors.lavender)),
            const SizedBox(height: 8),
            Text('App 端脚手架就绪',
                style: TextStyle(color: AppColors.subtext, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
