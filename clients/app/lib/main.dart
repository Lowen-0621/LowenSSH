import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'theme.dart';
import 'ui/app_shell.dart';

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
      home: const AppShell(),
    );
  }
}
