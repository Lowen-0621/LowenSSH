/// 本地端口转发 —— 把本地端口的连接通过 SSH 隧道转发到远端地址。
/// 等价于 `ssh -L localPort:remoteHost:remotePort`。
///
/// 生命周期重点（防泄漏）：
///  1. 一条隧道 = 一个本地 ServerSocket + N 条活动 SSH 转发 channel。
///  2. 每个进来的本地连接开一条 forwardLocal channel，双向 pipe。
///  3. 任一端关闭/出错都要拆掉配对的另一端，避免半开连接和 channel 泄漏。
///  4. stop() 关 ServerSocket 并销毁所有活动连接。
library;

import 'dart:async';
import 'dart:io';
import 'package:dartssh2/dartssh2.dart';
import 'ssh.dart';

/// 一条运行中的隧道句柄。持有本地监听 socket 与所有活动转发连接。
class ForwardTunnel {
  final int localPort;
  final String remoteHost;
  final int remotePort;

  final ServerSocket _server;
  // 活动的本地 socket 集合，stop 时统一销毁
  final Set<Socket> _activeSockets = {};
  bool _closed = false;

  ForwardTunnel._(
    this._server, {
    required this.localPort,
    required this.remoteHost,
    required this.remotePort,
  });

  /// 起一条本地端口转发隧道。绑定 127.0.0.1 仅本机可访问（安全：不暴露到局域网）。
  static Future<ForwardTunnel> start(
    SshClient ssh, {
    required int localPort,
    required String remoteHost,
    required int remotePort,
  }) async {
    final server = await ServerSocket.bind('127.0.0.1', localPort);
    final tunnel = ForwardTunnel._(
      server,
      localPort: localPort,
      remoteHost: remoteHost,
      remotePort: remotePort,
    );
    // 监听本地连接，每个连接开一条 SSH 转发 channel
    server.listen(
      (socket) => tunnel._handle(ssh, socket),
      onError: (_) {}, // 监听出错不抛，避免 zone 未捕获
      cancelOnError: false,
    );
    return tunnel;
  }

  // 处理单个本地连接：开转发 channel 并双向 pipe
  Future<void> _handle(SshClient ssh, Socket socket) async {
    if (_closed) {
      socket.destroy();
      return;
    }
    _activeSockets.add(socket);
    SSHForwardChannel? channel;
    try {
      channel = await ssh.forwardLocal(remoteHost, remotePort);
    } catch (_) {
      // 开 channel 失败（如连接已断），直接断掉本地连接
      _activeSockets.remove(socket);
      socket.destroy();
      return;
    }

    // 远端 → 本地
    final remoteSub = channel.stream.listen(
      (data) {
        try {
          socket.add(data);
        } catch (_) {}
      },
      onError: (_) => socket.destroy(),
      onDone: () => socket.destroy(),
      cancelOnError: false,
    );

    // 本地 → 远端
    socket.listen(
      (data) {
        try {
          channel!.sink.add(data);
        } catch (_) {}
      },
      onError: (_) {
        remoteSub.cancel();
        channel?.close();
      },
      onDone: () {
        remoteSub.cancel();
        channel?.close();
      },
      cancelOnError: false,
    );

    // 本地 socket 彻底关闭后从活动集合移除
    socket.done.whenComplete(() {
      _activeSockets.remove(socket);
    });
  }

  /// 关闭隧道：停止监听 + 销毁所有活动连接
  Future<void> stop() async {
    if (_closed) return;
    _closed = true;
    await _server.close();
    for (final s in _activeSockets.toList()) {
      s.destroy();
    }
    _activeSockets.clear();
  }
}
