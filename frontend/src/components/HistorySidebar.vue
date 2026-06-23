<script setup>
// 左侧历史栏：新会话按钮 + 会话列表（仿 Claude 左栏）。
// 点击某会话载入历史回看；当前会话高亮。
import { useAgentStream } from '@/composables/useAgentStream'

const { sessions, activeSessionId, switchSession, newSession, isRunning } = useAgentStream()

function onPick(id) {
  if (isRunning.value) return       // 跑着的时候不切会话，避免状态错乱
  if (id === activeSessionId.value) return
  switchSession(id)
}
</script>

<template>
  <div class="history">
    <div class="history-head">
      <button class="new-chat" :disabled="isRunning" @click="newSession">
        <span class="plus">＋</span> 新会话
      </button>
    </div>

    <div class="history-list">
      <div v-if="sessions.length === 0" class="empty">还没有会话</div>

      <button
        v-for="s in sessions"
        :key="s.id"
        class="item"
        :class="{ active: s.id === activeSessionId }"
        :disabled="isRunning && s.id !== activeSessionId"
        @click="onPick(s.id)"
      >
        <div class="item-title">{{ s.title || '未命名任务' }}</div>
        <div class="item-meta">{{ s.user }}@{{ s.host }} · {{ s.updatedAt || '' }}</div>
      </button>
    </div>
  </div>
</template>

<style scoped>
.history {
  width: 260px;          /* 固定宽度，折叠时父级裁掉 */
  height: 100%;
  display: flex;
  flex-direction: column;
}

.history-head {
  padding: var(--sp-3);
  flex-shrink: 0;
}
.new-chat {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: var(--sp-2);
  width: 100%;
  padding: var(--sp-2) var(--sp-3);
  border: 1px solid var(--border);
  border-radius: 8px;
  background: var(--surface-2);
  color: var(--text);
  font-size: 14px;
  cursor: pointer;
  transition: border-color 0.15s, background 0.15s;
}
.new-chat:hover:not(:disabled) { border-color: var(--model); background: var(--surface); }
.new-chat:disabled { opacity: 0.5; cursor: not-allowed; }
.plus { font-size: 16px; line-height: 1; }

.history-list {
  flex: 1;
  min-height: 0;
  overflow-y: auto;
  padding: 0 var(--sp-2) var(--sp-3);
  display: flex;
  flex-direction: column;
  gap: 2px;
}
.empty {
  color: var(--muted);
  font-size: 13px;
  text-align: center;
  margin-top: var(--sp-6);
}

.item {
  display: block;
  width: 100%;
  text-align: left;
  padding: var(--sp-2) var(--sp-3);
  border: none;
  border-radius: 6px;
  background: transparent;
  color: var(--text);
  cursor: pointer;
  transition: background 0.12s;
}
.item:hover:not(:disabled):not(.active) { background: var(--surface-2); }
.item.active { background: var(--surface-2); }
.item:disabled { opacity: 0.5; cursor: not-allowed; }
.item-title {
  font-size: 13px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.item-meta {
  font-size: 11px;
  color: var(--muted);
  margin-top: 2px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
</style>
