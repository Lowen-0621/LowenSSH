/// 本地配置 —— 主机簿 + GLM 接入设置，存 ~/.lowenssh/config.json。
/// 1:1 移植自 TS 版 config.ts，配置文件格式与终端端一致（两端可共享同一份）。
///
/// 内置版（不依赖后端）的持久化层：替代 Java 版的 MySQL t_host。
/// 主机密码用 AES-GCM 加密后存 passwordEnc 字段，绝不存明文（复用 crypto.dart）。
/// 配置文件权限设为 600，只有属主可读写。
library;

import 'dart:convert';
import 'dart:io';
import 'package:uuid/uuid.dart';
import 'crypto.dart';

/// 一台主机的连接信息
class Host {
  final String id;
  final String? alias;
  final String host;
  final int port;
  final String user;

  /// AES-GCM 加密后的密码；未存密码则为 null
  final String? passwordEnc;

  /// 指定用哪把密钥认证（SshKey.id）；为 null 走密码认证
  final String? keyId;

  const Host({
    required this.id,
    this.alias,
    required this.host,
    this.port = 22,
    this.user = 'root',
    this.passwordEnc,
    this.keyId,
  });

  factory Host.fromJson(Map<String, dynamic> j) => Host(
        id: j['id'] as String,
        alias: j['alias'] as String?,
        host: j['host'] as String,
        port: (j['port'] as num?)?.toInt() ?? 22,
        user: j['user'] as String? ?? 'root',
        passwordEnc: j['passwordEnc'] as String?,
        keyId: j['keyId'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        if (alias != null) 'alias': alias,
        'host': host,
        'port': port,
        'user': user,
        if (passwordEnc != null) 'passwordEnc': passwordEnc,
        if (keyId != null) 'keyId': keyId,
      };
}

/// 一把 SSH 私钥。私钥 PEM 与可选 passphrase 均经 AES-GCM 加密落盘，绝不存明文。
class SshKey {
  final String id;
  final String name; //          展示名
  final String privateKeyEnc; // 加密后的 PEM 私钥
  final String? passphraseEnc; // 加密后的 passphrase（私钥无加密则为 null）

  const SshKey({
    required this.id,
    required this.name,
    required this.privateKeyEnc,
    this.passphraseEnc,
  });

  factory SshKey.fromJson(Map<String, dynamic> j) => SshKey(
        id: j['id'] as String,
        name: j['name'] as String? ?? '未命名密钥',
        privateKeyEnc: j['privateKeyEnc'] as String,
        passphraseEnc: j['passphraseEnc'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'privateKeyEnc': privateKeyEnc,
        if (passphraseEnc != null) 'passphraseEnc': passphraseEnc,
      };
}

/// GLM/OpenAI 兼容接入设置
class LlmConfig {
  final String baseURL;
  final String apiKey;
  final String model;

  const LlmConfig({
    required this.baseURL,
    required this.apiKey,
    required this.model,
  });

  factory LlmConfig.fromJson(Map<String, dynamic> j) => LlmConfig(
        baseURL: j['baseURL'] as String? ?? _defaultLlm.baseURL,
        apiKey: j['apiKey'] as String? ?? '',
        model: j['model'] as String? ?? _defaultLlm.model,
      );

  Map<String, dynamic> toJson() => {
        'baseURL': baseURL,
        'apiKey': apiKey,
        'model': model,
      };

  LlmConfig copyWith({String? baseURL, String? apiKey, String? model}) => LlmConfig(
        baseURL: baseURL ?? this.baseURL,
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
      );
}

class AppConfig {
  final List<Host> hosts;
  final List<SshKey> keys;
  final LlmConfig llm;

