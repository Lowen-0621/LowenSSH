/**
 * 命令门禁 —— deny / ask / allow 三态判定。Agent 安全的硬边界。
 * 1:1 移植自 Java 版 CommandGuard，规则与语义保持一致（两端必须对齐）。
 *
 * 设计原则：
 *  1. 安全检查是独立代码路径，不写进工具方法、不靠模型自觉。模型越狱也绕不过。
 *  2. 三态顺序固定：先查 deny（命中即拒）→ 再看是否需 ask → 默认 allow。
 *  3. 只看实际要执行的命令，不看模型话术。
 *  4. 复合命令（&& | ; 串起来）拆段逐查，取最严结果。
 */

export type Decision = 'DENY' | 'ASK' | 'ALLOW'

export interface Verdict {
  decision: Decision
  reason: string
}

/**
 * deny 名单：不可逆的毁灭性操作，直接拒绝。
 * 用 \b 保证匹配独立命令词而非子串（dd 不误伤 add）。
 */
const DENY: RegExp[] = [
  /\brm\s+(-\w*\s+)*-\w*[rf]/, // rm -rf / rm -fr 等带 r/f 组合
  /\bmkfs\b/, //                 格式化文件系统
  /\bdd\b/, //                   块设备读写，易毁盘
  /\bshutdown\b/, //             关机
  /\breboot\b/, //               重启
  /\bhalt\b/, //                 停机
  />\s*\/dev\/sd/, //            直接写裸盘
  /:\(\)\s*\{.*\}/, //           fork 炸弹 :(){ :|:& };:
  /\bmv\s+.*\s+\/dev\/null/, //  mv 到 /dev/null 销毁数据
  /\bfind\b.*-delete/, //        find ... -delete 批量删除（rm -rf 等价绕过）
  /\bfind\b.*-exec\s+rm/, //     find ... -exec rm 批量删除
]

/**
 * ask 名单：有副作用但未必致命，执行前问一句。
 */
const ASK: RegExp[] = [
  /\brm\b/, //                              普通 rm（非 -rf）
  /\bkill\b/, //                            杀进程
  /\bsystemctl\s+(stop|restart|disable)/, // 停/重启/禁用服务
  /\bservice\s+\S+\s+(stop|restart)/,
  /\b(chmod|chown)\b/, //                   改权限/属主
  /\b(apt|apt-get|yum|dnf)\s+(install|remove|purge)/, // 装/卸软件
  /\btruncate\b/, //                        清空文件
  />\s*\//, //                              重定向覆盖写到绝对路径文件
]

/** 三态严重程度排序，越小越严：DENY < ASK < ALLOW */
const ORDINAL: Record<Decision, number> = { DENY: 0, ASK: 1, ALLOW: 2 }

/**
 * 判定一条命令。复合命令会被拆段，取最严结果（任一段 deny 则整条 deny）。
 */
export function evaluate(command: string): Verdict {
  if (!command || command.trim() === '') {
    return { decision: 'ALLOW', reason: '空命令' }
  }

  // 先对完整命令整体过一遍 DENY：fork 炸弹 :(){ :|:& };: 本身含 | 和 ;，
  // 拆段会把它切碎导致漏判。DENY 命中即拒，整体多查一次只会更安全。
  // （相对 Java 版的增强，Java 版 splitSegments 同样会漏 fork 炸弹，待同步修复。）
  for (const p of DENY) {
    const m = command.match(p)
    if (m) {
      return { decision: 'DENY', reason: `命中危险命令拦截规则: '${m[0]}'` }
    }
  }

  let worst: Decision = 'ALLOW'
  let worstReason = ''

  for (const seg of splitSegments(command)) {
    const s = seg.trim()
    if (s === '') continue

    const v = evaluateSingle(s)
    if (ORDINAL[v.decision] < ORDINAL[worst]) {
      worst = v.decision
      worstReason = v.reason
    }
    if (worst === 'DENY') break // 已最严，提前结束
  }

  if (worst === 'ALLOW') {
    return { decision: 'ALLOW', reason: '只读/安全命令' }
  }
  return { decision: worst, reason: worstReason }
}

/** 单段命令判定：先 deny 再 ask 后 allow */
function evaluateSingle(seg: string): Verdict {
  for (const p of DENY) {
    const m = seg.match(p)
    if (m) {
      return { decision: 'DENY', reason: `命中危险命令拦截规则: '${m[0]}'` }
    }
  }
  for (const p of ASK) {
    const m = seg.match(p)
    if (m) {
      return { decision: 'ASK', reason: `涉及有副作用的操作: '${m[0]}'` }
    }
  }
  return { decision: 'ALLOW', reason: '' }
}

/** 按命令分隔符拆段：&& || | ; 换行，分隔符本身丢弃 */
function splitSegments(command: string): string[] {
  return command.split(/&&|\|\||[|;\n]/)
}
