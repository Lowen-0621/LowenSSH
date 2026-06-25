import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';
import 'package:dartssh2/dartssh2.dart';
import '../theme.dart';
import '../state/connection_provider.dart';

/// 终端面板 —— 真交互终端（xterm 接 SSH shell channel）。
/// 已连接时开一个 PTY shell，用户可手敲命令；未连接显示占位。
/// 与 agent 的 exec 各走独立 channel，互不干扰。
class TerminalPane extends ConsumerStatefulWidget {
  const TerminalPane({super.key});

  @override
  ConsumerState<TerminalPane> createState() => _TerminalPaneState();
}

class _TerminalPaneState extends ConsumerState<TerminalPane> {
  late final Terminal _terminal = Terminal(maxLines: 5000);
  SSHSession? _session;
  String? _boundHostId; // 当前已绑定 shell 的主机 id，避免重复开
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    // 用户键盘输入 → 写进 SSH shell 的 stdin
    _terminal.onOutput = (data) {
      _session?.write(utf8.encode(data));
    };
    // 终端尺寸变化 → 通知远端 PTY 重设窗口大小
    _terminal.onResize = (w, h, pw, ph) {
      _session?.resizeTerminal(w, h, pw, ph);
    };
  }

  /// 为当前连接开一个交互 shell，把 SSH stdout/stderr 灌进终端显示。
  Future<void> _startShell(ConnState conn) async {
    if (_starting) return;
    _starting = true;
    try {
      final client = conn.client!;
      final session = await client.shell(
        width: _terminal.viewWidth,
        height: _terminal.viewHeight,
      );
      _session = session;
      _boundHostId = conn.host?.id;
      // 远端输出 → 终端
      session.stdout
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(_terminal.write);
      session.stderr
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(_terminal.write);
    } catch (e) {
      _terminal.write('\r\n[终端启动失败: $e]\r\n');
    } finally {
      _starting = false;
    }
  }

  /// 断开时清掉 shell 会话
  void _teardown() {
    _session?.close();
    _session = null;
    _boundHostId = null;
  }

  @override
  void dispose() {
    _session?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final conn = ref.watch(connectionProvider);

    // 连接状态驱动 shell 生命周期：
    // - 已连接且主机变了/未绑定 → 开新 shell
    // - 断开/出错 → 拆掉
    if (conn.isConnected && conn.host?.id != _boundHostId && !_starting) {
      _teardown();
      WidgetsBinding.instance.addPostFrameCallback((_) => _startShell(conn));
    } else if (!conn.isConnected && _boundHostId != null) {
      _teardown();
    }

    if (!conn.isConnected) {
      return Container(
        color: AppColors.crust,
        alignment: Alignment.center,
        child: const Text('连接主机后可在此使用交互式终端',
            style: TextStyle(fontSize: 12, color: AppColors.overlay)),
      );
    }

    return Container(
      color: AppColors.crust,
      child: TerminalView(
        _terminal,
        textStyle: const TerminalStyle(
          fontSize: 12.5,
          fontFamily: kMonoFont,
        ),
        theme: _termTheme,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
    );
  }
}

/// 终端配色（贴近 Catppuccin Mocha）
const TerminalTheme _termTheme = TerminalTheme(
  cursor: AppColors.text,
  selection: AppColors.surface1,
  foreground: AppColors.text,
  background: AppColors.crust,
  black: Color(0xFF45475A),
  red: AppColors.red,
  green: AppColors.green,
  yellow: AppColors.yellow,
  blue: AppColors.blue,
  magenta: Color(0xFFF5C2E7),
  cyan: AppColors.sapphire,
  white: AppColors.text,
  brightBlack: AppColors.overlay,
  brightRed: AppColors.red,
  brightGreen: AppColors.green,
  brightYellow: AppColors.yellow,
  brightBlue: AppColors.blue,
  brightMagenta: Color(0xFFF5C2E7),
  brightCyan: AppColors.sapphire,
  brightWhite: Colors.white,
  searchHitBackground: AppColors.yellow,
  searchHitBackgroundCurrent: AppColors.peach,
  searchHitForeground: AppColors.crust,
);
