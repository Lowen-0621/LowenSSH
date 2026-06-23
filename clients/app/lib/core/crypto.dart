/// 密码加密工具 —— 主机密码落本地存储前用 AES-256-GCM 加密，绝不存明文。
/// 1:1 移植自 TS 版 crypto.ts（再上游 Java CryptoUtil），密文格式三端互通。
///
/// 密文格式：Base64( iv[12] + cipherText + authTag[16] )。
/// pointycastle 的 GCMBlockCipher 在 doFinal 输出尾部内联 authTag，与 Java 版布局一致，
/// 故密文可与 TS/Java 端互相解密。
///
/// 密钥来源：环境变量 XWSSH_CRYPTO_KEY；任意长度经 SHA-256 派生成 32 字节 AES-256 密钥。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

const int _ivLen = 12; // GCM 推荐 12 字节 IV
const int _tagLen = 16; // 认证标签 16 字节（128 位）
const String _devDefaultKey = 'xwssh-dev-default-key-change-me';

/// 任意密钥串经 SHA-256 派生成固定 32 字节
Uint8List _deriveKey(String raw) {
  final digest = SHA256Digest();
  return digest.process(Uint8List.fromList(utf8.encode(raw)));
}

Uint8List _resolveKey() {
  final raw = Platform.environment['XWSSH_CRYPTO_KEY'];
  if (raw == null || raw.trim().isEmpty) {
    // 没配密钥退到开发默认值，仅保证能跑；生产务必设 XWSSH_CRYPTO_KEY
    return _deriveKey(_devDefaultKey);
  }
  return _deriveKey(raw);
}

/// 生成密码学安全的随机 IV（用 Dart 内置 Random.secure，简单可靠）
Uint8List _randomBytes(int len) {
  final rnd = Random.secure();
  final bytes = Uint8List(len);
  for (var i = 0; i < len; i++) {
    bytes[i] = rnd.nextInt(256);
  }
  return bytes;
}

/// 加密：明文 → Base64(iv + 密文 + tag)。空串返回 null。
String? encrypt(String? plain) {
  if (plain == null || plain.isEmpty) return null;
  final key = _resolveKey();
  final iv = _randomBytes(_ivLen);

  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      true,
      AEADParameters(KeyParameter(key), _tagLen * 8, iv, Uint8List(0)),
    );
  final ct = cipher.process(Uint8List.fromList(utf8.encode(plain)));
  // ct 尾部已内联 authTag，布局与 Java/TS 版对齐：iv + 密文 + tag
  final out = Uint8List(iv.length + ct.length)
    ..setRange(0, iv.length, iv)
    ..setRange(iv.length, iv.length + ct.length, ct);
  return base64.encode(out);
}

/// 解密：Base64(iv + 密文 + tag) → 明文。空串返回 null。
String? decrypt(String? enc) {
  if (enc == null || enc.isEmpty) return null;
  final key = _resolveKey();
  final all = base64.decode(enc);
  final iv = all.sublist(0, _ivLen);
  // pointycastle 的 GCM 解密期望输入为 密文+tag 拼接，正好是 all 去掉头部 iv
  final ctWithTag = all.sublist(_ivLen);

  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      false,
      AEADParameters(KeyParameter(key), _tagLen * 8, iv, Uint8List(0)),
    );
  final plain = cipher.process(Uint8List.fromList(ctWithTag));
  return utf8.decode(plain);
}
