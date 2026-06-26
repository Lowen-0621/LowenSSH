/// SSH 客户端 —— 一个实例持有一个长连接，多条命令复用同一会话。
/// 移植自 TS 版 ssh.ts（CLI 用 ssh2，这里用 dartssh2）。
///
/// 为什么长连接复用：agentic loop 里连续执行多条命令，每次重连既慢又丢上下文。
/// 非线程安全：一个实例对应一台机器一个会话，由上层串行使用。
library;

import 'dart:convert';
import 'package:dartssh2/dartssh2.dart';

/// 命令执行结果三件套
class ExecResult {
  final String stdout;
  final String stderr;
  final int exitCode;
  const ExecResult(this.stdout, this.stderr, this.exitCode);
}

/// 远程文件项
class RemoteFile {
  final String name;
  final String path;
  final int size;
  final bool isDir;
  final String perms;
  const RemoteFile({
    required this.name,
    required this.path,
    required this.size,
    required this.isDir,
    required this.perms,
  });
}

class SshClient {
  SSHClient? _client;
  SSHSocket? _socket;
  SftpClient? _sftp;
  bool _connected = false;

  /// 建立连接。10s 超时。
  /// 传 privateKeyPem 走密钥认证（可带 passphrase）；否则用 password 走密码认证。
  Future<void> connect(
    String host,
    int port,
    String username,
    String password, {
    String? privateKeyPem,
    String? passphrase,
  }) async {
    _socket = await SSHSocket.connect(
      host,
      port == 0 ? 22 : port,
      timeout: const Duration(seconds: 10),
    );
    // 有私钥则解析为 identities 走公钥认证，否则回调返回密码
    final identities = (privateKeyPem != null && privateKeyPem.trim().isNotEmpty)
        ? SSHKeyPair.fromPem(privateKeyPem, passphrase)
        : null;
    _client = SSHClient(
      _socket!,
      username: username,
      identities: identities,
      onPasswordRequest: () => password,
      // demo 方便：dartssh2 默认不强制 known_hosts 校验；生产应校验，否则有中间人风险
    );
    await _client!.authenticated;
    _connected = true;
  }

  bool isConnected() => _connected && _client != null;

  /// 开一个交互式 shell（PTY），供 xterm 双向绑定。
  /// 与 exec 各走独立 channel：exec 给 agent 拿结构化结果，shell 给用户手敲。
  Future<SSHSession> shell({
    int width = 80,
    int height = 24,
  }) async {
    final client = _client;
    if (client == null || !_connected) {
      throw StateError('SSH 未连接，先调用 connect()');
    }
    return client.shell(
      pty: SSHPtyConfig(width: width, height: height),
    );
  }

  /// 执行一条命令，收集 stdout、stderr、exitCode。
  Future<ExecResult> exec(String command) async {
    final client = _client;
    if (client == null || !_connected) {
      throw StateError('SSH 未连接，先调用 connect()');
    }
    final session = await client.execute(command);
    // 并发收集 stdout / stderr，等命令结束
    final outFut = session.stdout.cast<List<int>>().transform(utf8.decoder).join();
    final errFut = session.stderr.cast<List<int>>().transform(utf8.decoder).join();
    final stdout = await outFut;
    final stderr = await errFut;
    await session.done;
    return ExecResult(stdout, stderr, session.exitCode ?? 0);
  }

  /// 懒开 SFTP 通道
  Future<SftpClient> _sftpClient() async {
    final client = _client;
    if (client == null || !_connected) {
      throw StateError('SSH 未连接');
    }
    return _sftp ??= await client.sftp();
  }

  /// 列目录。过滤 . 和 ..，目录在前、名称升序。
  Future<List<RemoteFile>> listDir(String path) async {
    final sftp = await _sftpClient();
    final base = path.endsWith('/') ? path : '$path/';
    final names = await sftp.listdir(path);
    final files = <RemoteFile>[];
    for (final e in names) {
      if (e.filename == '.' || e.filename == '..') continue;
      files.add(RemoteFile(
        name: e.filename,
        path: base + e.filename,
        size: e.attr.size ?? 0,
        isDir: e.attr.isDirectory,
        // longname 首列形如 drwxr-xr-x
        perms: e.longname.split(RegExp(r'\s+')).firstOrNull ?? '',
      ));
    }
    files.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return files;
  }

  /// 删除文件
  Future<void> deleteFile(String path) async {
    final sftp = await _sftpClient();
    await sftp.remove(path);
  }

  /// 新建目录
  Future<void> mkdir(String path) async {
    final sftp = await _sftpClient();
    await sftp.mkdir(path);
  }

  /// 重命名/移动
  Future<void> rename(String from, String to) async {
    final sftp = await _sftpClient();
    await sftp.rename(from, to);
  }

  /// 开一条本地端口转发 channel：把数据转发到远端 remoteHost:remotePort。
  /// 由 port_forward.dart 的隧道管理器调用，每个本地连接对应一条 channel。
  Future<SSHForwardChannel> forwardLocal(String remoteHost, int remotePort) {
    final client = _client;
    if (client == null || !_connected) {
      throw StateError('SSH 未连接，无法开端口转发');
    }
    return client.forwardLocal(remoteHost, remotePort);
  }

  /// 关闭连接
  void close() {
    _sftp?.close();
    _client?.close();
    _socket?.close();
    _sftp = null;
    _client = null;
    _socket = null;
    _connected = false;
  }
}
