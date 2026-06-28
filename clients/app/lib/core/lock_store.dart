/// 本地主密码锁 —— 启动时校验，保护本地主机簿/密钥不被随手打开。
///
/// 安全设计：
/// - 不存明文，不存可逆密文，只存「加盐多轮 SHA-256」校验哈希。
/// - 随机盐（16B）抗彩虹表；多轮迭代（stretch）抬高暴力成本。
/// - 存 ~/.lowenssh/lock.json，权限 600。
/// - 未设置主密码时无锁，直接进应用（不强制）。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

const int _saltLen = 16;
const int _rounds = 100000; // 迭代轮数，抬高暴力破解成本

String get _lockFile =>
    '${Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.'}/.lowenssh/lock.json';

/// 加盐多轮 SHA-256：hash = SHA256^rounds(salt + pwd)
String _hash(String pwd, Uint8List salt) {
  final digest = SHA256Digest();
  var cur = Uint8List.fromList([...salt, ...utf8.encode(pwd)]);
  for (var i = 0; i < _rounds; i++) {
    cur = digest.process(cur);
  }
  return base64.encode(cur);
}

Uint8List _randomSalt() {
  final rnd = Random.secure();
  final b = Uint8List(_saltLen);
  for (var i = 0; i < _saltLen; i++) {
    b[i] = rnd.nextInt(256);
  }
  return b;
}

/// 是否已设置主密码
bool hasMasterPassword() => File(_lockFile).existsSync();

/// 设置/修改主密码（覆盖写）
void setMasterPassword(String pwd) {
  final salt = _randomSalt();
  final data = {
    'salt': base64.encode(salt),
    'hash': _hash(pwd, salt),
    'rounds': _rounds,
  };
  final dir = Directory(
      '${Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.'}/.lowenssh');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  final f = File(_lockFile);
  f.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data));
  // 权限 600（仅本人可读写）
  try {
    Process.runSync('chmod', ['600', _lockFile]);
  } catch (_) {/* Windows 无 chmod，忽略 */}
}

/// 取消主密码（删除锁文件）
void clearMasterPassword() {
  final f = File(_lockFile);
  if (f.existsSync()) f.deleteSync();
}

/// 校验主密码是否正确
bool verifyMasterPassword(String pwd) {
  final f = File(_lockFile);
  if (!f.existsSync()) return true; // 没设锁视为通过
  try {
    final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    final salt = base64.decode(j['salt'] as String);
    return _hash(pwd, Uint8List.fromList(salt)) == j['hash'] as String;
  } catch (_) {
    return false;
  }
}
