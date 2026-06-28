/// 轻量国际化 —— 不引第三方包，一个 key→译文 Map 搞定中/英切换。
/// 设计：L10n 持有当前语言；t(key) 取译文，缺失回退中文、再回退 key 本身。
/// 全应用文案逐步迁移到这里（分批），新代码一律用 context 无关的 L10n.of(ref)。
library;

/// 支持的语言
enum AppLang { zh, en }

/// 文案字典。外层 key 是文案标识，内层按语言取值。
/// 约定：key 用点分命名空间（settings.title / common.save）。
const Map<String, Map<AppLang, String>> _dict = {
  // 通用动作
  'common.save': {AppLang.zh: '保存', AppLang.en: 'Save'},
  'common.cancel': {AppLang.zh: '取消', AppLang.en: 'Cancel'},
  'common.delete': {AppLang.zh: '删除', AppLang.en: 'Delete'},
  'common.add': {AppLang.zh: '添加', AppLang.en: 'Add'},
  'common.close': {AppLang.zh: '关闭', AppLang.en: 'Close'},
  'common.version': {AppLang.zh: '版本', AppLang.en: 'Version'},

  // 设置中心 - 导航
  'settings.title': {AppLang.zh: '设置', AppLang.en: 'Settings'},
  'settings.nav.aiModel': {AppLang.zh: 'AI 模型', AppLang.en: 'AI Model'},
  'settings.nav.common': {AppLang.zh: '通用', AppLang.en: 'Common'},
  'settings.nav.terminal': {AppLang.zh: '终端', AppLang.en: 'Terminal'},
  'settings.nav.theme': {AppLang.zh: '外观', AppLang.en: 'Appearance'},
  'settings.theme.scheme': {AppLang.zh: '配色方案', AppLang.en: 'Color Scheme'},
  'settings.theme.hint': {
    AppLang.zh: '选择应用的整体配色，立即生效。',
    AppLang.en: 'Pick the app color scheme. Applies instantly.'
  },
  'settings.nav.security': {AppLang.zh: '安全', AppLang.en: 'Security'},
  'settings.nav.shortcuts': {AppLang.zh: '快捷键', AppLang.en: 'Shortcuts'},

  // 通用页
  'settings.common.title': {AppLang.zh: '通用设置', AppLang.en: 'Common Settings'},
  'settings.common.language': {AppLang.zh: '语言', AppLang.en: 'Language'},
  'settings.common.langZh': {AppLang.zh: '简体中文', AppLang.en: 'Simplified Chinese'},
  'settings.common.langEn': {AppLang.zh: '英文', AppLang.en: 'English'},

  // AI 模型页
  'settings.ai.title': {AppLang.zh: 'AI 模型设置', AppLang.en: 'AI Model Settings'},
  'settings.ai.provider': {AppLang.zh: '供应商', AppLang.en: 'Provider'},
  'settings.ai.apiKey': {AppLang.zh: 'API Key', AppLang.en: 'API Key'},
  'settings.ai.baseUrl': {AppLang.zh: 'Base URL', AppLang.en: 'Base URL'},
  'settings.ai.model': {AppLang.zh: '模型', AppLang.en: 'Model'},
  'settings.ai.active': {AppLang.zh: '当前使用', AppLang.en: 'Active'},
  'settings.ai.setActive': {AppLang.zh: '设为当前', AppLang.en: 'Set as active'},
  'settings.ai.configured': {AppLang.zh: '已配置', AppLang.en: 'Configured'},
  'settings.ai.notConfigured': {AppLang.zh: '未配置 Key', AppLang.en: 'No API Key'},
  'settings.ai.hint': {
    AppLang.zh: '填入对应供应商的 API Key 即可启用。均走 OpenAI 兼容协议。',
    AppLang.en: 'Enter the API Key to enable. All use the OpenAI-compatible protocol.'
  },

  // 终端设置页
  'settings.term.title': {AppLang.zh: '终端设置', AppLang.en: 'Terminal Settings'},
  'settings.term.fontSize': {AppLang.zh: '字号', AppLang.en: 'Font Size'},
  'settings.term.selectToCopy': {
    AppLang.zh: '选中即复制 / 右键粘贴',
    AppLang.en: 'Select to copy & Right click to paste'
  },
  'settings.term.rightClickPaste': {
    AppLang.zh: '右键粘贴',
    AppLang.en: 'Right click to paste'
  },
  'settings.term.cursorStyle': {AppLang.zh: '光标样式', AppLang.en: 'Cursor Style'},
  'settings.term.cursorBlink': {AppLang.zh: '光标闪烁', AppLang.en: 'Cursor Blink'},
  'settings.term.cursorBlock': {AppLang.zh: '方块', AppLang.en: 'Block'},
  'settings.term.cursorUnderline': {AppLang.zh: '下划线', AppLang.en: 'Underline'},
  'settings.term.cursorBar': {AppLang.zh: '竖线', AppLang.en: 'Bar'},

  // ========== 通用复用 ==========
  'common.confirm': {AppLang.zh: '确认', AppLang.en: 'Confirm'},
  'common.clear': {AppLang.zh: '清空', AppLang.en: 'Clear'},
  'common.all': {AppLang.zh: '全部', AppLang.en: 'All'},
  'state.denied': {AppLang.zh: '已阻止', AppLang.en: 'Blocked'},
  'state.ask': {AppLang.zh: '待确认', AppLang.en: 'Pending'},
  'state.allowed': {AppLang.zh: '已放行', AppLang.en: 'Allowed'},

  // ========== 顶栏 ==========
  'top.search': {AppLang.zh: '搜索主机…', AppLang.en: 'Search hosts…'},
  'top.connect': {AppLang.zh: '连接', AppLang.en: 'Connect'},
  'top.newHost': {AppLang.zh: '新建主机', AppLang.en: 'New Host'},
  'top.split': {AppLang.zh: '分屏', AppLang.en: 'Split'},

  // ========== 面板标题 ==========
  'panel.hosts': {AppLang.zh: '主机', AppLang.en: 'Hosts'},
  'panel.terminal': {AppLang.zh: '终端', AppLang.en: 'Terminal'},
  'panel.agent': {AppLang.zh: '智能体', AppLang.en: 'Agent'},
  'panel.side': {AppLang.zh: '面板', AppLang.en: 'Panel'},

  // ========== 左栏 ==========
  'left.noHosts': {AppLang.zh: '暂无主机，点 + 添加', AppLang.en: 'No hosts, click + to add'},
  'left.noMatch': {
    AppLang.zh: '未找到匹配「{q}」的主机',
    AppLang.en: 'No host matching "{q}"'
  },
  'left.connectFail': {AppLang.zh: '连接失败：{err}', AppLang.en: 'Connect failed: {err}'},
  'left.snippets': {AppLang.zh: '命令片段', AppLang.en: 'Snippets'},
  'left.keys': {AppLang.zh: '密钥库', AppLang.en: 'Keys'},
  'left.forward': {AppLang.zh: '端口转发', AppLang.en: 'Port Forwarding'},
  'left.security': {AppLang.zh: '安全策略', AppLang.en: 'Security'},
  'left.audit': {AppLang.zh: '审计日志', AppLang.en: 'Audit Log'},
  'left.deleteHost': {AppLang.zh: '删除主机', AppLang.en: 'Delete Host'},
  'left.deleteHostConfirm': {
    AppLang.zh: '确定删除「{name}」（{addr}）？此操作不可撤销。',
    AppLang.en: 'Delete "{name}" ({addr})? This cannot be undone.'
  },

  // ========== 智能体面板 ==========
  'ai.empty': {
    AppLang.zh: '连接主机后，输入运维任务开始对话',
    AppLang.en: 'Connect a host, then enter an ops task to start'
  },
  'ai.error': {AppLang.zh: '错误：{err}', AppLang.en: 'Error: {err}'},
  'ai.agent': {AppLang.zh: '智能体', AppLang.en: 'Agent'},
  'ai.switchModel': {AppLang.zh: '切换模型', AppLang.en: 'Switch model'},
  'ai.askTitle': {AppLang.zh: '需要确认 · 该命令需人工放行', AppLang.en: 'Confirmation needed · manual approval required'},
  'ai.gateVerdict': {AppLang.zh: '门禁判定：ASK — {reason}', AppLang.en: 'Guard: ASK — {reason}'},
  'ai.allow': {AppLang.zh: '允许执行', AppLang.en: 'Allow'},
  'ai.deny': {AppLang.zh: '拒绝', AppLang.en: 'Deny'},
  'ai.blockedTitle': {AppLang.zh: '已阻止 · 高危命令', AppLang.en: 'Blocked · dangerous command'},
  'ai.inputHint': {AppLang.zh: '输入运维任务，或 @ 引用主机…', AppLang.en: 'Enter an ops task, or @ to reference a host…'},
  'ai.interrupt': {AppLang.zh: '中断', AppLang.en: 'Stop'},
  'ai.send': {AppLang.zh: '↵ 发送', AppLang.en: '↵ Send'},
  'ai.sendKey': {AppLang.zh: '⏎ 发送', AppLang.en: '⏎ Send'},
  'ai.newlineKey': {AppLang.zh: '⇧⏎ 换行', AppLang.en: '⇧⏎ Newline'},
  'ai.escKey': {AppLang.zh: 'Esc 中断', AppLang.en: 'Esc Stop'},
  'ai.cmdK': {AppLang.zh: '⌘K 命令面板', AppLang.en: '⌘K Commands'},
  'ai.thinkingDone': {AppLang.zh: '思考 {sec}s', AppLang.en: 'Thought {sec}s'},
  'ai.thinking': {AppLang.zh: '思考中…', AppLang.en: 'Thinking…'},
  'ai.thinkProcess': {AppLang.zh: '思考过程', AppLang.en: 'Reasoning'},

  // ========== 审计对话框 ==========
  'audit.title': {AppLang.zh: '审计日志', AppLang.en: 'Audit Log'},
  'audit.count': {AppLang.zh: '共 {n} 条', AppLang.en: '{n} entries'},
  'audit.empty': {AppLang.zh: '暂无审计记录', AppLang.en: 'No audit records'},
  'audit.notExecuted': {AppLang.zh: ' · 未执行', AppLang.en: ' · not executed'},

  // ========== 新建主机对话框 ==========
  'host.new': {AppLang.zh: '新建主机', AppLang.en: 'New Host'},
  'host.alias': {AppLang.zh: '别名（可选）', AppLang.en: 'Alias (optional)'},
  'host.address': {AppLang.zh: '主机地址', AppLang.en: 'Host Address'},
  'host.addressHint': {AppLang.zh: '10.0.1.21 或 example.com', AppLang.en: '10.0.1.21 or example.com'},
  'host.port': {AppLang.zh: '端口', AppLang.en: 'Port'},
  'host.user': {AppLang.zh: '用户名', AppLang.en: 'Username'},
  'host.authMode': {AppLang.zh: '认证方式', AppLang.en: 'Auth Method'},
  'host.password': {AppLang.zh: '密码', AppLang.en: 'Password'},
  'host.key': {AppLang.zh: '密钥', AppLang.en: 'Key'},
  'host.keyEmpty': {
    AppLang.zh: '密钥库为空，请先到「密钥库」添加密钥',
    AppLang.en: 'No keys. Add one in Keys first.'
  },
  'host.selectKey': {AppLang.zh: '选择密钥', AppLang.en: 'Select Key'},
  'host.pleaseSelect': {AppLang.zh: '请选择…', AppLang.en: 'Please select…'},

  // ========== 端口转发对话框 ==========
  'fwd.title': {AppLang.zh: '端口转发', AppLang.en: 'Port Forwarding'},
  'fwd.count': {AppLang.zh: '共 {n} 条', AppLang.en: '{n} tunnels'},
  'fwd.addTunnel': {AppLang.zh: '添加隧道', AppLang.en: 'Add Tunnel'},
  'fwd.boundHint': {
    AppLang.zh: '隧道依附当前连接：{host}。等价 ssh -L 本地→远程，仅本机可访问。',
    AppLang.en: 'Tunnel bound to current connection: {host}. Equivalent to ssh -L, localhost only.'
  },
  'fwd.notConnected': {
    AppLang.zh: '未连接主机。连接后才能启动隧道。',
    AppLang.en: 'Not connected. Connect a host to start tunnels.'
  },
  'fwd.empty': {AppLang.zh: '暂无隧道，点「添加隧道」新建', AppLang.en: 'No tunnels, click "Add Tunnel"'},
  'fwd.running': {AppLang.zh: '运行中', AppLang.en: 'Running'},
  'fwd.stopped': {AppLang.zh: '已停止', AppLang.en: 'Stopped'},
  'fwd.start': {AppLang.zh: '启动', AppLang.en: 'Start'},
  'fwd.stop': {AppLang.zh: '停止', AppLang.en: 'Stop'},
  'fwd.addDesc': {
    AppLang.zh: '本地端口的连接经 SSH 转发到远程地址。常用于访问远端内网服务（如数据库）。',
    AppLang.en: 'Forward a local port through SSH to a remote address. Useful for remote internal services (e.g. databases).'
  },
  'fwd.localPort': {AppLang.zh: '本地端口', AppLang.en: 'Local Port'},
  'fwd.localPortHint': {AppLang.zh: '如 13306', AppLang.en: 'e.g. 13306'},
  'fwd.remoteHost': {AppLang.zh: '远程地址（从远端主机视角）', AppLang.en: 'Remote Host (from remote view)'},
  'fwd.remoteHostHint': {AppLang.zh: '127.0.0.1 或内网 IP', AppLang.en: '127.0.0.1 or internal IP'},
  'fwd.remotePort': {AppLang.zh: '远程端口', AppLang.en: 'Remote Port'},
  'fwd.remotePortHint': {AppLang.zh: '如 3306', AppLang.en: 'e.g. 3306'},
  'fwd.errLocalPort': {AppLang.zh: '本地端口不合法（1-65535）', AppLang.en: 'Invalid local port (1-65535)'},
  'fwd.errRemotePort': {AppLang.zh: '远程端口不合法（1-65535）', AppLang.en: 'Invalid remote port (1-65535)'},
  'fwd.errRemoteHost': {AppLang.zh: '远程地址不能为空', AppLang.en: 'Remote host required'},
  'fwd.addStart': {AppLang.zh: '添加并启动', AppLang.en: 'Add & Start'},

  // ========== 密钥库对话框 ==========
  'keys.title': {AppLang.zh: '密钥库', AppLang.en: 'Keys'},
  'keys.count': {AppLang.zh: '共 {n} 把', AppLang.en: '{n} keys'},
  'keys.add': {AppLang.zh: '添加密钥', AppLang.en: 'Add Key'},
  'keys.empty': {AppLang.zh: '暂无密钥，点「添加密钥」粘贴私钥 PEM', AppLang.en: 'No keys. Click "Add Key" to paste a PEM.'},
  'keys.withPassphrase': {AppLang.zh: '🔒 带 passphrase · ', AppLang.en: '🔒 with passphrase · '},
  'keys.usedBy': {AppLang.zh: '{n} 台主机使用', AppLang.en: 'used by {n} hosts'},
  'keys.unused': {AppLang.zh: '未被使用', AppLang.en: 'unused'},
  'keys.deleteKey': {AppLang.zh: '删除密钥', AppLang.en: 'Delete Key'},
  'keys.deleteUsed': {
    AppLang.zh: '密钥「{name}」正被 {n} 台主机使用，删除后这些主机将解除密钥绑定（需重新配置认证）。确定删除？',
    AppLang.en: 'Key "{name}" is used by {n} hosts. Deleting unbinds them (re-config needed). Delete?'
  },
  'keys.deleteConfirm': {
    AppLang.zh: '确定删除密钥「{name}」？此操作不可撤销。',
    AppLang.en: 'Delete key "{name}"? This cannot be undone.'
  },
  'keys.name': {AppLang.zh: '名称', AppLang.en: 'Name'},
  'keys.pem': {AppLang.zh: '私钥（PEM，粘贴 -----BEGIN ... 全文）', AppLang.en: 'Private Key (PEM, paste full -----BEGIN ...)'},
  'keys.passphrase': {AppLang.zh: 'passphrase（私钥无加密则留空）', AppLang.en: 'passphrase (leave empty if none)'},
  'keys.errPem': {AppLang.zh: '私钥格式不对，应以 -----BEGIN 开头', AppLang.en: 'Invalid key, must start with -----BEGIN'},
  'keys.unnamed': {AppLang.zh: '未命名密钥', AppLang.en: 'Unnamed Key'},

  // ========== 右栏（安全/文件/监控） ==========
  'right.tabSec': {AppLang.zh: '安全', AppLang.en: 'Security'},
  'right.tabFiles': {AppLang.zh: '文件', AppLang.en: 'Files'},
  'right.tabMon': {AppLang.zh: '监控', AppLang.en: 'Monitor'},
  'right.hits': {AppLang.zh: '{n} 次', AppLang.en: '{n}×'},
  'right.rulesTitle': {AppLang.zh: '门禁规则（按严格度）', AppLang.en: 'Guard Rules (by severity)'},
  'right.blockHistory': {AppLang.zh: '阻止历史', AppLang.en: 'Block History'},
  'right.noBlock': {AppLang.zh: '暂无阻止记录', AppLang.en: 'No block records'},
  'right.tempAllow': {AppLang.zh: '临时放行', AppLang.en: 'Temp allow'},
  'right.filesEmpty': {AppLang.zh: '连接主机后浏览远程文件', AppLang.en: 'Connect a host to browse remote files'},
  'right.loadFail': {AppLang.zh: '加载失败：{err}', AppLang.en: 'Load failed: {err}'},
  'right.emptyDir': {AppLang.zh: '（空目录）', AppLang.en: '(empty)'},
  'right.monEmpty': {AppLang.zh: '连接主机后查看实时监控', AppLang.en: 'Connect a host to view live monitoring'},
  'right.resUsage': {AppLang.zh: '资源占用', AppLang.en: 'Resource Usage'},
  'right.mem': {AppLang.zh: '内存', AppLang.en: 'Memory'},
  'right.disk': {AppLang.zh: '磁盘 /', AppLang.en: 'Disk /'},
  'right.load': {AppLang.zh: '负载', AppLang.en: 'Load'},
  'right.network': {AppLang.zh: '网络', AppLang.en: 'Network'},
  'right.netIn': {AppLang.zh: '↓ 入站', AppLang.en: '↓ In'},
  'right.netOut': {AppLang.zh: '↑ 出站', AppLang.en: '↑ Out'},
  'right.sampleFail': {AppLang.zh: '采样失败：{err}', AppLang.en: 'Sampling failed: {err}'},

  // ========== 安全策略对话框 ==========
  'sec.title': {AppLang.zh: '安全策略', AppLang.en: 'Security Policy'},
  'sec.subtitle': {AppLang.zh: '命令门禁规则', AppLang.en: 'Command guard rules'},
  'sec.principle1': {
    AppLang.zh: '判定顺序：先查 DENY（命中即拒）→ 再看 ASK（执行前确认）→ 默认 ALLOW。',
    AppLang.en: 'Order: DENY (reject on match) → ASK (confirm first) → default ALLOW.'
  },
  'sec.principle2': {
    AppLang.zh: '复合命令拆段逐查，取最严结果。安全检查是独立代码路径，模型越狱也绕不过。',
    AppLang.en: 'Compound commands split & checked per segment, strictest wins. Guard is an independent code path — jailbreaks cannot bypass it.'
  },
  'sec.denySection': {AppLang.zh: 'DENY · 直接拒绝（{n} 条）', AppLang.en: 'DENY · reject ({n})'},
  'sec.askSection': {AppLang.zh: 'ASK · 执行前确认（{n} 条）', AppLang.en: 'ASK · confirm first ({n})'},
  'sec.allowSection': {AppLang.zh: 'ALLOW · 默认放行', AppLang.en: 'ALLOW · default'},
  'sec.allowDesc': {
    AppLang.zh: '未命中以上规则的只读/安全命令（ls · cat · df · tail 等）',
    AppLang.en: 'Read-only/safe commands not matching above (ls · cat · df · tail …)'
  },

  // ========== 命令片段对话框 ==========
  'snip.title': {AppLang.zh: '命令片段', AppLang.en: 'Snippets'},
  'snip.clickToFill': {AppLang.zh: '点击填入输入框', AppLang.en: 'Click to fill input'},
  'snip.empty': {AppLang.zh: '暂无片段，点下方新增', AppLang.en: 'No snippets, add one below'},
  'snip.addNew': {AppLang.zh: '新增片段', AppLang.en: 'New Snippet'},
  'snip.nameOpt': {AppLang.zh: '名称（可选）', AppLang.en: 'Name (optional)'},
  'snip.cmdHint': {AppLang.zh: '命令，如 df -h', AppLang.en: 'Command, e.g. df -h'},

  // ========== SFTP ==========
  'sftp.local': {AppLang.zh: '本地', AppLang.en: 'Local'},
  'sftp.upload': {AppLang.zh: '上传', AppLang.en: 'Upload'},
  'sftp.download': {AppLang.zh: '下载', AppLang.en: 'Download'},
  'sftp.hint': {
    AppLang.zh: '双击文件用内置编辑器打开 · 拖拽可跨栏传输',
    AppLang.en: 'Double-click to open in editor · drag to transfer across panes'
  },

  // ========== 状态栏 ==========
  'status.guard': {AppLang.zh: '门禁 ', AppLang.en: 'Guard '},
  'status.blocked': {AppLang.zh: '阻止{n}', AppLang.en: 'blocked {n}'},
  'status.pending': {AppLang.zh: '待确认{n}', AppLang.en: 'pending {n}'},
  'status.model': {AppLang.zh: '模型 ', AppLang.en: 'Model '},
  'status.notConfigured': {AppLang.zh: '未配置', AppLang.en: 'Not set'},
  'status.context': {AppLang.zh: '上下文 ', AppLang.en: 'Context '},
  'status.rounds': {AppLang.zh: '{n} 轮', AppLang.en: '{n} rounds'},
  'status.connected': {AppLang.zh: '已连接', AppLang.en: 'Connected'},
  'status.connecting': {AppLang.zh: '连接中…', AppLang.en: 'Connecting…'},
  'status.connFail': {AppLang.zh: '连接失败', AppLang.en: 'Connect failed'},
  'status.disconnected': {AppLang.zh: '未连接', AppLang.en: 'Disconnected'},

  // ========== 终端面板 ==========
  'term.startFail': {AppLang.zh: '[终端启动失败: {err}]', AppLang.en: '[Terminal start failed: {err}]'},
  'term.connectFirst': {AppLang.zh: '连接主机后可在此使用交互式终端', AppLang.en: 'Connect a host to use the interactive terminal'},

  // ========== 设置中心 ==========
  'settings.comingSoon': {AppLang.zh: '即将推出…', AppLang.en: 'Coming soon…'},
};

/// 当前语言下取文案
class L10n {
  final AppLang lang;
  const L10n(this.lang);

  /// 取文案。可选 params 替换占位符：译文里写 {name}，传 {'name': 'x'} 即替换。
  String t(String key, [Map<String, String>? params]) {
    final entry = _dict[key];
    var s = entry == null ? key : (entry[lang] ?? entry[AppLang.zh] ?? key);
    if (params != null) {
      params.forEach((k, v) => s = s.replaceAll('{$k}', v));
    }
    return s;
  }
}
