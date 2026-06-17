import { createApp } from 'vue'
import { createRouter, createWebHashHistory } from 'vue-router'
import App from './App.vue'
import ChatView from './views/ChatView.vue'
import TerminalView from './views/TerminalView.vue'
import './styles/global.css'

// 路由：图形版 / 与终端版 /terminal 切换同一会话的两种呈现
// 用 hash 模式：静态部署到 Spring Boot static 目录下无需后端配 history fallback
const router = createRouter({
  history: createWebHashHistory(),
  routes: [
    { path: '/', name: 'chat', component: ChatView },
    { path: '/terminal', name: 'terminal', component: TerminalView }
  ]
})

createApp(App).use(router).mount('#app')
