<script setup>
// 应用外壳：顶部品牌 + 视图切换（图形 ⇄ 终端），下面是路由出口
import { useRoute } from 'vue-router'

const route = useRoute()
</script>

<template>
  <div class="app-shell">
    <header class="app-header">
      <div class="brand">
        <span class="brand-mark">▢</span>
        <span class="brand-name">XiaowenSSH</span>
        <span class="brand-sub">AI 运维 Agent</span>
      </div>
      <nav class="view-switch">
        <router-link to="/" :class="{ active: route.name === 'chat' }">图形</router-link>
        <router-link to="/terminal" :class="{ active: route.name === 'terminal' }">终端</router-link>
      </nav>
    </header>
    <main class="app-main">
      <router-view />
    </main>
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
  padding: var(--sp-3) var(--sp-6);
  border-bottom: 1px solid var(--border);
  background: var(--surface);
  flex-shrink: 0;
}

.brand {
  display: flex;
  align-items: baseline;
  gap: var(--sp-2);
}
.brand-mark {
  color: var(--ok);
  font-size: 18px;
}
.brand-name {
  font-weight: 600;
  font-size: 16px;
  letter-spacing: 0.3px;
}
.brand-sub {
  color: var(--muted);
  font-size: 12px;
}

/* 视图切换：分段控件风格 */
.view-switch {
  display: flex;
  border: 1px solid var(--border);
  border-radius: 6px;
  overflow: hidden;
}
.view-switch a {
  padding: var(--sp-1) var(--sp-4);
  color: var(--muted);
  font-size: 13px;
  background: transparent;
  transition: background 0.15s, color 0.15s;
}
.view-switch a.active {
  background: var(--surface-2);
  color: var(--text);
}
.view-switch a:hover:not(.active) {
  color: var(--text);
}

.app-main {
  flex: 1;
  min-height: 0;
  overflow: hidden;
}
</style>
