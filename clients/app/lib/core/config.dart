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

  const Host({
    required this.id,
    this.alias,
    required this.host,
    this.port = 22,
    this.user = 'root',
    this.passwordEnc,
  });

  factory Host.fromJson(Map<String, dynamic> j) => Host(
        id: j['id'] as String,
        alias: j['alias'] as String?,
        host: j['host'] as String,
        port: (j['port'] as num?)?.toInt() ?? 22,
        user: j['user'] as String? ?? 'root',
        passwordEnc: j['passwordEnc'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        if (alias != null) 'alias': alias,
        'host': host,
        'port': port,
        'user': user,
        if (passwordEnc != null) 'passwordEnc': passwordEnc,
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
  final LlmConfig llm;

  const AppConfig({required this.hosts, required this.llm});
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
      final llm = parsed['llm'] != null
          ? LlmConfig.fromJson(parsed['llm'] as Map<String, dynamic>)
          : _defaultLlm;
      cfg = AppConfig(hosts: hosts, llm: llm);
    } catch (_) {
      // 配置损坏不影响启动，退回空配置（用户可重新添加）
      cfg = _emptyConfig();
    }
  }
  // 环境变量优先：方便临时覆盖，且不把 key 写进文件
  final envKey = Platform.environment['GLM_API_KEY'];
  if (envKey != null && envKey.trim().isNotEmpty) {
    cfg = AppConfig(hosts: cfg.hosts, llm: cfg.llm.copyWith(apiKey: envKey));
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

/// 新增主机：密码加密后落库，返回带 id 的 Host
Host addHost({
  String? alias,
  required String host,
  int port = 22,
  String user = 'root',
  String? password,
}) {
  final cfg = loadConfig();
  final newHost = Host(
    id: _uuid.v4(),
    alias: alias,
    host: host,
    port: port,
    user: user,
    passwordEnc: (password != null && password.isNotEmpty) ? encrypt(password) : null,
  );
  final hosts = [...cfg.hosts, newHost];
  saveConfig(AppConfig(hosts: hosts, llm: cfg.llm));
  return newHost;
}

/// 删除主机
void removeHost(String id) {
  final cfg = loadConfig();
  final hosts = cfg.hosts.where((h) => h.id != id).toList();
  saveConfig(AppConfig(hosts: hosts, llm: cfg.llm));
}

/// 取某主机的明文密码（解密）；未存返回 null
String? getHostPassword(Host host) {
  if (host.passwordEnc == null) return null;
  return decrypt(host.passwordEnc);
}

/// 主机是否已存密码
bool hasPassword(Host host) => host.passwordEnc != null;
