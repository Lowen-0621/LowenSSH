import { ref, reactive, computed } from 'vue'

/**
 * useAgentStream —— 消费后端 SSE 端点 POST /api/agent/stream 的核心 composable。
 *
 * 为什么不用 EventSource：浏览器原生 EventSource 只支持 GET，而后端是 POST（要带
 * host/password/task 请求体）。所以用 fetch + ReadableStream 手动按 SSE 协议解析。
 *
 * 后端每条 SSE 形如：
 *   event: tool_call
 *   data: {"name":"execCommand","args":"{...}"}
 *   （空行分隔事件）
 *
 * 6 类事件：token / tool_call / tool_result / blocked / done / error
 * 产出一个响应式 messages 列表，图形版和终端版各自渲染。
 *
 * token 事件做特殊处理：连续 token 会合并进同一条 assistant 消息（流式追加），
 * 而不是每个 token 一条，否则消息列表会爆炸。
 *
 * 模块级单例：state 提到模块顶层，两个视图（图形/终端）共用同一份会话与连接参数，
 * 切换视图不丢消息——对应 DESIGN「同一会话能切换看两种呈现」。
 */

// —— 模块级共享 state（单例） ——
// 消息流：每条 { id, type, ...payload }
const messages = ref([])
// 运行状态：idle / running / done / error
const status = ref('idle')
// 会话列表（左侧历史栏）：每项 { id, title, host, user, port, updatedAt }
const sessions = ref([])
// 主机簿列表（主页选主机）：每项 { id, alias, host, port, user, hasPassword }
const hosts = ref([])
// 左右侧栏折叠状态（仿 Claude 可收起）
const leftCollapsed = ref(false)
const rightCollapsed = ref(false)
// 当前会话的常驻连接是否存活：切换旧会话时由后端告知，false 则续聊会断线提示
const connLive = ref(true)
// 连接 + 任务参数（两视图共享；密码只在内存，不持久化）
const conn = reactive({
  host: '',
  port: 22,
  user: 'root',
  password: '',
  task: ''
})

let controller = null
let seq = 0
// 当前会话 id：首轮为 null，收到 session_ready 后存下，后续请求带上以续聊
let currentSessionId = null
// 当前所在主机 id：从主机簿进入后存下，会话列表按它过滤、新会话挂到它下面
let currentHostId = null

