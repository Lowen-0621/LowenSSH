import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'theme.dart';
import 'state/agent_provider.dart';
import 'state/connection_provider.dart';
import 'ui/app_shell.dart';

void main() {
  runApp(const ProviderScope(child: LowenSshApp()));
}

class LowenSshApp extends ConsumerStatefulWidget {
  const LowenSshApp({super.key});

  @override
  ConsumerState<LowenSshApp> createState() => _LowenSshAppState();
}

class _LowenSshAppState extends ConsumerState<LowenSshApp> {
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
    return MaterialApp(
      title: 'LowenSSH',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const AppShell(),
    );
  }
}
