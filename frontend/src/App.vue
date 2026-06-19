<script setup>
// 应用外壳：三栏布局（仿 Claude web）
//   ┌──────┬─────────────────┬──────┐
//   │ 左栏  │   对话主区        │ 右栏  │
//   │ 历史  │ (消息流+思考动画) │ 连接  │
//   │ 会话  ├─────────────────┤ 配置  │
//   │      │   底部输入框      │      │
//   └──────┴─────────────────┴──────┘
// 左右栏可折叠（width 过渡）。主区是 router-view（图形/终端两种消息流呈现），
// 底部 composer 固定。连接表单、视图切换都收进右栏。
import { onMounted, computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useAgentStream } from '@/composables/useAgentStream'
import HistorySidebar from '@/components/HistorySidebar.vue'
import ConnectionPanel from '@/components/ConnectionPanel.vue'
import ChatComposer from '@/components/ChatComposer.vue'

const route = useRoute()
const router = useRouter()
const { leftCollapsed, rightCollapsed, toggleLeft, toggleRight, loadSessions, leaveHost, conn } =
  useAgentStream()

// 主机簿页（/hosts）全屏渲染，不套三栏外壳
const isHostsPage = computed(() => route.name === 'hosts')

// 返回主机簿：断开当前主机上下文并跳转
function backToHosts() {
  leaveHost()
  router.push('/hosts')
}

// 首次进入拉一次会话列表
onMounted(loadSessions)
</script>

<template>
  <!-- 主机簿主页：全屏渲染 -->
  <router-view v-if="isHostsPage" />

  <!-- 对话页：三栏外壳 -->
  <div v-else class="app-shell">
    <header class="app-header">
      <div class="header-left">
        <button class="back-btn" title="返回主机簿" @click="backToHosts">← 主机簿</button>
        <button class="icon-btn" :title="leftCollapsed ? '展开历史' : '收起历史'" @click="toggleLeft">
          <span class="icon-burger" />
        </button>
        <div class="brand">
          <span class="brand-mark">▢</span>
          <span class="brand-name">LowenSSH</span>
          <span class="brand-sub">{{ conn.host ? `${conn.user}@${conn.host}` : 'AI 运维 Agent' }}</span>
        </div>
      </div>
      <button class="icon-btn" :title="rightCollapsed ? '展开连接' : '收起连接'" @click="toggleRight">
        <span class="icon-panel" />
      </button>
    </header>

    <div class="app-body">
      <!-- 左侧历史栏 -->
      <aside class="side-left" :class="{ collapsed: leftCollapsed }">
        <HistorySidebar />
      </aside>

      <!-- 中间对话主区 -->
      <main class="app-main">
        <div class="main-stream">
          <router-view />
        </div>
        <ChatComposer />
      </main>

      <!-- 右侧连接栏 -->
      <aside class="side-right" :class="{ collapsed: rightCollapsed }">
        <ConnectionPanel />
      </aside>
    </div>
  </div>
</template>

<style scoped>
.app-shell {
  display: flex;
  flex-direction: column;
  height: 100%;
}

.app-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: var(--sp-2) var(--sp-4);
  border-bottom: 1px solid var(--border);
  background: var(--surface);
  flex-shrink: 0;
}
.header-left {
  display: flex;
  align-items: center;
  gap: var(--sp-3);
}

/* 返回主机簿按钮 */
.back-btn {
  border: 1px solid var(--border);
  background: transparent;
  color: var(--muted);
  padding: 4px 10px;
  border-radius: 6px;
  cursor: pointer;
  font-size: 13px;
  white-space: nowrap;
  transition: background 0.15s, color 0.15s;
}
.back-btn:hover { background: var(--surface-2); color: var(--text); }

.brand {
  display: flex;
  align-items: baseline;
  gap: var(--sp-2);
}
.brand-mark { color: var(--ok); font-size: 18px; }
.brand-name { font-weight: 600; font-size: 16px; letter-spacing: 0.3px; }
.brand-sub { color: var(--muted); font-size: 12px; }

/* 顶部图标按钮 */
.icon-btn {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 32px;
  height: 32px;
  border: 1px solid transparent;
  border-radius: 6px;
  background: transparent;
  cursor: pointer;
  color: var(--muted);
  transition: background 0.15s, color 0.15s;
}
.icon-btn:hover { background: var(--surface-2); color: var(--text); }
/* 汉堡图标（三横线） */
.icon-burger, .icon-burger::before, .icon-burger::after {
  display: block;
  width: 16px;
  height: 2px;
  background: currentColor;
  border-radius: 1px;
  position: relative;
}
.icon-burger::before, .icon-burger::after {
  content: '';
  position: absolute;
  left: 0;
}
.icon-burger::before { top: -5px; }
.icon-burger::after { top: 5px; }
/* 右栏图标（带竖线的面板） */
.icon-panel {
  display: block;
  width: 16px;
  height: 14px;
  border: 2px solid currentColor;
  border-radius: 3px;
  position: relative;
}
.icon-panel::after {
  content: '';
  position: absolute;
  right: 3px;
  top: -2px;
  bottom: -2px;
  width: 2px;
  background: currentColor;
}

/* —— 三栏主体 —— */
.app-body {
  flex: 1;
  min-height: 0;
  display: flex;
  overflow: hidden;
}

.side-left,
.side-right {
  flex-shrink: 0;
  background: var(--surface);
  overflow: hidden;
  transition: width 0.22s ease, opacity 0.18s ease;
}
.side-left {
  width: 260px;
  border-right: 1px solid var(--border);
}
.side-right {
  width: 320px;
  border-left: 1px solid var(--border);
}
/* 折叠：宽度归零并淡出，内容裁掉 */
.side-left.collapsed,
.side-right.collapsed {
  width: 0;
  opacity: 0;
  border-color: transparent;
}

.app-main {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  overflow: hidden;
}
.main-stream {
  flex: 1;
  min-height: 0;
  overflow: hidden;
}
</style>
