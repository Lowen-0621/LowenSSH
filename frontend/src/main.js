import { createApp } from 'vue'
import { createRouter, createWebHashHistory } from 'vue-router'
import App from './App.vue'
import HostsView from './views/HostsView.vue'
import ChatView from './views/ChatView.vue'
import TerminalView from './views/TerminalView.vue'
import './styles/global.css'

// 路由：/hosts 主机簿主页（选服务器入口）→ 进入主机后到 /chat 三栏对话页
// /terminal 是对话的终端版呈现。用 hash 模式：静态部署到 static 目录无需后端配 fallback
const router = createRouter({
  history: createWebHashHistory(),
  routes: [
    { path: '/', redirect: '/hosts' },
    { path: '/hosts', name: 'hosts', component: HostsView },
    { path: '/chat', name: 'chat', component: ChatView },
    { path: '/terminal', name: 'terminal', component: TerminalView }
  ]
})

createApp(App).use(router).mount('#app')
