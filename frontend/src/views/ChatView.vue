<script setup>
// 图形版对话界面：顶部连接表单卡 + 消息流（气泡 + 卡片混排）
// 定位「这是个产品」。消费共享的 useAgentStream，按 6 类事件分别渲染，
// blocked 事件视觉权重最重（红边框 + 染底 + 图标），对应 DESIGN 第 6 节。
import { ref, nextTick, watch } from 'vue'
import { useAgentStream } from '@/composables/useAgentStream'

const { messages, status, isRunning, conn, run, stop } = useAgentStream()

const streamEl = ref(null)

// 新消息进来自动滚到底
watch(
  () => messages.value.length,
  async () => {
    await nextTick()
    if (streamEl.value) {
      streamEl.value.scrollTop = streamEl.value.scrollHeight
    }
  }
)
// 流式 token 追加时也要跟随滚动
watch(
  () => messages.value[messages.value.length - 1]?.text,
  async () => {
    await nextTick()
    if (streamEl.value) {
      streamEl.value.scrollTop = streamEl.value.scrollHeight
    }
  }
)

function onSubmit() {
  if (isRunning.value) return
  if (!conn.host || !conn.task) return
  run({ ...conn })
}

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
</script>

<template>
  <div class="chat-view">
    <!-- 连接 + 任务表单 -->
    <form class="conn-card" @submit.prevent="onSubmit">
      <div class="conn-row">
        <label class="field grow">
          <span>主机</span>
          <input v-model="conn.host" placeholder="192.168.1.10" :disabled="isRunning" />
        </label>
        <label class="field port">
          <span>端口</span>
          <input v-model="conn.port" type="number" placeholder="22" :disabled="isRunning" />
        </label>
        <label class="field">
          <span>用户</span>
          <input v-model="conn.user" placeholder="root" :disabled="isRunning" />
        </label>
        <label class="field">
          <span>密码</span>
          <input
            v-model="conn.password"
            type="password"
            autocomplete="off"
            placeholder="••••••"
            :disabled="isRunning"
          />
        </label>
      </div>
      <div class="conn-row">
        <label class="field grow">
          <span>运维任务</span>
          <input
            v-model="conn.task"
            placeholder="例如：看下根分区还剩多少空间"
            :disabled="isRunning"
            @keydown.enter.prevent="onSubmit"
          />
        </label>
        <button v-if="!isRunning" type="submit" class="btn-run" :disabled="!conn.host || !conn.task">
          执行
        </button>
        <button v-else type="button" class="btn-stop" @click="stop">停止</button>
      </div>
    </form>

    <!-- 消息流 -->
    <div ref="streamEl" class="stream">
      <div v-if="messages.length === 0" class="empty">
        填入目标服务器和运维任务，看 AI Agent 如何一步步排查 —— 危险命令会被安全门禁拦下。
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
            {{ m.text }}<span v-if="m.streaming" class="caret">▋</span>
          </div>
        </div>

        <!-- 要跑命令 -->
        <div v-else-if="m.type === 'tool_call'" class="card tool-card">
          <div class="card-head">
            <span class="dot tool" />执行命令 · {{ m.name }}
          </div>
          <pre class="code">{{ prettyArgs(m.args) }}</pre>
        </div>

        <!-- 命令结果 -->
        <div v-else-if="m.type === 'tool_result'" class="card result-card">
          <div class="card-head">
            <span class="dot" :class="m.executed ? 'ok' : 'danger'" />
            {{ m.executed ? '执行结果' : '未执行' }} · {{ m.name }}
          </div>
          <pre class="code">{{ m.summary }}</pre>
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
          <div class="done-text">{{ m.finalText }}</div>
        </div>

        <!-- 错误 -->
        <div v-else-if="m.type === 'error'" class="card error-card">
          <div class="card-head error"><span class="dot error" />错误</div>
          <div class="reason">{{ m.message }}</div>
        </div>
      </template>
    </div>
  </div>
