<script setup>
// 右侧连接栏：
//  - 首轮（无会话）：完整连接表单 host/port/user/password
//  - 续聊 + 连接存活：已连接信息条 + 新会话
//  - 续聊 + 连接已断（超时回收）：断线提示，引导开新会话重连
// 底部放图形/终端视图切换开关。task 输入在底部 composer，这里不放。
import { useRoute, useRouter } from 'vue-router'
import { useAgentStream } from '@/composables/useAgentStream'

const { conn, isRunning, hasSession, connLive, newSession } = useAgentStream()
const route = useRoute()
const router = useRouter()
</script>

<template>
  <div class="panel">
    <div class="panel-head">连接</div>

    <!-- 首轮：完整连接表单 -->
    <div v-if="!hasSession" class="form">
      <label class="field">
        <span>主机</span>
        <input v-model="conn.host" placeholder="192.168.1.10" :disabled="isRunning" />
      </label>
      <div class="field-row">
        <label class="field port">
          <span>端口</span>
          <input v-model="conn.port" type="number" placeholder="22" :disabled="isRunning" />
        </label>
        <label class="field grow">
          <span>用户</span>
          <input v-model="conn.user" placeholder="root" :disabled="isRunning" />
        </label>
      </div>
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
      <p class="hint">填好后在底部告诉我你想做什么，我会自己连上去执行。</p>
    </div>

    <!-- 续聊 + 连接存活 -->
    <div v-else-if="connLive" class="session-state">
      <div class="conn-info">
        <span class="dot ok" />
        <div class="conn-text">
          <div class="conn-host">{{ conn.user }}@{{ conn.host }}</div>
          <div class="conn-sub">连接常驻 · 可继续追问</div>
        </div>
      </div>
      <button class="btn-new" :disabled="isRunning" @click="newSession">新会话</button>
    </div>

    <!-- 续聊 + 连接已断 -->
    <div v-else class="session-state">
      <div class="conn-info broken">
        <span class="dot danger" />
        <div class="conn-text">
          <div class="conn-host">{{ conn.user }}@{{ conn.host }}</div>
          <div class="conn-sub warn">常驻连接已断开（空闲超时回收）</div>
        </div>
      </div>
      <p class="hint">这条会话的 SSH 连接已被回收，无法继续追问。开个新会话重新连接吧。</p>
      <button class="btn-new" :disabled="isRunning" @click="newSession">新会话</button>
    </div>

    <!-- 视图切换：图形 / 终端 -->
    <div class="view-switch-wrap">
      <div class="switch-label">呈现方式</div>
      <div class="view-switch">
        <button
          :class="{ active: route.name === 'chat' }"
          @click="router.push('/')"
        >图形</button>
        <button
          :class="{ active: route.name === 'terminal' }"
          @click="router.push('/terminal')"
        >终端</button>
      </div>
    </div>
  </div>
</template>

<style scoped>
.panel {
  width: 320px;        /* 固定宽度，折叠时父级裁掉 */
  height: 100%;
  display: flex;
  flex-direction: column;
  padding: var(--sp-4);
  overflow-y: auto;
}
.panel-head {
  font-size: 13px;
  font-weight: 600;
  color: var(--muted);
  margin-bottom: var(--sp-3);
}

/* —— 表单 —— */
.form { display: flex; flex-direction: column; gap: var(--sp-3); }
.field-row { display: flex; gap: var(--sp-3); }
.field {
  display: flex;
  flex-direction: column;
  gap: var(--sp-1);
  font-size: 12px;
  color: var(--muted);
}
.field.port { width: 84px; flex-shrink: 0; }
.field.grow { flex: 1; }
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
.field input:focus { border-color: var(--model); }
.field input:disabled { opacity: 0.6; }
.hint {
  font-size: 12px;
  color: var(--muted);
  line-height: 1.6;
  margin: var(--sp-1) 0 0;
}

/* —— 续聊态 —— */
.session-state { display: flex; flex-direction: column; gap: var(--sp-3); }
.conn-info {
  display: flex;
  align-items: center;
  gap: var(--sp-2);
  padding: var(--sp-3);
  border: 1px solid var(--border);
  border-radius: 8px;
  background: var(--surface-2);
}
.conn-info.broken { border-color: var(--danger); }
.dot { width: 8px; height: 8px; border-radius: 50%; flex-shrink: 0; }
.dot.ok { background: var(--ok); }
.dot.danger { background: var(--danger); }
.conn-text { min-width: 0; }
.conn-host {
  font-size: 14px;
  color: var(--text);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.conn-sub { font-size: 12px; color: var(--muted); margin-top: 2px; }
.conn-sub.warn { color: var(--danger); }

.btn-new {
  padding: var(--sp-2) var(--sp-4);
  border: 1px solid var(--border);
  border-radius: 6px;
  background: var(--surface-2);
  color: var(--text);
  font-size: 13px;
  cursor: pointer;
}
.btn-new:hover:not(:disabled) { border-color: var(--model); }
.btn-new:disabled { opacity: 0.5; cursor: not-allowed; }

/* —— 视图切换 —— */
.view-switch-wrap { margin-top: auto; padding-top: var(--sp-4); }
.switch-label { font-size: 12px; color: var(--muted); margin-bottom: var(--sp-2); }
.view-switch {
  display: flex;
  border: 1px solid var(--border);
  border-radius: 6px;
  overflow: hidden;
}
.view-switch button {
  flex: 1;
  padding: var(--sp-2);
  border: none;
  background: transparent;
  color: var(--muted);
  font-size: 13px;
  cursor: pointer;
  transition: background 0.15s, color 0.15s;
}
.view-switch button.active { background: var(--surface-2); color: var(--text); }
.view-switch button:hover:not(.active) { color: var(--text); }
</style>
