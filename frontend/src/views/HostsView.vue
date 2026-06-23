<script setup>
// 主机簿主页：选服务器入口（仿 Termius）。
// 卡片列表展示已存主机，点卡片连接进入对话页；右上「新增主机」加机器。
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useAgentStream } from '@/composables/useAgentStream'

const router = useRouter()
const { hosts, loadHosts, createHost, deleteHost, enterHost } = useAgentStream()

const showForm = ref(false)        // 新增主机表单弹层
const connecting = ref(null)       // 正在连接的主机 id（按钮转圈）
const errorMsg = ref('')           // 连接/操作错误提示
const form = ref({ alias: '', host: '', port: 22, user: 'root', password: '' })
// 主机未存密码时，点连接弹出补填密码
const pwdPrompt = ref({ open: false, host: null, password: '' })

onMounted(loadHosts)

// 点主机卡片 → 连接。无存密码的主机先弹补填框
async function onConnect(h) {
  if (connecting.value) return
  if (!h.hasPassword) {
    pwdPrompt.value = { open: true, host: h, password: '' }
    return
  }
  await doConnect(h, null)
}

async function doConnect(h, password) {
  errorMsg.value = ''
  connecting.value = h.id
  const res = await enterHost(h, password)
  connecting.value = null
  if (res.ok) {
    router.push('/chat')
  } else {
    errorMsg.value = res.error
  }
}

// 补填密码后连接
async function onPwdConfirm() {
  if (!pwdPrompt.value.password) return
  const h = pwdPrompt.value.host
  const pwd = pwdPrompt.value.password
  pwdPrompt.value.open = false
  await doConnect(h, pwd)
}

// 提交新增主机
async function onCreate() {
  errorMsg.value = ''
  if (!form.value.host || !form.value.user) {
    errorMsg.value = '请填写主机地址和用户名'
    return
  }
  try {
    await createHost({ ...form.value, port: Number(form.value.port) || 22 })
    showForm.value = false
    form.value = { alias: '', host: '', port: 22, user: 'root', password: '' }
  } catch (e) {
    errorMsg.value = `新增失败: ${e.message}`
  }
}

async function onDelete(h) {
  if (!confirm(`确定删除主机「${h.alias || h.host}」？历史对话仍保留，只是移出主机簿。`)) return
  await deleteHost(h.id)
}
</script>

<template>
  <div class="hosts-page">
    <header class="hosts-header">
      <div class="brand">
        <span class="brand-mark">▰</span>
        <span class="brand-name">LowenSSH</span>
        <span class="brand-sub">选择一台服务器开始</span>
      </div>
      <button class="btn-primary" @click="showForm = true">+ 新增主机</button>
    </header>

    <div v-if="errorMsg" class="alert">{{ errorMsg }}</div>

    <section class="host-grid">
      <article
        v-for="h in hosts"
        :key="h.id"
        class="host-card"
        :class="{ connecting: connecting === h.id }"
        @click="onConnect(h)"
      >
        <div class="host-icon">
          <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="1.6">
            <rect x="3" y="4" width="18" height="12" rx="1.5" />
            <path d="M8 20h8M12 16v4" />
          </svg>
        </div>
        <div class="host-info">
          <div class="host-title">{{ h.alias || h.host }}</div>
          <div class="host-sub">ssh, {{ h.user }}@{{ h.host }}:{{ h.port }}</div>
          <div v-if="!h.hasPassword" class="host-tag">未存密码</div>
        </div>
        <div class="host-actions">
          <span v-if="connecting === h.id" class="spinner" />
          <button v-else class="del-btn" title="删除" @click.stop="onDelete(h)">✕</button>
        </div>
      </article>

      <div v-if="hosts.length === 0" class="empty">
        还没有主机，点右上「新增主机」添加一台。
      </div>
    </section>

    <!-- 新增主机弹层 -->
    <div v-if="showForm" class="modal-mask" @click.self="showForm = false">
      <div class="modal">
        <h3>新增主机</h3>
        <label>别名（可选）<input v-model="form.alias" placeholder="如：京东云生产" /></label>
        <label>主机地址<input v-model="form.host" placeholder="192.168.1.10 或域名" /></label>
        <div class="row">
          <label class="flex2">用户名<input v-model="form.user" placeholder="root" /></label>
          <label class="flex1">端口<input v-model.number="form.port" type="number" placeholder="22" /></label>
        </div>
        <label>密码<input v-model="form.password" type="password" placeholder="加密保存，仅连接时使用" /></label>
        <div class="modal-actions">
          <button class="btn-ghost" @click="showForm = false">取消</button>
          <button class="btn-primary" @click="onCreate">保存</button>
        </div>
      </div>
    </div>

    <!-- 补填密码弹层（迁移出的无密码主机） -->
    <div v-if="pwdPrompt.open" class="modal-mask" @click.self="pwdPrompt.open = false">
      <div class="modal">
        <h3>输入密码连接</h3>
        <p class="modal-hint">该主机未保存密码，请输入以连接。</p>
        <label>密码<input v-model="pwdPrompt.password" type="password" autofocus @keyup.enter="onPwdConfirm" /></label>
        <div class="modal-actions">
          <button class="btn-ghost" @click="pwdPrompt.open = false">取消</button>
          <button class="btn-primary" @click="onPwdConfirm">连接</button>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.hosts-page {
  height: 100%;
  overflow-y: auto;
  padding: var(--sp-6);
  background: var(--bg);
}
.hosts-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: var(--sp-6);
}
.brand { display: flex; align-items: center; gap: var(--sp-3); }
/* 品牌 mark：青光方块，与顶栏 HUD 标识一致 */
.brand-mark {
  width: 30px;
  height: 30px;
  border-radius: 7px;
  display: grid;
  place-items: center;
  background: var(--hud-dim);
  border: 1px solid rgba(45, 212, 191, 0.4);
  color: var(--hud);
  font-family: var(--font-mono);
  font-weight: 700;
  font-size: 15px;
  box-shadow: 0 0 14px rgba(45, 212, 191, 0.25);
}
.brand-name { font-weight: 700; font-size: 19px; letter-spacing: 0.4px; }
.brand-sub { color: var(--muted); font-size: 13px; align-self: flex-end; padding-bottom: 2px; }