</template>

<style scoped>
.chat-view {
  display: flex;
  flex-direction: column;
  height: 100%;
  max-width: 880px;
  margin: 0 auto;
  width: 100%;
}

/* —— 连接表单卡 —— */
.conn-card {
  margin: var(--sp-4);
  padding: var(--sp-4);
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 8px;
  flex-shrink: 0;
}
.conn-row {
  display: flex;
  gap: var(--sp-3);
  align-items: flex-end;
}
.conn-row + .conn-row {
  margin-top: var(--sp-3);
}
.field {
  display: flex;
  flex-direction: column;
  gap: var(--sp-1);
  font-size: 12px;
  color: var(--muted);
}
.field.grow {
  flex: 1;
}
.field.port input {
  width: 72px;
}
.field input {
  background: var(--bg);
  border: 1px solid var(--border);
  border-radius: 6px;
  padding: var(--sp-2) var(--sp-3);
  color: var(--text);
  font-size: 14px;
  font-family: var(--font-ui);
  outline: none;
}
.field input:focus {
  border-color: var(--model);
}
.field input:disabled {
  opacity: 0.6;
}

.btn-run,
.btn-stop {
  padding: var(--sp-2) var(--sp-6);
  border: none;
  border-radius: 6px;
  font-size: 14px;
  font-weight: 600;
  cursor: pointer;
  height: 37px;
}
.btn-run {
  background: var(--ok-dim);
  color: #fff;
}
.btn-run:disabled {
  background: var(--border);
  color: var(--muted);
  cursor: not-allowed;
}
.btn-stop {
  background: var(--danger);
  color: #fff;
}

/* —— 消息流 —— */
.stream {
  flex: 1;
  min-height: 0;
  overflow-y: auto;
  padding: 0 var(--sp-4) var(--sp-8);
  display: flex;
  flex-direction: column;
  gap: var(--sp-3);
}
/* 流是 flex 列容器，子项默认会被压缩导致卡片塌成一条线，统一禁止收缩 */
.stream > * {
  flex-shrink: 0;
}
.empty {
  color: var(--muted);
  text-align: center;
  margin-top: var(--sp-8);
  font-size: 14px;
  line-height: 1.8;
}

.msg {
  display: flex;
  flex-direction: column;
}
.msg.user {
  align-items: flex-end;
}
.msg .role {
  font-size: 11px;
  color: var(--muted);
  margin-bottom: var(--sp-1);
}
.bubble {
  max-width: 80%;
  padding: var(--sp-2) var(--sp-3);
  border-radius: 8px;
  font-size: 14px;
  white-space: pre-wrap;
  word-break: break-word;
}
.msg.user .bubble {
  background: var(--model);
  color: #0d1117;
  font-weight: 500;
}
.model-bubble {
  background: var(--surface);
  border: 1px solid var(--border);
  color: var(--text);
}
.caret {
  color: var(--model);
  animation: blink 1s step-end infinite;
}
@keyframes blink {
  50% {
    opacity: 0;
  }
}

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
.dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  flex-shrink: 0;
}
.dot.tool { background: var(--tool); }
.dot.ok { background: var(--ok); }
.dot.danger { background: var(--danger); }
.dot.error { background: var(--error); }

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

/* tool_call：琥珀 */
.tool-card .card-head {
  color: var(--tool);
  background: var(--tool-bg);
}
/* tool_result：绿 */
.result-card .card-head {
  color: var(--ok);
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
.block-icon {
  font-size: 16px;
}
.blocked-card .code {
  background: rgba(248, 81, 73, 0.06);
}
.reason {
  padding: var(--sp-2) var(--sp-3);
  font-size: 13px;
  color: var(--text);
}
.blocked-card .reason {
  color: var(--danger);
}

/* error：品红 */
.error-card {
  border-color: var(--error);
}
.error-card .card-head.error {
  color: var(--error);
}

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
  white-space: pre-wrap;
  word-break: break-word;
}
</style>
