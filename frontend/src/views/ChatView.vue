<script setup>
// 图形版消息流：气泡 + 卡片混排（定位「这是个产品」）。
// 只负责渲染 messages（连接表单挪到右栏 ConnectionPanel，输入框挪到底部 ChatComposer）。
// 命令与输出默认收进「执行了 N 条命令」折叠条，对话主线只见模型说话 + 最终结论。
import { ref, nextTick, watch, computed, onMounted } from 'vue'
import { marked } from 'marked'
import DOMPurify from 'dompurify'
import { useAgentStream } from '@/composables/useAgentStream'

const { messages, sessionLoadTick } = useAgentStream()

// web 对话形式定位「这是个产品」：对话主线只见模型说话 + 最终结论，
// 命令与输出（tool_call/tool_result）一律不渲染。要看命令执行过程切到终端视图。
const renderUnits = computed(() =>
  messages.value.filter((m) => m.type !== 'tool_call' && m.type !== 'tool_result')
)

// marked：换行即换行（GFM 风格），更贴合模型输出习惯
marked.setOptions({ breaks: true, gfm: true })

// 把模型输出的 markdown 渲染成 HTML。模型输出可能夹带 SSH 回显，
// 必须用 DOMPurify 净化防 XSS（远端内容不可信）。
function renderMd(text) {
  if (!text) return ''
  return DOMPurify.sanitize(marked.parse(String(text)))
}

const streamEl = ref(null)

// 自动滚动：仅当用户当前贴着底部时才跟随，向上翻看不打断。
// 距底 80px 内算"贴底"——容忍流式追加时的轻微抖动。
function scrollToBottomIfNear() {
  const el = streamEl.value
  if (!el) return
  const nearBottom = el.scrollHeight - el.scrollTop - el.clientHeight < 80
  if (nearBottom) el.scrollTop = el.scrollHeight
}

// 强制滚到底：切换会话时内容（表格/markdown/代码块）撑开高度会滞后多帧，
// 长会话甚至几百毫秒后才布局完。固定帧数会停在"还没撑开"的旧高度。
// 改用「钉底时间窗」：开窗后只要容器高度还在变（ResizeObserver）就重滚，直到稳定。
const PIN_WINDOW_MS = 800
let pinUntil = 0

function scrollNow() {
  const el = streamEl.value
  if (el) el.scrollTop = el.scrollHeight
}

// 开启钉底时间窗：立即滚一次，并在窗口期内持续盯高度变化重滚。
function forceScrollBottom() {
  scrollNow()
  pinUntil = Date.now() + PIN_WINDOW_MS
  // rAF 兜底：即使没有 resize 事件，也连续重滚覆盖渐进布局。
  const tick = () => {
    if (!streamEl.value) return
    scrollNow()
    if (Date.now() < pinUntil) requestAnimationFrame(tick)
  }
  requestAnimationFrame(tick)
}

// 切换会话/重载历史：switchSession 成功回灌后递增 sessionLoadTick，
// watch 这个数字（而非 messages 引用）100% 可靠触发，不受单例引用相等/mount 时序影响。
watch(
  () => sessionLoadTick.value,
  async () => {
    await nextTick()
    forceScrollBottom()
  }
)

// 新消息进来：贴底才跟随
watch(
  () => messages.value.length,
  async () => {
    await nextTick()
    scrollToBottomIfNear()
  }
)
// 流式 token 追加：贴底才跟随
watch(
  () => messages.value[messages.value.length - 1]?.text,
  async () => {
    await nextTick()
    scrollToBottomIfNear()
  }
)

// 首次进入页面：从主机簿点服务器进来时，switchSession 在组件 mount 前
// 就把 messages 填好了，上面的 watch（无 immediate）不会触发 → 停在顶部。
// 这里在 mount 后主动钉底一次，覆盖"进入即满"的场景。
onMounted(async () => {
  await nextTick()
  if (messages.value.length > 0) forceScrollBottom()
})
</script>

<template>
  <div ref="streamEl" class="stream">
    <div v-if="messages.length === 0" class="empty">
      右侧填入目标服务器，底部告诉我你想做什么。我会自己连上去一步步排查、操作，过程中的命令默认折叠，你只看结论。危险命令会被安全门禁拦下。
    </div>

    <template v-for="m in renderUnits" :key="m.id">
      <!-- 用户任务 -->
      <div v-if="m.type === 'user'" class="msg user">
        <div class="bubble">{{ m.task }}</div>
      </div>

      <!-- 模型思考过程：灰色气泡，可折叠，流式实时显示"在想什么" -->
      <div v-else-if="m.type === 'reasoning'" class="msg assistant">
        <div class="role">思考</div>
        <div class="bubble think-bubble">
          <span class="think-text">{{ m.text }}</span><span v-if="m.streaming" class="caret">▋</span>
        </div>
      </div>

      <!-- 模型说话 -->
      <div v-else-if="m.type === 'assistant'" class="msg assistant">
        <div class="role">模型</div>
        <div class="bubble model-bubble">
          <span v-if="m.streaming">{{ m.text }}<span class="caret">▋</span></span>
          <span v-else class="md-body md-rendered" v-html="renderMd(m.text)" />
        </div>
      </div>

      <!-- 命令与输出不在对话视图渲染（要看执行过程切终端视图） -->

      <!-- 被安全门禁拦截：全场最重 -->
      <div v-else-if="m.type === 'blocked'" class="card blocked-card">
        <div class="card-head danger">
          <span class="block-icon">⛔</span>命令被安全门禁拦截
        </div>
        <pre class="code">{{ m.command }}</pre>
        <div class="reason">拦截原因：{{ m.reason }}</div>
      </div>

      <!-- 最终结论：内容已在上方流式气泡显示过时，这里只标记完成、不重复渲染 -->
      <div v-else-if="m.type === 'done'" class="done-block">
        <div class="done-tag"><span class="dot ok" />任务完成</div>
        <div v-if="!m.redundant" class="done-text md-body" v-html="renderMd(m.finalText)" />
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
/* 思考气泡：弱化为灰色、小字、半透明，与正式回答区分 */
.think-bubble {
  background: transparent;
  border: 1px dashed var(--border);
  color: var(--muted);
  font-size: 12px;
  line-height: 1.6;
  opacity: 0.85;
}
.think-text { white-space: pre-wrap; }
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