  const AppConfig({required this.hosts, this.keys = const [], required this.llm});
}

/// 默认 LLM 设置：GLM。apiKey 留空，首次运行提示用户填或从环境变量读
const LlmConfig _defaultLlm = LlmConfig(
  baseURL: 'https://open.bigmodel.cn/api/paas/v4',
  apiKey: '',
  model: 'glm-4.6',
);

String get _configDir =>
    '${Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.'}/.lowenssh';
String get configFile => '$_configDir/config.json';

const _uuid = Uuid();

AppConfig _emptyConfig() => const AppConfig(hosts: [], llm: _defaultLlm);

/// 读配置；不存在则返回空配置。环境变量 GLM_API_KEY 优先覆盖文件里的 apiKey。
AppConfig loadConfig() {
  AppConfig cfg;
  final file = File(configFile);
  if (!file.existsSync()) {
    cfg = _emptyConfig();
  } else {
    try {
      final raw = file.readAsStringSync();
      final parsed = jsonDecode(raw) as Map<String, dynamic>;
      final hosts = (parsed['hosts'] as List<dynamic>? ?? [])
          .map((e) => Host.fromJson(e as Map<String, dynamic>))
          .toList();
      final keys = (parsed['keys'] as List<dynamic>? ?? [])
          .map((e) => SshKey.fromJson(e as Map<String, dynamic>))
          .toList();
      final llm = parsed['llm'] != null
          ? LlmConfig.fromJson(parsed['llm'] as Map<String, dynamic>)
          : _defaultLlm;
      cfg = AppConfig(hosts: hosts, keys: keys, llm: llm);
    } catch (_) {
      // 配置损坏不影响启动，退回空配置（用户可重新添加）
      cfg = _emptyConfig();
    }
  }
  // 环境变量优先：方便临时覆盖，且不把 key 写进文件
  final envKey = Platform.environment['GLM_API_KEY'];
  if (envKey != null && envKey.trim().isNotEmpty) {
    cfg = AppConfig(
        hosts: cfg.hosts,
        keys: cfg.keys,
        llm: cfg.llm.copyWith(apiKey: envKey));
  }
  return cfg;
}

/// 写配置（权限 600）。注意：不会把环境变量注入的 apiKey 持久化回文件。
void saveConfig(AppConfig cfg) {
  final dir = Directory(_configDir);
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }
  final json = const JsonEncoder.withIndent('  ').convert({
    'hosts': cfg.hosts.map((h) => h.toJson()).toList(),
    'keys': cfg.keys.map((k) => k.toJson()).toList(),
    'llm': cfg.llm.toJson(),
  });
  final file = File(configFile);
  file.writeAsStringSync(json);
  // Windows 不支持 chmod，忽略异常
  try {
    if (!Platform.isWindows) {
      Process.runSync('chmod', ['600', configFile]);
    }
  } catch (_) {}
}

/// 新增主机：密码加密后落库，返回带 id 的 Host。
/// keyId 非空表示用密钥认证（此时通常不存密码）。
Host addHost({
  String? alias,
  required String host,
  int port = 22,
  String user = 'root',
  String? password,
  String? keyId,
}) {
  final cfg = loadConfig();
  final newHost = Host(
    id: _uuid.v4(),
    alias: alias,
    host: host,
    port: port,
    user: user,
    passwordEnc: (password != null && password.isNotEmpty) ? encrypt(password) : null,
    keyId: keyId,
  );
  final hosts = [...cfg.hosts, newHost];
  saveConfig(AppConfig(hosts: hosts, keys: cfg.keys, llm: cfg.llm));
  return newHost;
}

/// 删除主机
void removeHost(String id) {
  final cfg = loadConfig();
  final hosts = cfg.hosts.where((h) => h.id != id).toList();
  saveConfig(AppConfig(hosts: hosts, keys: cfg.keys, llm: cfg.llm));
}

/// 取某主机的明文密码（解密）；未存返回 null
String? getHostPassword(Host host) {
  if (host.passwordEnc == null) return null;
  return decrypt(host.passwordEnc);
}

/// 主机是否已存密码
bool hasPassword(Host host) => host.passwordEnc != null;

/// 新增密钥：私钥 PEM 与 passphrase 加密后落库，返回带 id 的 SshKey
SshKey addKey({
  required String name,
  required String privateKeyPem,
  String? passphrase,
}) {
  final cfg = loadConfig();
  final newKey = SshKey(
    id: _uuid.v4(),
    name: name,
    privateKeyEnc: encrypt(privateKeyPem)!,
    passphraseEnc: (passphrase != null && passphrase.isNotEmpty)
        ? encrypt(passphrase)
        : null,
  );
  final keys = [...cfg.keys, newKey];
  saveConfig(AppConfig(hosts: cfg.hosts, keys: keys, llm: cfg.llm));
  return newKey;
}

/// 删除密钥。引用了该密钥的主机回退为「无认证」（keyId 置空），由用户重新配置。
void removeKey(String id) {
  final cfg = loadConfig();
  final keys = cfg.keys.where((k) => k.id != id).toList();
  // 解除引用：把 keyId 指向被删密钥的主机清掉 keyId
  final hosts = cfg.hosts
      .map((h) => h.keyId == id
          ? Host(
              id: h.id,
              alias: h.alias,
              host: h.host,
              port: h.port,
              user: h.user,
              passwordEnc: h.passwordEnc,
              keyId: null,
            )
          : h)
      .toList();
  saveConfig(AppConfig(hosts: hosts, keys: keys, llm: cfg.llm));
}

/// 取某把密钥的明文 PEM + passphrase（解密）。找不到返回 null。
({String pem, String? passphrase})? getKeyMaterial(String keyId) {
  final cfg = loadConfig();
  final key = cfg.keys.where((k) => k.id == keyId).firstOrNull;
  if (key == null) return null;
  final pem = decrypt(key.privateKeyEnc);
  if (pem == null) return null;
  return (
    pem: pem,
    passphrase: key.passphraseEnc != null ? decrypt(key.passphraseEnc) : null,
  );
}
