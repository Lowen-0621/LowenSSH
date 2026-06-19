<script setup>
// 底部对话输入（仿 Claude composer）：圆角输入框 + 发送/停止按钮。
// 思考中呼吸动画也放这上方：模型推理但还没吐字时显示「思考中…」脉冲。
import { computed } from 'vue'
import { useAgentStream } from '@/composables/useAgentStream'

const { conn, isRunning, hasSession, connLive, isThinking, run, stop } = useAgentStream()

// 断线态（已有会话但常驻连接已回收）不能发，引导开新会话
const broken = computed(() => hasSession.value && !connLive.value)

// 能否提交：有任务文字；首轮还需主机；非断线；不在运行中
const canSend = computed(() => {
  if (isRunning.value || broken.value) return false
  if (!conn.task.trim()) return false
  if (!hasSession.value && !conn.host.trim()) return false
  return true
})

function onSubmit() {
  if (!canSend.value) return
  run({ ...conn })
  conn.task = ''   // 清空便于连续追问
}

// 回车发送，但避开输入法合成：中文输入法选词时的回车 e.isComposing 为 true，
// 此时回车意在上屏候选词而非发送，直接放行让输入法处理。
// Shift/Ctrl/Alt/Meta + 回车保留为换行（不发送）。
function onEnter(e) {
  if (e.isComposing || e.keyCode === 229) return  // 229 是部分浏览器合成态的兜底
  if (e.shiftKey || e.ctrlKey || e.altKey || e.metaKey) return
  e.preventDefault()
  onSubmit()
}
</script>

<template>
  <div class="composer-wrap">
    <!-- 思考中：呼吸动画 -->
    <transition name="fade">
      <div v-if="isThinking" class="thinking">
        <span class="breath" />
        <span class="thinking-text">思考中</span>
        <span class="dots"><i /><i /><i /></span>
      </div>
    </transition>

    <form class="composer" :class="{ disabled: broken }" @submit.prevent="onSubmit">
      <textarea
        v-model="conn.task"
        class="input"
        rows="1"
        :placeholder="broken
          ? '连接已断开，请在右侧开新会话重连'
          : (hasSession ? '继续追问，例如：那内存呢' : '输入运维任务，例如：看下根分区还剩多少空间')"
        :disabled="isRunning || broken"
        @keydown.enter="onEnter"
      />
      <button v-if="!isRunning" type="submit" class="send" :disabled="!canSend" title="发送">
        <span class="arrow">↑</span>
      </button>
      <button v-else type="button" class="stop" title="停止" @click="stop">
        <span class="square" />
      </button>
    </form>
  </div>
</template>

<style scoped>
.composer-wrap {
  flex-shrink: 0;
  padding: var(--sp-3) var(--sp-6) var(--sp-4);
  max-width: 860px;
  width: 100%;
  margin: 0 auto;
}

/* —— 思考中呼吸动画 —— */
.thinking {
  display: flex;
  align-items: center;
  gap: var(--sp-2);
  padding: 0 var(--sp-2) var(--sp-2);
  color: var(--muted);
  font-size: 13px;
}
/* 呼吸圆点：缩放 + 透明度脉冲 */
.breath {
  width: 10px;
  height: 10px;
  border-radius: 50%;
  background: var(--model);
  animation: breath 1.6s ease-in-out infinite;
}
@keyframes breath {
  0%, 100% { transform: scale(0.7); opacity: 0.4; }
  50%      { transform: scale(1.15); opacity: 1; }
}
.thinking-text { letter-spacing: 0.5px; }
/* 三个点依次明灭 */
.dots { display: inline-flex; gap: 3px; }
.dots i {
  width: 3px;
  height: 3px;
  border-radius: 50%;
  background: var(--muted);
  animation: dot 1.4s ease-in-out infinite;
}
.dots i:nth-child(2) { animation-delay: 0.2s; }
.dots i:nth-child(3) { animation-delay: 0.4s; }
@keyframes dot {
  0%, 60%, 100% { opacity: 0.25; }
  30%           { opacity: 1; }
}

/* —— 输入框 —— */
.composer {
  display: flex;
  align-items: flex-end;
  gap: var(--sp-2);
  padding: var(--sp-2) var(--sp-2) var(--sp-2) var(--sp-4);
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 14px;
  transition: border-color 0.15s;
}
.composer:focus-within { border-color: var(--model); }
.composer.disabled { opacity: 0.7; }

.input {
  flex: 1;
  resize: none;
  border: none;
  outline: none;
  background: transparent;
  color: var(--text);
  font-family: var(--font-ui);
  font-size: 15px;
  line-height: 1.5;
  max-height: 160px;
  padding: var(--sp-2) 0;
}
.input::placeholder { color: var(--muted); }
.input:disabled { cursor: not-allowed; }

/* 发送 / 停止按钮：圆形 */
.send, .stop {
  flex-shrink: 0;
  width: 36px;
  height: 36px;
  border: none;
  border-radius: 50%;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: background 0.15s, opacity 0.15s;
}
.send {
  background: var(--model);
  color: #0d1117;
}
.send:disabled {
  background: var(--border);
  color: var(--muted);
  cursor: not-allowed;
}
.arrow { font-size: 18px; font-weight: 700; line-height: 1; }
.stop { background: var(--danger); }
.square {
  width: 12px;
  height: 12px;
  background: #fff;
  border-radius: 2px;
}

/* 思考动画进出过渡 */
.fade-enter-active, .fade-leave-active { transition: opacity 0.2s; }
.fade-enter-from, .fade-leave-to { opacity: 0; }
</style>
