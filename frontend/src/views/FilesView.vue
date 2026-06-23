<script setup>
// SFTP 文件管理面板（给人用）：列目录、进出目录、上传、下载、删除、新建目录。
// 数据走 /api/sftp/{hostId}/*，hostId 取自 useAgentStream 的 activeHostId（进主机时已设）。
// 套在三栏外壳的中间主区里渲染，与图形/终端并列为一种"呈现方式"。
import { ref, computed, onMounted, watch } from 'vue'
import { useRouter } from 'vue-router'
import { useAgentStream } from '@/composables/useAgentStream'

const router = useRouter()
const { activeHostId, conn } = useAgentStream()

const cwd = ref('/')           // 当前目录
const files = ref([])          // 当前目录下的条目
const loading = ref(false)
const errorMsg = ref('')
const uploading = ref(false)
const fileInput = ref(null)    // 隐藏的 <input type=file>

// 没进主机就别停在这页，回主机簿
const hostId = computed(() => activeHostId.value)

// 面包屑：把 /a/b/c 拆成可点的层级
const crumbs = computed(() => {
  const parts = cwd.value.split('/').filter(Boolean)
  const list = [{ name: '/', path: '/' }]
  let acc = ''
  for (const p of parts) {
    acc += '/' + p
    list.push({ name: p, path: acc })
  }
  return list
})

// 列目录
async function loadDir(path) {
  if (hostId.value == null) return
  loading.value = true
  errorMsg.value = ''
  try {
    const resp = await fetch(`/api/sftp/${hostId.value}/list?path=${encodeURIComponent(path)}`)
    const data = await resp.json().catch(() => ({}))
    if (!resp.ok || data.error) {
      errorMsg.value = data.error || `列目录失败 (HTTP ${resp.status})`
      return
    }
    cwd.value = data.path || path
    files.value = data.files || []
  } catch (e) {
    errorMsg.value = `列目录失败: ${e.message}`
  } finally {
    loading.value = false
  }
}

// 进目录 / 上一级
function enter(file) {
  if (file.isDir) loadDir(file.path)
}
function goUp() {
  if (cwd.value === '/') return
  const parent = cwd.value.replace(/\/[^/]+\/?$/, '') || '/'
  loadDir(parent)
}

// 上传：触发隐藏 input
function pickFile() {
  fileInput.value?.click()
}
async function onFilePicked(e) {
  const file = e.target.files?.[0]
  if (!file) return
  uploading.value = true
  errorMsg.value = ''
  try {
    const form = new FormData()
    form.append('file', file)
    form.append('path', cwd.value)
    const resp = await fetch(`/api/sftp/${hostId.value}/upload`, { method: 'POST', body: form })
    const data = await resp.json().catch(() => ({}))
    if (!resp.ok || data.error) {
      errorMsg.value = data.error || `上传失败 (HTTP ${resp.status})`
      return
    }
    await loadDir(cwd.value)   // 刷新
  } catch (err) {
    errorMsg.value = `上传失败: ${err.message}`
  } finally {
    uploading.value = false
    e.target.value = ''        // 允许重复选同一文件
  }
}

// 下载：直接开后端流式接口（浏览器触发下载）
function download(file) {
  const url = `/api/sftp/${hostId.value}/download?path=${encodeURIComponent(file.path)}`
  window.open(url, '_blank')
}

// 删除文件（仅文件，目录删除暂不开放，避免误删整树）
async function remove(file) {
  if (file.isDir) {
    errorMsg.value = '暂不支持删除目录，避免误删整树'
    return
  }
  if (!confirm(`确认删除 ${file.name}?`)) return
  errorMsg.value = ''
  try {
    const resp = await fetch(`/api/sftp/${hostId.value}/file?path=${encodeURIComponent(file.path)}`, {
      method: 'DELETE'
    })
    if (!resp.ok) {
      const data = await resp.json().catch(() => ({}))
      errorMsg.value = data.error || `删除失败 (HTTP ${resp.status})`
      return
    }
    await loadDir(cwd.value)
  } catch (e) {
    errorMsg.value = `删除失败: ${e.message}`
  }
}

// 新建目录
async function makeDir() {
  const name = prompt('新目录名')
  if (!name) return
  const path = (cwd.value.endsWith('/') ? cwd.value : cwd.value + '/') + name
  errorMsg.value = ''
  try {
    const resp = await fetch(`/api/sftp/${hostId.value}/mkdir`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ path })
    })
    const data = await resp.json().catch(() => ({}))
    if (!resp.ok || data.error) {
      errorMsg.value = data.error || `建目录失败 (HTTP ${resp.status})`
      return
    }
    await loadDir(cwd.value)
  } catch (e) {
    errorMsg.value = `建目录失败: ${e.message}`
  }
}

