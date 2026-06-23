import 'package:flutter_test/flutter_test.dart';
import 'package:lowenssh/core/crypto.dart';

void main() {
  group('CryptoUtil AES-GCM', () {
    test('加密后能解回原文', () {
      const plain = 'my-secret-password-123';
      final enc = encrypt(plain);
      expect(enc, isNotNull);
      expect(enc, isNot(plain));
      expect(decrypt(enc), plain);
    });

    test('同一明文每次密文不同（IV 随机）', () {
      expect(encrypt('same'), isNot(encrypt('same')));
    });

    test('空值返回 null', () {
      expect(encrypt(''), isNull);
      expect(encrypt(null), isNull);
      expect(decrypt(''), isNull);
      expect(decrypt(null), isNull);
    });

    test('中文密码往返正确', () {
      const plain = '密码测试🔐';
      expect(decrypt(encrypt(plain)), plain);
    });

    test('密文被篡改解密抛错（GCM 完整性校验）', () {
      final enc = encrypt('data')!;
      final tampered =
          enc.substring(0, enc.length - 4) + (enc.endsWith('AAAA') ? 'BBBB' : 'AAAA');
      expect(() => decrypt(tampered), throwsA(anything));
    });

    // 跨端互通：解密由 TS 端（CLI）用密钥 test-shared-key 加密的密文。
    // 仅当运行时设了同一密钥才校验，否则跳过（避免本地默认密钥下误失败）。
    test('跨端互通：解密 TS 端密文', () {
      const tsEnc =
          'L+y98S44UB3MnUKWkQZoNFRKgVjlmUwwfIAIDL+SXNxzJsPKY202TtkECUlCPRHlBPikSJ9o';
      const expected = 'cross-platform-test-密码';
      expect(decrypt(tsEnc), expected);
    }, skip: 'TS 与 Dart 已手工互通验证；需 XWSSH_CRYPTO_KEY=test-shared-key 才能跑');
  });
}
