<script setup>
// 图形版消息流：气泡 + 卡片混排（定位「这是个产品」）。
// 只负责渲染 messages（连接表单挪到右栏 ConnectionPanel，输入框挪到底部 ChatComposer）。
// 按 6 类事件分别渲染，blocked 视觉权重最重（红边框 + 染底 + 图标）。
import { ref, nextTick, watch } from 'vue'
import { marked } from 'marked'
import DOMPurify from 'dompurify'
import { useAgentStream } from '@/composables/useAgentStream'

const { messages } = useAgentStream()

// marked：换行即换行（GFM 风格），更贴合模型输出习惯
marked.setOptions({ breaks: true, gfm: true })

// 把模型输出的 markdown 渲染成 HTML。模型输出可能夹带 SSH 回显，
// 必须用 DOMPurify 净化防 XSS（远端内容不可信）。
function renderMd(text) {
  if (!text) return ''
  return DOMPurify.sanitize(marked.parse(String(text)))
}

const streamEl = ref(null)

// 记录哪些工具结果被用户手动展开了（key 用 message id）
const expanded = ref({})
function toggleExpand(id) {
  expanded.value[id] = !expanded.value[id]
}

// 长输出默认只显示前这么多行，其余折叠
const COLLAPSE_LINES = 8

// 新消息进来自动滚到底
watch(
  () => messages.value.length,
  async () => {
    await nextTick()
    if (streamEl.value) streamEl.value.scrollTop = streamEl.value.scrollHeight
  }
)
// 流式 token 追加时也跟随滚动
watch(
  () => messages.value[messages.value.length - 1]?.text,
  async () => {
    await nextTick()
    if (streamEl.value) streamEl.value.scrollTop = streamEl.value.scrollHeight
  }
)

// 美化命令参数：tool_call 的 args 是 JSON 字符串，尽量取出 command 字段展示
function prettyArgs(args) {
  try {
    const obj = JSON.parse(args)
    if (obj.command) return obj.command
    return JSON.stringify(obj, null, 2)
  } catch {
    return args
  }
}

