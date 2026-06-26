/// 命令门禁 —— deny / ask / allow 三态判定。Agent 安全的硬边界。
/// 1:1 移植自 TS 版 guard.ts（再上游是 Java CommandGuard），规则与语义两端必须对齐。
///
/// 设计原则：
///  1. 安全检查是独立代码路径，不写进工具方法、不靠模型自觉。模型越狱也绕不过。
///  2. 三态顺序固定：先查 deny（命中即拒）→ 再看是否需 ask → 默认 allow。
///  3. 只看实际要执行的命令，不看模型话术。
///  4. 复合命令（&& | ; 串起来）拆段逐查，取最严结果。
library;

enum Decision { deny, ask, allow }

class Verdict {
  final Decision decision;
  final String reason;
  const Verdict(this.decision, this.reason);
}

/// deny 名单：不可逆的毁灭性操作，直接拒绝。
/// 用 \b 保证匹配独立命令词而非子串（dd 不误伤 add）。
final List<RegExp> _deny = [
  RegExp(r'\brm\s+(-\w*\s+)*-\w*[rf]'), // rm -rf / rm -fr 等带 r/f 组合
  RegExp(r'\bmkfs\b'), //                 格式化文件系统
  RegExp(r'\bdd\b'), //                   块设备读写，易毁盘
  RegExp(r'\bshutdown\b'), //             关机
  RegExp(r'\breboot\b'), //               重启
  RegExp(r'\bhalt\b'), //                 停机
  RegExp(r'>\s*/dev/sd'), //              直接写裸盘
  RegExp(r':\(\)\s*\{.*\}'), //           fork 炸弹 :(){ :|:& };:
  RegExp(r'\bmv\s+.*\s+/dev/null'), //    mv 到 /dev/null 销毁数据
  RegExp(r'\bfind\b.*-delete'), //        find ... -delete 批量删除
  RegExp(r'\bfind\b.*-exec\s+rm'), //     find ... -exec rm 批量删除
];

/// ask 名单：有副作用但未必致命，执行前问一句。
final List<RegExp> _ask = [
  RegExp(r'\brm\b'), //                              普通 rm（非 -rf）
  RegExp(r'\bkill\b'), //                            杀进程
  RegExp(r'\bsystemctl\s+(stop|restart|disable)'), // 停/重启/禁用服务
  RegExp(r'\bservice\s+\S+\s+(stop|restart)'),
  RegExp(r'\b(chmod|chown)\b'), //                   改权限/属主
  RegExp(r'\b(apt|apt-get|yum|dnf)\s+(install|remove|purge)'), // 装/卸软件
  RegExp(r'\btruncate\b'), //                        清空文件
  RegExp(r'>\s*/'), //                               重定向覆盖写到绝对路径文件
];

/// 三态严重程度排序，越小越严：DENY < ASK < ALLOW
int _ordinal(Decision d) => switch (d) {
      Decision.deny => 0,
      Decision.ask => 1,
      Decision.allow => 2,
    };

/// 判定一条命令。复合命令会被拆段，取最严结果（任一段 deny 则整条 deny）。
Verdict evaluate(String command) {
  if (command.trim().isEmpty) {
    return const Verdict(Decision.allow, '空命令');
  }

  // 先对完整命令整体过一遍 DENY：fork 炸弹 :(){ :|:& };: 本身含 | 和 ;，
  // 拆段会把它切碎导致漏判。DENY 命中即拒，整体多查一次只会更安全。
  for (final p in _deny) {
    final m = p.firstMatch(command);
    if (m != null) {
      return Verdict(Decision.deny, "命中危险命令拦截规则: '${m[0]}'");
    }
  }

  Decision worst = Decision.allow;
  String worstReason = '';

  for (final seg in _splitSegments(command)) {
    final s = seg.trim();
    if (s.isEmpty) continue;

    final v = _evaluateSingle(s);
    if (_ordinal(v.decision) < _ordinal(worst)) {
      worst = v.decision;
      worstReason = v.reason;
    }
    if (worst == Decision.deny) break; // 已最严，提前结束
  }

  if (worst == Decision.allow) {
    return const Verdict(Decision.allow, '只读/安全命令');
  }
  return Verdict(worst, worstReason);
}

/// 单段命令判定：先 deny 再 ask 后 allow
Verdict _evaluateSingle(String seg) {
  for (final p in _deny) {
    final m = p.firstMatch(seg);
    if (m != null) {
      return Verdict(Decision.deny, "命中危险命令拦截规则: '${m[0]}'");
    }
  }
  for (final p in _ask) {
    final m = p.firstMatch(seg);
    if (m != null) {
      return Verdict(Decision.ask, "涉及有副作用的操作: '${m[0]}'");
    }
  }
  return const Verdict(Decision.allow, '');
}

/// 按命令分隔符拆段：&& || | ; 换行，分隔符本身丢弃
List<String> _splitSegments(String command) {
  return command.split(RegExp(r'&&|\|\||[|;\n]'));
}

/// 一条门禁规则的只读说明（供 UI 展示，不参与判定）
class GuardRule {
  final Decision level;
  final String pattern; // 正则源串
  final String desc; //    中文说明
  const GuardRule(this.level, this.pattern, this.desc);
}

/// DENY 规则清单（与 _deny 一一对应，仅供 UI 展示）
const List<GuardRule> denyRules = [
  GuardRule(Decision.deny, r'\brm\s+...-[rf]', 'rm -rf / rm -fr 递归强删'),
  GuardRule(Decision.deny, r'\bmkfs\b', '格式化文件系统'),
  GuardRule(Decision.deny, r'\bdd\b', '块设备读写，易毁盘'),
  GuardRule(Decision.deny, r'\bshutdown\b', '关机'),
  GuardRule(Decision.deny, r'\breboot\b', '重启'),
  GuardRule(Decision.deny, r'\bhalt\b', '停机'),
  GuardRule(Decision.deny, r'>\s*/dev/sd', '直接写裸盘'),
  GuardRule(Decision.deny, r':(){ :|:& };:', 'fork 炸弹'),
  GuardRule(Decision.deny, r'\bmv\s+...\s+/dev/null', 'mv 到 /dev/null 销毁数据'),
  GuardRule(Decision.deny, r'\bfind\b...-delete', 'find 批量删除'),
  GuardRule(Decision.deny, r'\bfind\b...-exec rm', 'find -exec rm 批量删除'),
];

/// ASK 规则清单（与 _ask 一一对应，仅供 UI 展示）
const List<GuardRule> askRules = [
  GuardRule(Decision.ask, r'\brm\b', '普通 rm（非 -rf）'),
  GuardRule(Decision.ask, r'\bkill\b', '杀进程'),
  GuardRule(Decision.ask, r'\bsystemctl stop|restart|disable', '停/重启/禁用服务'),
  GuardRule(Decision.ask, r'\bservice ... stop|restart', '停/重启服务'),
  GuardRule(Decision.ask, r'\b(chmod|chown)\b', '改权限/属主'),
  GuardRule(Decision.ask, r'\b(apt|yum|dnf) install|remove', '装/卸软件'),
  GuardRule(Decision.ask, r'\btruncate\b', '清空文件'),
  GuardRule(Decision.ask, r'>\s*/', '重定向覆盖写绝对路径文件'),
];
