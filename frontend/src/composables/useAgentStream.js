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
      default:
        // 未知事件类型，原样落一条，方便调试
        pushEvent('error', { message: `未知事件 ${eventName}: ${JSON.stringify(data)}` })
    }
  }

  /**
   * 发起一轮任务。
   * @param {{host,port,user,password,task}} req 连接 + 任务参数
   */
  async function run(req) {
    if (status.value === 'running') return
    messages.value = []
    status.value = 'running'
    controller = new AbortController()

    // 回显用户任务（不回显密码）
    pushEvent('user', { task: req.task })

    try {
      const resp = await fetch('/api/agent/stream', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Accept: 'text/event-stream'
        },
        body: JSON.stringify({
          host: req.host,
          port: Number(req.port) || 22,
          user: req.user,
          password: req.password,
          task: req.task
        }),
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

  return { messages, status, isRunning, conn, run, stop }
}