export function useAgentStream() {
  const isRunning = computed(() => status.value === 'running')

  function nextId() {
    return ++seq
  }

  // 把一条事件并入 messages；token 合并进上一条 assistant 流式消息
  function pushEvent(type, payload) {
    if (type === 'token') {
      const last = messages.value[messages.value.length - 1]
      if (last && last.type === 'assistant' && last.streaming) {
        // 追加到正在流式输出的助手消息
        last.text += payload.text
        return
      }
      // 开一条新的流式助手消息
      messages.value.push({
        id: nextId(),
        type: 'assistant',
        text: payload.text,
        streaming: true
      })
      return
    }

    // 非 token 事件到来，先把正在流式的助手消息定型（streaming=false）
    const last = messages.value[messages.value.length - 1]
    if (last && last.type === 'assistant' && last.streaming) {
      last.streaming = false
    }

    messages.value.push({ id: nextId(), type, ...payload })
  }

  /**
   * 解析一段 SSE 文本缓冲，返回剩余未完整的尾巴。
   * SSE 事件以空行（\n\n）分隔，每个事件含 event: 和 data: 行。
   */
  function parseSSEBuffer(buffer, onEvent) {
    const parts = buffer.split('\n\n')
    // 最后一段可能不完整，留回缓冲
    const rest = parts.pop()
    for (const block of parts) {
      if (!block.trim()) continue
      let eventName = 'message'
      let dataLines = []
      for (const line of block.split('\n')) {
        if (line.startsWith('event:')) {
          eventName = line.slice(6).trim()
        } else if (line.startsWith('data:')) {
          dataLines.push(line.slice(5).trim())
        }
      }
      const dataRaw = dataLines.join('\n')
      if (!dataRaw) continue
      let data
      try {
        data = JSON.parse(dataRaw)
      } catch {
        data = { raw: dataRaw }
      }
      onEvent(eventName, data)
    }
    return rest
  }

  // 把后端事件 record 映射成前端消息 payload
  function dispatch(eventName, data) {
    switch (eventName) {
      case 'session_ready':
        // 首轮建会话回传 sessionId，存下供后续续聊；不入消息流（纯协议事件）
        currentSessionId = data.sessionId
        connLive.value = true       // 刚建的连接当然是活的
        rightCollapsed.value = true // 连上后自动收起右栏连接配置，腾空间给对话
        loadSessions()              // 新会话已落库，刷新左栏列表
        break
      case 'token':
        pushEvent('token', { text: data.text ?? '' })
        break
      case 'tool_call':
        pushEvent('tool_call', { name: data.name, args: data.args })
        break
      case 'tool_result':
        pushEvent('tool_result', {
          name: data.name,
          summary: data.summary,
          executed: data.executed
        })
        break
      case 'blocked':
        pushEvent('blocked', { command: data.command, reason: data.reason })
        break
      case 'done':
        pushEvent('done', { finalText: data.finalText })
        status.value = 'done'
        break
      case 'error':
        pushEvent('error', { message: data.message })
        status.value = 'error'
        break
      case 'session_expired':
        // 续聊时常驻连接已被回收：锁住输入并切到断线态，展开右栏提示开新会话重连
        pushEvent('session_expired', { message: data.message })
        connLive.value = false
        rightCollapsed.value = false
        status.value = 'error'
        break
      default:
        // 未知事件类型，原样落一条，方便调试
        pushEvent('error', { message: `未知事件 ${eventName}: ${JSON.stringify(data)}` })
    }
  }

  /**
   * 发起一轮任务。
   * 首轮（currentSessionId 为 null）带连接信息建会话；续聊只带 sessionId + task，
   * 复用后端常驻连接，消息列表不清空（接续显示）。
   * @param {{host,port,user,password,task}} req 连接 + 任务参数
   */
  async function run(req) {
    if (status.value === 'running') return
    status.value = 'running'
    controller = new AbortController()

    // 回显用户任务（不回显密码）
    pushEvent('user', { task: req.task })

    // 续聊只带 sessionId + task；首轮带完整连接信息（含 hostId 把会话挂到主机下）
    const body = currentSessionId
      ? { sessionId: currentSessionId, task: req.task }
      : {
          hostId: currentHostId,
          host: req.host,
          port: Number(req.port) || 22,
          user: req.user,
          password: req.password,
          task: req.task
        }

    try {
      const resp = await fetch('/api/agent/stream', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Accept: 'text/event-stream'
        },
        body: JSON.stringify(body),
        signal: controller.signal
      })

      if (!resp.ok || !resp.body) {
        throw new Error(`HTTP ${resp.status}`)
      }

      const reader = resp.body.getReader()
      const decoder = new TextDecoder()
      let buffer = ''

      // 流式读取，逐块解析
      while (true) {
        const { done, value } = await reader.read()
        if (done) break
        buffer += decoder.decode(value, { stream: true })
        buffer = parseSSEBuffer(buffer, dispatch)
      }
      // 收尾：刷掉残留缓冲
      buffer += decoder.decode()
      parseSSEBuffer(buffer + '\n\n', dispatch)

      // 流正常结束但没收到 done/error（极少见），兜底标记完成
      if (status.value === 'running') {
        status.value = 'done'
      }
    } catch (e) {
      if (e.name === 'AbortError') {
        pushEvent('error', { message: '已停止' })
      } else {
        pushEvent('error', { message: `连接失败: ${e.message}` })
      }
      status.value = 'error'
    } finally {
      // 定型最后一条流式助手消息
      const last = messages.value[messages.value.length - 1]
      if (last && last.type === 'assistant' && last.streaming) {
        last.streaming = false
      }
      controller = null
    }
  }

  // 中途停止
  function stop() {
    if (controller) {
      controller.abort()
    }
  }

  // 开新会话：同一主机下再开一轮。清空消息和 sessionId，保留 currentHostId 和连接信息，
  // 下一次 run 会在该主机下新建会话并复用/重建常驻连接。
  function newSession() {
    if (status.value === 'running') return
    messages.value = []
    currentSessionId = null
    connLive.value = true
    status.value = 'idle'
    // 保留 conn.host/port/user（同主机），只清空任务和密码
    conn.password = ''
    conn.task = ''
  }

  // 离开主机回主机簿：清空主机/会话上下文，刷新主机列表
  function leaveHost() {
    currentHostId = null
    currentSessionId = null
    messages.value = []
    sessions.value = []
    status.value = 'idle'
    conn.host = ''
    conn.port = 22
    conn.user = 'root'
    conn.password = ''
    conn.task = ''
  }

  // 拉取会话列表，刷新左侧历史栏（按当前主机过滤）
  async function loadSessions() {
    try {
      const url = currentHostId
        ? `/api/agent/sessions?hostId=${currentHostId}`
        : '/api/agent/sessions'
      const resp = await fetch(url)
      if (!resp.ok) return
      sessions.value = await resp.json()
    } catch {
      // 列表拉取失败不影响主流程，静默
    }
  }

  // —— 主机簿 ——
  // 拉主机列表
  async function loadHosts() {
    try {
      const resp = await fetch('/api/hosts')
      if (!resp.ok) return
      hosts.value = await resp.json()
    } catch {
      // 静默
    }
  }

  // 新增主机（密码加密存后端）
  async function createHost(payload) {
    const resp = await fetch('/api/hosts', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    })
    if (!resp.ok) throw new Error(`HTTP ${resp.status}`)
    await loadHosts()
    return await resp.json()
  }

  // 删除主机
  async function deleteHost(id) {
    await fetch(`/api/hosts/${id}`, { method: 'DELETE' })
    await loadHosts()
  }

  /**
   * 进入主机：后端建/复用常驻连接，拿回 sessionId。
   * 成功后设好 currentHostId/currentSessionId、回填连接信息、拉该主机历史会话。
   * password 仅当主机未存密码时传入补连。
   * 返回 { ok, error }，调用方据此决定是否跳转对话页。
   */
  async function enterHost(host, password) {
    try {
      const resp = await fetch(`/api/hosts/${host.id}/connect`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ password: password || null })
      })
      const data = await resp.json().catch(() => ({}))
      if (!resp.ok || !data.sessionId) {
        return { ok: false, error: data.error || `连接失败 (HTTP ${resp.status})` }
      }
      currentHostId = host.id
      currentSessionId = data.sessionId
      connLive.value = true
      conn.host = host.host
      conn.port = host.port || 22
      conn.user = host.user || 'root'
      conn.password = ''
      conn.task = ''
      messages.value = []
      status.value = 'idle'
      await loadSessions()
      return { ok: true }
    } catch (e) {
      return { ok: false, error: `连接失败: ${e.message}` }
    }
  }

  // 把后端历史消息（type=user/assistant/tool_call/tool_result）转成前端 messages 格式
  function historyToMessages(list) {
    return (list || []).map((h) => {
      switch (h.type) {
        case 'user':
          return { id: nextId(), type: 'user', task: h.text }
        case 'assistant':
          return { id: nextId(), type: 'assistant', text: h.text, streaming: false }
        case 'tool_call':
          // 后端把命令放在 summary，前端 tool_call 渲染读 args，包成 {command} 复用 prettyArgs
          return { id: nextId(), type: 'tool_call', name: h.name, args: JSON.stringify({ command: h.summary }) }
        case 'tool_result':
          // 历史回看统一视为已执行（被拦截的在库里也是 tool 结果，summary 自带说明）
          return { id: nextId(), type: 'tool_result', name: h.name || '', summary: h.summary, executed: true }
        default:
          return { id: nextId(), type: 'assistant', text: h.text || '', streaming: false }
      }
    })
  }

  /**
   * 切换到某个历史会话：拉历史回灌消息区，填回连接信息。
   * 后端返回 live 表示常驻连接是否还活着——活着可直接续聊，否则视图提示需重连。
   */
  async function switchSession(id) {
    if (status.value === 'running') return
    try {
      const resp = await fetch(`/api/agent/sessions/${id}/messages`)
      if (!resp.ok) throw new Error(`HTTP ${resp.status}`)
      const detail = await resp.json()
      currentSessionId = id
      connLive.value = !!detail.live
      conn.host = detail.host || ''
      conn.port = detail.port || 22
      conn.user = detail.user || 'root'
      conn.password = ''        // 密码不回显，断线重连时再让用户填
      conn.task = ''
      messages.value = historyToMessages(detail.messages)
      status.value = 'idle'
    } catch (e) {
      messages.value = [{ id: nextId(), type: 'error', message: `加载会话失败: ${e.message}` }]
    }
  }

  // 是否处于续聊态（已建会话），视图据此折叠连接表单
  const hasSession = computed(() => currentSessionId !== null)

  // 是否已进入某台主机（主机簿模式下决定能否使用对话页）
  const hasHost = computed(() => currentHostId !== null)
  const activeHostId = computed(() => currentHostId)

  // 当前高亮的会话 id（左栏据此标记选中项）
  const activeSessionId = computed(() => currentSessionId)

  // 思考中：正在运行，且最后一条不是正在流式输出的 assistant（即模型还没开口吐字）
  // 也包含跑命令后等待下一轮模型响应的间隙
  const isThinking = computed(() => {
    if (status.value !== 'running') return false
    const last = messages.value[messages.value.length - 1]
    // 最后一条是流式 assistant 且已有文字 = 正在说话，不算思考
    if (last && last.type === 'assistant' && last.streaming && last.text) return false
    return true
  })

  // 切换左/右侧栏折叠
  function toggleLeft() {
    leftCollapsed.value = !leftCollapsed.value
  }
  function toggleRight() {
    rightCollapsed.value = !rightCollapsed.value
  }

  return {
    messages, status, isRunning, hasSession, conn, run, stop, newSession,
    sessions, loadSessions, switchSession, activeSessionId, connLive,
    isThinking, leftCollapsed, rightCollapsed, toggleLeft, toggleRight,
    hosts, loadHosts, createHost, deleteHost, enterHost, leaveHost,
    hasHost, activeHostId
  }
}
