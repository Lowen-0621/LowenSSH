import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'theme.dart';
import 'core/lock_store.dart';
import 'state/agent_provider.dart';
import 'state/connection_provider.dart';
import 'state/settings_provider.dart';
import 'ui/app_shell.dart';
import 'ui/lock_screen.dart';

void main() {
  runApp(const ProviderScope(child: LowenSshApp()));
}

class LowenSshApp extends ConsumerStatefulWidget {
  const LowenSshApp({super.key});

  @override
  ConsumerState<LowenSshApp> createState() => _LowenSshAppState();
}

class _LowenSshAppState extends ConsumerState<LowenSshApp> {
  // 已设主密码时，启动需先解锁；未设则直接进入
  late bool _unlocked = !hasMasterPassword();

  @override
  void initState() {
    super.initState();
    // 连接池 LRU 踢人时跳过「AI 任务正在跑」的主机：注入查询回调，
    // 避免 connectionProvider 反向依赖 agentProvider。
    ref.read(connectionProvider.notifier).isHostBusy =
        (hostId) => ref.read(agentProvider.notifier).isBusy(hostId);
  }

  @override
  Widget build(BuildContext context) {
    // 监听配色变化：themeId 变 → 重建 MaterialApp → buildTheme 读到新 AppColors
    ref.watch(settingsProvider.select((s) => s.themeId));
    return MaterialApp(
      title: 'LowenSSH',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: _unlocked
          ? const AppShell()
          : LockScreen(onUnlocked: () => setState(() => _unlocked = true)),
    );
  }
}
