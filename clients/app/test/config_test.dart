import 'package:flutter_test/flutter_test.dart';
import 'package:lowenssh/core/config.dart';

void main() {
  group('Config 序列化', () {
    test('Host toJson/fromJson 往返', () {
      const h = Host(
        id: 'abc-123',
        alias: 'web01',
        host: '10.0.1.21',
        port: 2222,
        user: 'deploy',
        passwordEnc: 'ENCRYPTED==',
      );
      final round = Host.fromJson(h.toJson());
      expect(round.id, h.id);
      expect(round.alias, h.alias);
      expect(round.host, h.host);
      expect(round.port, h.port);
      expect(round.user, h.user);
      expect(round.passwordEnc, h.passwordEnc);
    });

    test('Host 默认值：port 22 / user root', () {
      final h = Host.fromJson({'id': 'x', 'host': '1.2.3.4'});
      expect(h.port, 22);
      expect(h.user, 'root');
      expect(h.passwordEnc, isNull);
    });

    test('无密码主机 toJson 不含 passwordEnc 字段', () {
      const h = Host(id: 'x', host: '1.2.3.4');
      expect(h.toJson().containsKey('passwordEnc'), false);
    });

    test('LlmConfig 缺字段回退默认 GLM', () {
      final c = LlmConfig.fromJson({});
      expect(c.baseURL, contains('bigmodel.cn'));
      expect(c.model, 'glm-4.6');
      expect(c.apiKey, '');
    });

    test('LlmConfig copyWith 只改指定字段', () {
      const c = LlmConfig(baseURL: 'u', apiKey: 'k', model: 'm');
      final c2 = c.copyWith(apiKey: 'new');
      expect(c2.baseURL, 'u');
      expect(c2.apiKey, 'new');
      expect(c2.model, 'm');
    });
  });
}
