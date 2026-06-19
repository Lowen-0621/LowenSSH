<script setup>
// 终端版消息流：仿 SSH 会话的单列 log 流，全等宽字体（定位「这是个工具」）。
// 只负责渲染 log（连接表单挪到右栏，输入框挪到底部 composer）。
import { ref, nextTick, watch } from 'vue'
import { useAgentStream } from '@/composables/useAgentStream'

const { messages, conn } = useAgentStream()

const logEl = ref(null)

watch(
  () => [messages.value.length, messages.value[messages.value.length - 1]?.text],
  async () => {
    await nextTick()
    if (logEl.value) logEl.value.scrollTop = logEl.value.scrollHeight
  }
)

function command(args) {
  try {
    const obj = JSON.parse(args)
    return obj.command || JSON.stringify(obj)
  } catch {
    return args
  }
}
</script>

<template>
  <div ref="logEl" class="log">
    <div v-if="messages.length === 0" class="ln dim"># 右侧填连接，底部输入任务，等待执行…</div>

    <template v-for="m in messages" :key="m.id">
      <!-- 用户任务 -->
      <div v-if="m.type === 'user'" class="ln task">
        <span class="prompt">{{ conn.user || 'root' }}@{{ conn.host || 'host' }}:~$</span>
        <span class="task-text"> {{ m.task }}</span>
      </div>

      <!-- 模型推理：注释行风格 -->
      <div v-else-if="m.type === 'assistant'" class="ln model">
        <span class="hash"># </span>{{ m.text }}<span v-if="m.streaming" class="caret">▋</span>
      </div>

      <!-- 要跑的命令 -->
      <div v-else-if="m.type === 'tool_call'" class="ln cmd">
        <span class="dollar">$</span> {{ command(m.args) }}
      </div>

      <!-- 命令输出：缩进 -->
      <div v-else-if="m.type === 'tool_result'" class="ln out" :class="{ skipped: !m.executed }">
        <span v-if="!m.executed" class="skip-tag">[未执行] </span>{{ m.summary }}
      </div>

      <!-- 被拦截：整行红底 -->
      <div v-else-if="m.type === 'blocked'" class="ln blocked">
        <span class="tag">[BLOCKED]</span> {{ m.command }}
        <div class="blocked-reason">↳ {{ m.reason }}</div>
      </div>

      <!-- 结论 -->
      <div v-else-if="m.type === 'done'" class="ln done">
        <span class="ok-tag">[DONE]</span> {{ m.finalText }}
      </div>

      <!-- 错误 -->
      <div v-else-if="m.type === 'error'" class="ln err">
        <span class="tag">[ERROR]</span> {{ m.message }}
      </div>
    </template>
  </div>
</template>

<style scoped>
.log {
  height: 100%;
  overflow-y: auto;
  padding: var(--sp-4) var(--sp-6) var(--sp-8);
  background: #0a0d12;
  font-family: var(--font-mono);
  font-size: 13px;
  line-height: 1.65;
  white-space: pre-wrap;
  word-break: break-word;
}
.ln { white-space: pre-wrap; word-break: break-word; }
.ln.dim { color: var(--muted); }

.ln.task { margin-top: var(--sp-2); }
.prompt { color: var(--ok); }
.task-text { color: var(--text); font-weight: 600; }

.ln.model { color: var(--muted); }
.ln.model .hash { color: var(--model); }
.caret { color: var(--model); animation: blink 1s step-end infinite; }
@keyframes blink { 50% { opacity: 0; } }

.ln.cmd { color: var(--tool); }
.ln.cmd .dollar { color: var(--ok); }

.ln.out {
  color: var(--text);
  padding-left: var(--sp-3);
  border-left: 2px solid var(--border);
  margin-left: 2px;
}
.ln.out.skipped { color: var(--muted); }
.skip-tag { color: var(--danger); }

/* —— blocked：整行红底，终端里最醒目 —— */
.ln.blocked {
  background: var(--danger-bg);
  border-left: 3px solid var(--danger);
  padding: var(--sp-1) var(--sp-2);
  margin: var(--sp-1) 0;
  color: var(--danger);
}
.ln.blocked .tag { font-weight: 700; }
.blocked-reason { color: var(--danger); opacity: 0.85; padding-left: var(--sp-3); }

.ln.done { color: var(--ok); margin-top: var(--sp-2); }
.ln.done .ok-tag { font-weight: 700; }

.ln.err { color: var(--error); }
.ln.err .tag { font-weight: 700; }
</style>