// 解析工具结果 summary：后端格式形如 "exitCode=0\nstdout:\n<内容>\nstderr:\n<内容>"
// 可能被 JSON 序列化带了外层引号和转义。统一拆成 { exitCode, body }，body 是干净的命令输出。
function parseResult(summary) {
  if (summary == null) return { exitCode: null, body: '' }
  let s = String(summary)
  // 去掉外层字面引号并还原转义。注意：被截断的长结果结尾可能没有配对引号（… 替换掉了），
  // 所以不依赖 endsWith('"')，只要以 " 开头就尽力反转义；JSON.parse 失败再手工剥引号兜底。
  if (s.startsWith('"')) {
    try {
      s = JSON.parse(s)
    } catch {
      // 结尾引号被截断时 JSON.parse 会失败：手工去头引号 + 反转义常见转义符
      s = s.slice(1).replace(/\\n/g, '\n').replace(/\\t/g, '\t').replace(/\\"/g, '"').replace(/\\\\/g, '\\')
    }
  }
  let exitCode = null
  const m = s.match(/^exitCode=(-?\d+)\s*/)
  if (m) {
    exitCode = Number(m[1])
    s = s.slice(m[0].length)
  }
  // 去掉 stdout:/stderr: 这类标签前缀，只留正文；两段都有时用分隔
  s = s.replace(/^stdout:\s*\n?/i, '').replace(/\nstderr:\s*\n?/i, '\n').trimEnd()
  return { exitCode, body: s }
}

// 把正文按折叠规则切分：返回 { head, rest, total }，rest 为空表示无需折叠
function splitLines(body) {
  const lines = body.split('\n')
  if (lines.length <= COLLAPSE_LINES) {
    return { head: body, rest: '', total: lines.length }
  }
  return {
    head: lines.slice(0, COLLAPSE_LINES).join('\n'),
    rest: lines.slice(COLLAPSE_LINES).join('\n'),
    total: lines.length
  }
}
</script>

<template>
  <div ref="streamEl" class="stream">
    <div v-if="messages.length === 0" class="empty">
      右侧填入目标服务器，底部输入运维任务，看 AI Agent 如何一步步排查。危险命令会被安全门禁拦下。
    </div>

    <template v-for="m in messages" :key="m.id">
      <!-- 用户任务 -->
      <div v-if="m.type === 'user'" class="msg user">
        <div class="bubble">{{ m.task }}</div>
      </div>

      <!-- 模型说话 -->
      <div v-else-if="m.type === 'assistant'" class="msg assistant">
        <div class="role">模型</div>
        <div class="bubble model-bubble">
          <span v-if="m.streaming">{{ m.text }}<span class="caret">▋</span></span>
          <span v-else class="md-body md-rendered" v-html="renderMd(m.text)" />
        </div>
      </div>

      <!-- 要跑命令：单行紧凑，前缀 $ 像终端 -->
      <div v-else-if="m.type === 'tool_call'" class="cmd-line">
        <span class="cmd-prompt">$</span>
        <code class="cmd-text">{{ prettyArgs(m.args) }}</code>
      </div>

      <!-- 命令结果：退出码徽章 + 输出（长则折叠） -->
      <div v-else-if="m.type === 'tool_result'" class="result-block">
        <template v-for="(parsed, _) in [parseResult(m.summary)]" :key="0">
          <div class="result-meta">
            <span
              class="exit-badge"
              :class="parsed.exitCode === 0 ? 'ok' : (parsed.exitCode == null ? 'muted' : 'bad')"
            >
              {{ parsed.exitCode == null ? (m.executed ? '已执行' : '未执行') : `exit ${parsed.exitCode}` }}
            </span>
            <span class="result-name">{{ m.name }}</span>
          </div>
          <template v-if="parsed.body" v-for="(seg, __) in [splitLines(parsed.body)]" :key="1">
            <pre v-if="!seg.rest" class="output">{{ seg.head }}</pre>
            <template v-else>
              <pre class="output">{{ expanded[m.id] ? parsed.body : seg.head }}</pre>
              <button class="expand-btn" @click="toggleExpand(m.id)">
                {{ expanded[m.id] ? '收起' : `展开剩余 ${seg.total - 8} 行` }}
              </button>
            </template>
          </template>
        </template>
      </div>

      <!-- 被安全门禁拦截：全场最重 -->
      <div v-else-if="m.type === 'blocked'" class="card blocked-card">
        <div class="card-head danger">
          <span class="block-icon">⛔</span>命令被安全门禁拦截
        </div>
        <pre class="code">{{ m.command }}</pre>
        <div class="reason">拦截原因：{{ m.reason }}</div>
      </div>

      <!-- 最终结论 -->
      <div v-else-if="m.type === 'done'" class="done-block">
        <div class="done-tag"><span class="dot ok" />任务完成</div>
        <div class="done-text md-body" v-html="renderMd(m.finalText)" />
      </div>

      <!-- 错误 -->
      <div v-else-if="m.type === 'error'" class="card error-card">
        <div class="card-head error"><span class="dot error" />错误</div>
        <div class="reason">{{ m.message }}</div>
      </div>

      <!-- 会话过期：常驻连接被回收，提示开新会话重连 -->
      <div v-else-if="m.type === 'session_expired'" class="card expired-card">
        <div class="card-head expired"><span class="dot expired" />连接已断开</div>
        <div class="reason">{{ m.message }}</div>
      </div>
    </template>
  </div>
</template>

<style scoped>
/* —— 消息流 —— */
.stream {
  height: 100%;
  overflow-y: auto;
  padding: var(--sp-6) var(--sp-6) var(--sp-8);
  max-width: 860px;
  width: 100%;
  margin: 0 auto;
  display: flex;
  flex-direction: column;
  gap: var(--sp-3);
}
/* 流是 flex 列容器，子项默认会被压缩导致卡片塌成一条线，统一禁止收缩 */
.stream > * { flex-shrink: 0; }
.empty {
  color: var(--muted);
  text-align: center;
  margin-top: var(--sp-8);
  font-size: 14px;
  line-height: 1.8;
}

.msg { display: flex; flex-direction: column; }
.msg.user { align-items: flex-end; }
.msg .role { font-size: 11px; color: var(--muted); margin-bottom: var(--sp-1); }
.bubble {
  max-width: 80%;
  padding: var(--sp-2) var(--sp-3);
  border-radius: 8px;
  font-size: 14px;
  white-space: pre-wrap;
  word-break: break-word;
}
.msg.user .bubble { background: var(--model); color: #0d1117; font-weight: 500; }
.model-bubble { background: var(--surface); border: 1px solid var(--border); color: var(--text); }
.caret { color: var(--model); animation: blink 1s step-end infinite; }
@keyframes blink { 50% { opacity: 0; } }

/* —— 卡片通用 —— */
.card {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 8px;
  overflow: hidden;
}
.card-head {
  display: flex;
  align-items: center;
  gap: var(--sp-2);
  padding: var(--sp-2) var(--sp-3);
  font-size: 13px;
  font-weight: 600;
  border-bottom: 1px solid var(--border);
}
.dot { width: 8px; height: 8px; border-radius: 50%; flex-shrink: 0; }
.dot.tool { background: var(--tool); }
.dot.ok { background: var(--ok); }
.dot.danger { background: var(--danger); }
.dot.error { background: var(--error); }
.dot.expired { background: var(--warn, #d8862a); }

.code {
  margin: 0;
  padding: var(--sp-3);
  background: var(--surface-2);
  font-family: var(--font-mono);
  font-size: 13px;
  line-height: 1.5;
  white-space: pre-wrap;
  word-break: break-word;
  color: var(--text);
  max-height: 360px;
  overflow: auto;
}

/* —— 命令调用：单行终端风，视觉权重轻 —— */
.cmd-line {
  display: flex;
  align-items: baseline;
  gap: var(--sp-2);
  padding: var(--sp-2) var(--sp-3);
  background: var(--surface-2);
  border-radius: 6px;
  border-left: 2px solid var(--tool);
  font-family: var(--font-mono);
  font-size: 13px;
  overflow-x: auto;
}
.cmd-prompt { color: var(--tool); font-weight: 700; flex-shrink: 0; }
.cmd-text { color: var(--text); white-space: pre; }

/* —— 命令结果：紧贴上一条命令，退出码徽章 + 干净输出 —— */
.result-block {
  margin-top: calc(var(--sp-3) * -1 + 2px);  /* 上移贴近对应命令，视觉成组 */
  padding-left: var(--sp-3);
}
.result-meta {
  display: flex;
  align-items: center;
  gap: var(--sp-2);
  margin-bottom: var(--sp-1);
}
.exit-badge {
  font-family: var(--font-mono);
  font-size: 11px;
  font-weight: 600;
  padding: 1px 7px;
  border-radius: 4px;
  line-height: 1.6;
}
.exit-badge.ok { color: var(--ok); background: rgba(63, 185, 80, 0.12); }
.exit-badge.bad { color: var(--error); background: rgba(248, 81, 73, 0.12); }
.exit-badge.muted { color: var(--muted); background: var(--surface-2); }
.result-name { font-size: 11px; color: var(--muted); font-family: var(--font-mono); }
.output {
  margin: 0;
  padding: var(--sp-2) var(--sp-3);
  background: var(--surface-2);
  border-radius: 6px;
  font-family: var(--font-mono);
  font-size: 12.5px;
  line-height: 1.5;
  white-space: pre-wrap;
  word-break: break-word;
  color: var(--text-dim, var(--text));
  max-height: 320px;
  overflow: auto;
}
.expand-btn {
  margin-top: var(--sp-1);
  border: none;
  background: transparent;
  color: var(--tool);
  cursor: pointer;
  font-size: 12px;
  padding: 2px 0;
}
.expand-btn:hover { text-decoration: underline; }

/* —— blocked：全场最重 —— */
.blocked-card {
  border: 1px solid var(--danger);
  border-left: 4px solid var(--danger);
  background: var(--danger-bg);
}
.blocked-card .card-head.danger {
  color: var(--danger);
  border-bottom-color: var(--danger);
  font-size: 14px;
}
.block-icon { font-size: 16px; }
.blocked-card .code { background: rgba(248, 81, 73, 0.06); }
.reason { padding: var(--sp-2) var(--sp-3); font-size: 13px; color: var(--text); }
.blocked-card .reason { color: var(--danger); }

/* error：品红 */
.error-card { border-color: var(--error); }
.error-card .card-head.error { color: var(--error); }
.expired-card { border-color: var(--warn, #d8862a); }
.expired-card .card-head.expired { color: var(--warn, #d8862a); }

/* —— done 结论 —— */
.done-block {
  border-top: 1px solid var(--border);
  padding-top: var(--sp-4);
  margin-top: var(--sp-2);
}
.done-tag {
  display: flex;
  align-items: center;
  gap: var(--sp-2);
  font-size: 12px;
  color: var(--ok);
  margin-bottom: var(--sp-2);
}
.done-text {
  font-size: 15px;
  line-height: 1.7;
  word-break: break-word;
}

/* —— markdown 正文排版（模型说话 + 最终结论共用）—— */
/* 流式纯文本阶段保留换行；渲染成 HTML 后由块级元素自己控制间距 */
.md-body { font-size: 15px; line-height: 1.7; word-break: break-word; }
/* 渲染态（v-html）里重置父级 pre-wrap，避免块级元素间多余空白 */
.md-rendered, .done-text.md-body { white-space: normal; }
.model-bubble .md-rendered { display: block; }
.md-body :deep(h1),
.md-body :deep(h2),
.md-body :deep(h3),
.md-body :deep(h4) {
  margin: var(--sp-3) 0 var(--sp-2);
  font-weight: 600;
  line-height: 1.35;
}
.md-body :deep(h1) { font-size: 18px; }
.md-body :deep(h2) { font-size: 16px; }
.md-body :deep(h3) { font-size: 15px; color: var(--text); }
.md-body :deep(h4) { font-size: 14px; color: var(--muted); }
.md-body :deep(p) { margin: var(--sp-2) 0; }
.md-body :deep(ul),
.md-body :deep(ol) { margin: var(--sp-2) 0; padding-left: 1.4em; }
.md-body :deep(li) { margin: 2px 0; }
.md-body :deep(strong) { font-weight: 600; color: var(--text); }
.md-body :deep(a) { color: var(--ok); text-decoration: none; }
.md-body :deep(a:hover) { text-decoration: underline; }
.md-body :deep(code) {
  font-family: var(--font-mono);
  font-size: 13px;
  background: var(--surface-2);
  padding: 1px 5px;
  border-radius: 4px;
}
.md-body :deep(pre) {
  margin: var(--sp-2) 0;
  padding: var(--sp-3);
  background: var(--surface-2);
  border: 1px solid var(--border);
  border-radius: 8px;
  overflow-x: auto;
}
.md-body :deep(pre code) { background: none; padding: 0; font-size: 12.5px; }
.md-body :deep(blockquote) {
  margin: var(--sp-2) 0;
  padding-left: var(--sp-3);
  border-left: 3px solid var(--border);
  color: var(--muted);
}
/* 表格：紧凑、暗色描边、首行加重 */
.md-body :deep(table) {
  border-collapse: collapse;
  margin: var(--sp-2) 0;
  font-size: 13px;
  width: 100%;
}
.md-body :deep(th),
.md-body :deep(td) {
  border: 1px solid var(--border);
  padding: 5px 10px;
  text-align: left;
}
.md-body :deep(th) { background: var(--surface-2); font-weight: 600; }
.md-body :deep(*:first-child) { margin-top: 0; }
.md-body :deep(*:last-child) { margin-bottom: 0; }
</style>