// 字节数转人类可读
function humanSize(n) {
  if (n < 1024) return n + ' B'
  const units = ['KB', 'MB', 'GB', 'TB']
  let v = n / 1024, i = 0
  while (v >= 1024 && i < units.length - 1) { v /= 1024; i++ }
  return v.toFixed(1) + ' ' + units[i]
}
// mtime 是秒级时间戳
function fmtTime(sec) {
  if (!sec) return '-'
  const d = new Date(sec * 1000)
  const p = (x) => String(x).padStart(2, '0')
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`
}

onMounted(() => {
  if (hostId.value == null) {
    router.push('/hosts')
    return
  }
  loadDir('/')
})
// 切主机后重置回根目录
watch(hostId, (id) => { if (id != null) loadDir('/') })
</script>

<template>
  <div class="files">
    <!-- 工具条：当前主机 + 操作 -->
    <div class="toolbar">
      <div class="host-tag" v-if="conn.host">{{ conn.user }}@{{ conn.host }}</div>
      <div class="actions">
        <button class="btn" :disabled="uploading || hostId == null" @click="pickFile">
          {{ uploading ? '上传中…' : '上传' }}
        </button>
        <button class="btn" :disabled="hostId == null" @click="makeDir">新建目录</button>
        <button class="btn ghost" :disabled="loading" @click="loadDir(cwd)">刷新</button>
      </div>
    </div>

    <!-- 面包屑 -->
    <div class="crumbs">
      <button class="up" :disabled="cwd === '/'" @click="goUp" title="上一级">↑</button>
      <template v-for="(c, i) in crumbs" :key="c.path">
        <span v-if="i > 0" class="sep">/</span>
        <button class="crumb" @click="loadDir(c.path)">{{ c.name === '/' ? 'root' : c.name }}</button>
      </template>
    </div>

    <!-- 错误条 -->
    <div v-if="errorMsg" class="error-bar">{{ errorMsg }}</div>

    <!-- 文件列表 -->
    <div class="list-wrap">
      <div v-if="loading" class="empty">加载中…</div>
      <div v-else-if="files.length === 0" class="empty">空目录</div>
      <table v-else class="file-table">
        <thead>
          <tr>
            <th class="col-name">名称</th>
            <th class="col-size">大小</th>
            <th class="col-perm">权限</th>
            <th class="col-time">修改时间</th>
            <th class="col-op">操作</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="f in files" :key="f.path" :class="{ dir: f.isDir }">
            <td class="col-name">
              <button class="name-btn" @click="enter(f)">
                <span class="ico">{{ f.isDir ? '📁' : '📄' }}</span>{{ f.name }}
              </button>
            </td>
            <td class="col-size">{{ f.isDir ? '-' : humanSize(f.size) }}</td>
            <td class="col-perm mono">{{ f.perms }}</td>
            <td class="col-time">{{ fmtTime(f.mtime) }}</td>
            <td class="col-op">
              <button v-if="!f.isDir" class="op" @click="download(f)">下载</button>
              <button v-if="!f.isDir" class="op danger" @click="remove(f)">删除</button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <input ref="fileInput" type="file" hidden @change="onFilePicked" />
  </div>
</template>

<style scoped>
.files {
  display: flex;
  flex-direction: column;
  height: 100%;
  padding: var(--sp-4);
  gap: var(--sp-3);
  overflow: hidden;
}
.toolbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: var(--sp-3);
}
.host-tag {
  font-family: var(--font-mono);
  font-size: 12px;
  color: var(--hud);
  background: var(--hud-dim);
  border: 1px solid rgba(45, 212, 191, 0.3);
  padding: 3px 10px;
  border-radius: 6px;
}
.actions { display: flex; gap: var(--sp-2); }
.btn {
  padding: 7px 14px;
  border: 1px solid var(--border);
  border-radius: 8px;
  background: var(--surface-2);
  color: var(--text);
  font-size: 13px;
  cursor: pointer;
  transition: border-color 0.15s, color 0.15s;
}
.btn:hover:not(:disabled) { border-color: var(--hud); color: var(--hud); }
.btn:disabled { opacity: 0.5; cursor: not-allowed; }
.btn.ghost { background: transparent; }

.crumbs {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 2px;
  font-size: 13px;
}
.up {
  margin-right: var(--sp-2);
  padding: 2px 8px;
  border: 1px solid var(--border);
  border-radius: 6px;
  background: var(--surface-2);
  color: var(--text);
  cursor: pointer;
}
.up:disabled { opacity: 0.4; cursor: not-allowed; }
.crumb {
  background: none;
  border: none;
  color: var(--hud);
  cursor: pointer;
  padding: 2px 4px;
  font-size: 13px;
  font-family: var(--font-mono);
}
.crumb:hover { text-decoration: underline; }
.sep { color: var(--muted); }

.error-bar {
  background: var(--danger-bg);
  color: var(--danger);
  border: 1px solid var(--danger);
  border-radius: 6px;
  padding: 8px 12px;
  font-size: 13px;
}

.list-wrap {
  flex: 1;
  overflow-y: auto;
  border: 1px solid var(--border);
  border-radius: 10px;
}
.empty {
  padding: var(--sp-8);
  text-align: center;
  color: var(--muted);
  font-size: 13px;
}
.file-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 13px;
}
.file-table th {
  position: sticky;
  top: 0;
  background: var(--surface);
  color: var(--muted);
  text-align: left;
  font-weight: 500;
  padding: 8px 12px;
  border-bottom: 1px solid var(--border);
}
.file-table td {
  padding: 6px 12px;
  border-bottom: 1px solid var(--border);
  color: var(--text);
}
.file-table tr:hover td { background: var(--surface-2); }
.col-size, .col-perm, .col-time { color: var(--muted); white-space: nowrap; }
.col-op { white-space: nowrap; text-align: right; }
.mono { font-family: var(--font-mono); }
.name-btn {
  background: none;
  border: none;
  color: var(--text);
  cursor: pointer;
  display: inline-flex;
  align-items: center;
  gap: 6px;
  font-size: 13px;
}
.dir .name-btn { color: var(--model); }
.ico { font-size: 14px; }
.op {
  background: none;
  border: 1px solid var(--border);
  border-radius: 4px;
  color: var(--text);
  padding: 2px 8px;
  margin-left: 6px;
  cursor: pointer;
  font-size: 12px;
}
.op:hover { border-color: var(--hud); color: var(--hud); }
.op.danger { color: var(--danger); }
.op.danger:hover { border-color: var(--danger); color: var(--danger); }
</style>