.alert {
  background: rgba(216, 60, 60, 0.12);
  border: 1px solid var(--error);
  color: var(--error);
  padding: var(--sp-3) var(--sp-4);
  border-radius: 8px;
  margin-bottom: var(--sp-4);
  font-size: 13px;
}

/* 主机卡片网格 */
.host-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
  gap: var(--sp-4);
}
.host-card {
  position: relative;
  display: flex;
  align-items: center;
  gap: var(--sp-3);
  padding: var(--sp-4);
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 12px;
  cursor: pointer;
  overflow: hidden;
  transition: border-color 0.15s, transform 0.1s, box-shadow 0.15s;
}
/* 左侧高亮条：默认收起，hover 时青光亮起，HUD 节点选中感 */
.host-card::before {
  content: '';
  position: absolute;
  left: 0;
  top: 0;
  bottom: 0;
  width: 3px;
  background: var(--hud);
  box-shadow: 0 0 10px var(--hud);
  transform: scaleY(0);
  transition: transform 0.18s;
}
.host-card:hover {
  border-color: var(--border-lit);
  box-shadow: 0 4px 20px rgba(0, 0, 0, 0.35), 0 0 0 1px rgba(45, 212, 191, 0.15);
}
.host-card:hover::before { transform: scaleY(1); }
.host-card:active { transform: scale(0.99); }
.host-card.connecting { opacity: 0.7; pointer-events: none; }

.host-icon {
  width: 44px;
  height: 44px;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--hud);
  background: var(--hud-dim);
  border: 1px solid rgba(45, 212, 191, 0.25);
  border-radius: 10px;
  flex-shrink: 0;
}
.host-info { flex: 1; min-width: 0; }
.host-title {
  font-weight: 600;
  font-size: 15px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.host-sub {
  font-family: var(--font-mono);
  color: var(--muted);
  font-size: 12px;
  margin-top: 3px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.host-tag {
  display: inline-block;
  margin-top: 6px;
  font-size: 11px;
  color: var(--warn);
  background: rgba(216, 134, 42, 0.1);
  border: 1px solid rgba(216, 134, 42, 0.4);
  border-radius: 4px;
  padding: 1px 7px;
}
.host-actions { flex-shrink: 0; }
.del-btn {
  border: none;
  background: transparent;
  color: var(--muted);
  cursor: pointer;
  font-size: 14px;
  padding: 4px 8px;
  border-radius: 6px;
}
.del-btn:hover { background: var(--surface-2); color: var(--error); }

.empty {
  grid-column: 1 / -1;
  text-align: center;
  color: var(--muted);
  padding: var(--sp-8);
}

/* 转圈 */
.spinner {
  display: inline-block;
  width: 16px;
  height: 16px;
  border: 2px solid var(--border);
  border-top-color: var(--hud);
  border-radius: 50%;
  animation: spin 0.7s linear infinite;
}
@keyframes spin { to { transform: rotate(360deg); } }

/* 弹层 */
.modal-mask {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.5);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 100;
}
.modal {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 12px;
  padding: var(--sp-6);
  width: 380px;
  max-width: 90vw;
}
.modal h3 { margin: 0 0 var(--sp-4); font-size: 16px; }
.modal-hint { color: var(--muted); font-size: 13px; margin: 0 0 var(--sp-3); }
.modal label {
  display: block;
  font-size: 13px;
  color: var(--muted);
  margin-bottom: var(--sp-3);
}
.modal input {
  display: block;
  width: 100%;
  margin-top: 4px;
  padding: 8px 10px;
  background: var(--bg);
  border: 1px solid var(--border);
  border-radius: 6px;
  color: var(--text);
  font-size: 14px;
  box-sizing: border-box;
}
.modal input:focus { outline: none; border-color: var(--hud); }
.row { display: flex; gap: var(--sp-3); }
.flex2 { flex: 2; }
.flex1 { flex: 1; }
.modal-actions {
  display: flex;
  justify-content: flex-end;
  gap: var(--sp-3);
  margin-top: var(--sp-4);
}
.btn-primary {
  background: var(--hud-dim);
  color: var(--hud);
  border: 1px solid rgba(45, 212, 191, 0.4);
  padding: 8px 16px;
  border-radius: 7px;
  cursor: pointer;
  font-size: 14px;
  font-weight: 500;
  transition: background 0.15s, box-shadow 0.15s;
}
.btn-primary:hover {
  background: rgba(45, 212, 191, 0.22);
  box-shadow: 0 0 14px rgba(45, 212, 191, 0.25);
}
.btn-ghost {
  background: transparent;
  color: var(--muted);
  border: 1px solid var(--border);
  padding: 8px 16px;
  border-radius: 6px;
  cursor: pointer;
  font-size: 14px;
}
.btn-ghost:hover { background: var(--surface-2); }
</style>
