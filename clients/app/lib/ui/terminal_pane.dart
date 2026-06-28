import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart' hide CursorStyle;
import 'package:dartssh2/dartssh2.dart';
import '../theme.dart';
import '../core/ssh.dart';
import '../core/settings_store.dart';
import '../state/connection_provider.dart';
import '../state/settings_provider.dart';

/// 一台主机的终端会话：独立的 xterm 缓冲 + PTY shell + 选区控制器。
/// 按主机保活，切主机切显示对应 Terminal，旧的 PTY 留在后台不断。
class _TermSession {
  final Terminal terminal = Terminal(maxLines: 5000);
  final TerminalController controller = TerminalController();
  SSHSession? shell;
  bool starting = false;
  VoidCallback? _selListener;

  /// 选中自动复制（Linux 终端风格）：选区变化且非空 → 写入系统剪贴板。
  /// 受设置控制，可动态开关。
  void setAutoCopy(bool on) {
    if (on && _selListener == null) {
      _selListener = () {
        final sel = controller.selection;
        if (sel == null) return;
        // buffer 可能尚未布局完成，getText 越界会抛异常，包一层防御
        try {
          final text = terminal.buffer.getText(sel);
          if (text.trim().isNotEmpty) {
            Clipboard.setData(ClipboardData(text: text));
          }
        } catch (_) {
          // 选区超出当前 buffer 范围，忽略本次复制
        }
      };
      controller.addListener(_selListener!);
    } else if (!on && _selListener != null) {
      controller.removeListener(_selListener!);
      _selListener = null;
    }
  }

  void dispose() {
    if (_selListener != null) controller.removeListener(_selListener!);
    controller.dispose();
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

  /// 右键：把剪贴板内容写进 shell（桌面终端常见的粘贴交互）
  Future<void> _paste(_TermSession s) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.isNotEmpty) {
      s.shell?.write(utf8.encode(text));
    }
  }

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
      unawaited(_clearShellWhenDone(s, session));
      session.stdout
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(s.terminal.write);
      session.stderr
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(s.terminal.write);
    } catch (e) {
      s.shell = null;
      final err = e.toString();
      if (!client.isConnected() || err.contains('Transport is closed')) {
        ref.read(connectionProvider.notifier).markConnectionLost(hostId, e);
      }
      final l = ref.read(l10nProvider);
      s.terminal.write('\r\n${l.t('term.startFail', {'err': '$e'})}\r\n');
    } finally {
      s.starting = false;
    }
  }

  Future<void> _clearShellWhenDone(
      _TermSession s, SSHSession session) async {
    try {
      await session.done;
    } catch (_) {
      // Transport errors are reflected through connectionProvider.
    }
    if (mounted && identical(s.shell, session)) {
      s.shell = null;
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
    final cfg = ref.watch(settingsProvider); // 终端设置
    final l = ref.watch(l10nProvider);
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
        child: Text(l.t('term.connectFirst'),
            style: TextStyle(fontSize: 12, color: AppColors.overlay)),
      );
    }

    // 当前主机：没 shell 就开一个（按主机隔离，互不影响）
    final s = _sessionFor(hostId);
    if (s.shell == null && !s.starting) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _startShell(hostId, conn.client!));
    }
    // 按设置同步「选中即复制」开关
    s.setAutoCopy(cfg.selectToCopy);

    // 光标样式映射
    final cursorType = switch (cfg.cursorStyle) {
      CursorStyle.underline => TerminalCursorType.underline,
      CursorStyle.bar => TerminalCursorType.verticalBar,
      _ => TerminalCursorType.block,
    };

    return Container(
      color: AppColors.crust,
      child: TerminalView(
        s.terminal,
        controller: s.controller,
        // 右键粘贴：按设置开关
        onSecondaryTapDown:
            cfg.rightClickPaste ? (details, offset) => _paste(s) : null,
        cursorType: cursorType,
        // alwaysShowCursor=true 即不闪烁；闪烁则 false
        alwaysShowCursor: !cfg.cursorBlink,
        textStyle: TerminalStyle(
          fontSize: cfg.termFontSize,
          fontFamily: kMonoFont,
        ),
        theme: _termTheme,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
    );
  }
}

/// 终端配色 —— getter（非 const 全局），随当前主题 AppColors 实时重算，
/// 切换配色后终端区域颜色立即跟随。
TerminalTheme get _termTheme => TerminalTheme(
  cursor: AppColors.text,
  // 选区半透明，选中后文字仍可读（原来不透明的灰会盖住文字）
  selection: AppColors.surface2.withValues(alpha: .45),
  foreground: AppColors.text,
  background: AppColors.crust,
  black: AppColors.surface1,
  red: AppColors.red,
  green: AppColors.green,
  yellow: AppColors.yellow,
  blue: AppColors.blue,
  magenta: AppColors.pink,
  cyan: AppColors.sapphire,
  white: AppColors.text,
  brightBlack: AppColors.overlay,
  brightRed: AppColors.red,
  brightGreen: AppColors.green,
  brightYellow: AppColors.yellow,
  brightBlue: AppColors.blue,
  brightMagenta: AppColors.mauve,
  brightCyan: AppColors.sapphire,
  brightWhite: AppColors.text,
  searchHitBackground: AppColors.yellow,
  searchHitBackgroundCurrent: AppColors.peach,
  searchHitForeground: AppColors.crust,
);
