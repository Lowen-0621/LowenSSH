<script setup>
// 终端版界面：仿 SSH 会话的单列 log 流，全等宽字体。
// 与图形版共享同一份 useAgentStream 状态，只是把同样的事件渲染成「终端行」。
// 定位「这是个工具」，对应 DESIGN 第 7 节的两界面对比。
import { ref, nextTick, watch } from 'vue'
import { useAgentStream } from '@/composables/useAgentStream'

const { messages, status, isRunning, conn, run, stop } = useAgentStream()

const logEl = ref(null)
const showConn = ref(true) // 连接面板可折叠，跑起来后收起更像终端

watch(
  () => [messages.value.length, messages.value[messages.value.length - 1]?.text],
  async () => {
    await nextTick()
    if (logEl.value) logEl.value.scrollTop = logEl.value.scrollHeight
  }
)

function onRun() {
  if (isRunning.value) return
  if (!conn.host || !conn.task) return
  showConn.value = false
  run({ ...conn })
}

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
  <div class="term-view">
    <!-- 连接条：折叠态只显示一行 prompt -->
    <div class="conn-bar">
      <button class="toggle" @click="showConn = !showConn">
        {{ showConn ? '▾' : '▸' }} {{ conn.user || 'root' }}@{{ conn.host || 'host' }}
      </button>
      <span class="status-tag" :class="status">{{ status }}</span>
    </div>

    <form v-if="showConn" class="conn-form" @submit.prevent="onRun">
      <div class="line">
        <span class="k">host</span>
        <input v-model="conn.host" placeholder="192.168.1.10" :disabled="isRunning" />
        <span class="k">port</span>
        <input v-model="conn.port" type="number" class="sm" :disabled="isRunning" />
        <span class="k">user</span>
        <input v-model="conn.user" class="sm" :disabled="isRunning" />
        <span class="k">pass</span>
        <input
          v-model="conn.password"
          type="password"
          autocomplete="off"
          class="sm"
          :disabled="isRunning"
        />
      </div>
      <div class="line">
        <span class="k">task</span>
        <input
          v-model="conn.task"
          class="grow"
          placeholder="输入运维任务，回车执行"
          :disabled="isRunning"
          @keydown.enter.prevent="onRun"
        />
        <button v-if="!isRunning" type="submit" class="go" :disabled="!conn.host || !conn.task">
          run
        </button>
        <button v-else type="button" class="go stop" @click="stop">stop</button>
      </div>
    </form>

    <!-- log 流 -->
    <div ref="logEl" class="log">
      <div v-if="messages.length === 0" class="ln dim"># 等待任务…</div>

      <template v-for="m in messages" :key="m.id">
        <!-- 用户任务 -->
        <div v-if="m.type === 'user'" class="ln task">
          <span class="prompt">{{ conn.user || 'root' }}@{{ conn.host }}:~$</span>
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
  </div>
</template>

<style scoped>
.term-view {
  display: flex;
  flex-direction: column;
  height: 100%;
  background: #0a0d12;
  font-family: var(--font-mono);
  font-size: 13px;
  line-height: 1.65;
}

/* —— 连接条 —— */
.conn-bar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: var(--sp-2) var(--sp-4);
  border-bottom: 1px solid var(--border);
  flex-shrink: 0;
}
.toggle {
  background: none;
  border: none;
  color: var(--ok);
  font-family: var(--font-mono);
  font-size: 13px;
  cursor: pointer;
  padding: 0;
}
.status-tag {
  font-size: 11px;
  padding: 2px 8px;
  border-radius: 3px;
  color: var(--muted);
  border: 1px solid var(--border);
}
.status-tag.running { color: var(--tool); border-color: var(--tool); }
.status-tag.done { color: var(--ok); border-color: var(--ok); }
.status-tag.error { color: var(--error); border-color: var(--error); }

/* —— 连接表单 —— */
.conn-form {
  padding: var(--sp-3) var(--sp-4);
  border-bottom: 1px solid var(--border);
  flex-shrink: 0;
  display: flex;
  flex-direction: column;
  gap: var(--sp-2);
}
.line {
  display: flex;
  align-items: center;
  gap: var(--sp-2);
}
.k {
  color: var(--muted);
  user-select: none;
}
.conn-form input {
  background: #0a0d12;
  border: none;
  border-bottom: 1px solid var(--border);
  color: var(--text);
  font-family: var(--font-mono);
  font-size: 13px;
  padding: 2px 4px;
  outline: none;
  flex: 1;
}
.conn-form input.sm { flex: 0 0 96px; }
.conn-form input.grow { flex: 1; }
.conn-form input:focus { border-bottom-color: var(--ok); }
.go {
  background: none;
  border: 1px solid var(--ok);
  color: var(--ok);
  font-family: var(--font-mono);
  padding: 2px 14px;
  border-radius: 3px;
  cursor: pointer;
}
.go:disabled { opacity: 0.4; cursor: not-allowed; }
.go.stop { border-color: var(--danger); color: var(--danger); }

/* —— log —— */
.log {
  flex: 1;
  min-height: 0;
  overflow-y: auto;
  padding: var(--sp-3) var(--sp-4) var(--sp-8);
  white-space: pre-wrap;
  word-break: break-word;
}
.ln {
  white-space: pre-wrap;
  word-break: break-word;
}
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
.blocked-reason {
  color: var(--danger);
  opacity: 0.85;
  padding-left: var(--sp-3);
}

.ln.done { color: var(--ok); margin-top: var(--sp-2); }
.ln.done .ok-tag { font-weight: 700; }

.ln.err { color: var(--error); }
.ln.err .tag { font-weight: 700; }
</style>
