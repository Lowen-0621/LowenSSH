import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';
import 'package:dartssh2/dartssh2.dart';
import '../theme.dart';
import '../core/ssh.dart';
import '../state/connection_provider.dart';

/// 一台主机的终端会话：独立的 xterm 缓冲 + PTY shell。
/// 按主机保活，切主机切显示对应 Terminal，旧的 PTY 留在后台不断。
class _TermSession {
  final Terminal terminal = Terminal(maxLines: 5000);
  SSHSession? shell;
  bool starting = false;

  void dispose() {
    shell?.close();
    shell = null;
  }
}

/// 终端面板 —— 真交互终端（xterm 接 SSH shell channel）。
/// 多主机各自保活一个 shell：切主机切显示对应终端，历史与会话不丢。
/// 与 agent 的 exec 各走独立 channel，互不干扰。
class TerminalPane extends ConsumerStatefulWidget {
  const TerminalPane({super.key});

  @override
  ConsumerState<TerminalPane> createState() => _TerminalPaneState();
}

class _TerminalPaneState extends ConsumerState<TerminalPane> {
  // 每台主机一个终端会话，按 hostId 保活
  final Map<String, _TermSession> _sessions = {};

  /// 取/建某主机的终端会话，并绑定键盘输入 → shell stdin
  _TermSession _sessionFor(String hostId) =>
      _sessions.putIfAbsent(hostId, () {
        final s = _TermSession();
        s.terminal.onOutput = (data) => s.shell?.write(utf8.encode(data));
        s.terminal.onResize =
            (w, h, pw, ph) => s.shell?.resizeTerminal(w, h, pw, ph);
        return s;
      });

  /// 为指定主机开交互 shell，把 SSH stdout/stderr 灌进它的终端
  Future<void> _startShell(String hostId, SshClient client) async {
    final s = _sessionFor(hostId);
    if (s.starting || s.shell != null) return;
    s.starting = true;
    try {
      final session = await client.shell(
        width: s.terminal.viewWidth,
        height: s.terminal.viewHeight,
      );
      s.shell = session;
      session.stdout
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(s.terminal.write);
      session.stderr
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(s.terminal.write);
    } catch (e) {
      s.terminal.write('\r\n[终端启动失败: $e]\r\n');
    } finally {
      s.starting = false;
    }
  }

  @override
  void dispose() {
    for (final s in _sessions.values) {
      s.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final conn = ref.watch(connectionProvider);
    final hostId = conn.host?.id;

    // 池里已不存在的主机（被 LRU 踢掉/断开），清理其终端会话
    _sessions.keys
        .where((id) => !conn.connectedIds.contains(id))
        .toList()
        .forEach((id) {
      _sessions.remove(id)?.dispose();
    });

    if (!conn.isConnected || hostId == null) {
      return Container(
        color: AppColors.crust,
        alignment: Alignment.center,
        child: const Text('连接主机后可在此使用交互式终端',
            style: TextStyle(fontSize: 12, color: AppColors.overlay)),
      );
    }

    // 当前主机：没 shell 就开一个（按主机隔离，互不影响）
    final s = _sessionFor(hostId);
    if (s.shell == null && !s.starting) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _startShell(hostId, conn.client!));
    }

    return Container(
      color: AppColors.crust,
      child: TerminalView(
        s.terminal,
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
