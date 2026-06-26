import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/audit_store.dart';

/// 门禁判定记录（一条阻止历史）
class GuardRecord {
  final String command;
  final String level; // deny / ask
  final DateTime time;
  const GuardRecord(this.command, this.level, this.time);
}

/// 门禁统计：三态计数 + 阻止历史。供右栏安全面板可视化。
class GuardStats {
  final int denyCount; // 已阻止（DENY 命中 + 用户拒绝）
  final int askCount; // 待确认（ASK 触发次数）
  final int allowCount; // 已放行（只读/安全命令执行）
  final List<GuardRecord> blocked; // 阻止历史（最新在前）

  const GuardStats({
    this.denyCount = 0,
    this.askCount = 0,
    this.allowCount = 0,
    this.blocked = const [],
  });

  GuardStats copyWith({
    int? denyCount,
    int? askCount,
    int? allowCount,
    List<GuardRecord>? blocked,
  }) =>
      GuardStats(
        denyCount: denyCount ?? this.denyCount,
        askCount: askCount ?? this.askCount,
        allowCount: allowCount ?? this.allowCount,
        blocked: blocked ?? this.blocked,
      );
}

/// 门禁统计 Notifier —— agent 执行命令时由 agent_provider 记账。
/// 每条命令同时落审计盘（auditProvider）。
class GuardNotifier extends Notifier<GuardStats> {
  @override
  GuardStats build() => const GuardStats();

  /// 命令被 DENY 拦截 / 用户拒绝
  void recordDeny(String command, {String host = '-'}) {
    state = state.copyWith(
      denyCount: state.denyCount + 1,
      blocked: [GuardRecord(command, 'deny', DateTime.now()), ...state.blocked],
    );
    _audit(command, 'deny', false, host);
  }

  /// 命令触发 ASK（待人工确认）
  void recordAsk() {
    state = state.copyWith(askCount: state.askCount + 1);
  }

  /// 命令放行执行（只读/安全）
  void recordAllow(String command, {String host = '-'}) {
    state = state.copyWith(allowCount: state.allowCount + 1);
    _audit(command, 'allow', true, host);
  }

  /// 落审计盘并刷新审计 provider
  void _audit(String command, String decision, bool executed, String host) {
    ref.read(auditProvider.notifier).record(
        command: command, decision: decision, executed: executed, host: host);
  }
}

final guardProvider =
    NotifierProvider<GuardNotifier, GuardStats>(GuardNotifier.new);

/// 审计日志 Notifier —— 全局命令审计列表，落盘持久化（最新在前，限 500 条）。
class AuditNotifier extends Notifier<List<AuditEntry>> {
  @override
  List<AuditEntry> build() => loadAudit();

  /// 记一条审计（落盘 + 刷新）
  void record({
    required String command,
    required String decision,
    required bool executed,
    required String host,
  }) {
    state = appendAudit(AuditEntry(
      command: command,
      decision: decision,
      executed: executed,
      host: host,
      time: DateTime.now(),
    ));
  }

  /// 清空审计
  void clear() {
    clearAudit();
    state = [];
  }
}

final auditProvider =
    NotifierProvider<AuditNotifier, List<AuditEntry>>(AuditNotifier.new);
