<script setup>
// 监控面板（给人用），两块：
//  1) 远程主机：每 5s 轮询 /api/monitor/{hostId}/metrics，前端攒采样点画 SVG 趋势线
//  2) 应用自监控：读本服务的 Actuator（health + JVM 指标），反映 LowenSSH 自身健康
// 不引图表库。
import { ref, computed, onMounted, onUnmounted, watch } from 'vue'
import { useRouter } from 'vue-router'
import { useAgentStream } from '@/composables/useAgentStream'

const router = useRouter()
const { activeHostId, conn } = useAgentStream()

const hostId = computed(() => activeHostId.value)
const metrics = ref(null)      // 最新一帧
const errorMsg = ref('')
const loading = ref(false)
const POLL_MS = 5000
const MAX_POINTS = 60          // 最多攒 60 个点（约 5 分钟）
const cpuHistory = ref([])     // [{t, v}]
const memHistory = ref([])
let timer = null

// —— 应用自监控（Actuator）——
const appHealth = ref('')      // UP/DOWN
const appMetrics = ref(null)   // { memUsed, memMax, threads, uptime }

async function readMetric(name) {
  try {
    const r = await fetch(`/actuator/metrics/${name}`)
    const d = await r.json()
    return d.measurements?.[0]?.value ?? null
  } catch { return null }
}
async function fetchApp() {
  try {
    const h = await fetch('/actuator/health').then(r => r.json()).catch(() => null)
    appHealth.value = h?.status || 'UNKNOWN'
    const [memUsed, memMax, threads, uptime] = await Promise.all([
      readMetric('jvm.memory.used'),
      readMetric('jvm.memory.max'),
      readMetric('jvm.threads.live'),
      readMetric('process.uptime')
    ])
    appMetrics.value = { memUsed, memMax, threads, uptime }
  } catch {
    appHealth.value = 'UNKNOWN'
  }
}

async function fetchOnce() {
  if (hostId.value == null) return
  try {
    const resp = await fetch(`/api/monitor/${hostId.value}/metrics`)
    const data = await resp.json().catch(() => ({}))
    if (!resp.ok || data.error) {
      errorMsg.value = data.error || `采集失败 (HTTP ${resp.status})`
      return
    }
    errorMsg.value = ''
    metrics.value = data
    pushPoint(cpuHistory, data.cpuPercent)
    pushPoint(memHistory, data.memPercent)
  } catch (e) {
    errorMsg.value = `采集失败: ${e.message}`
  } finally {
    loading.value = false
  }
}

function pushPoint(arrRef, v) {
  const arr = arrRef.value
  arr.push({ t: Date.now(), v })
  if (arr.length > MAX_POINTS) arr.shift()
}

function start() {
  stop()
  loading.value = true
  fetchOnce()
  fetchApp()
  timer = setInterval(() => { fetchOnce(); fetchApp() }, POLL_MS)
}
function stop() {
  if (timer) { clearInterval(timer); timer = null }
}

// —— 纯 SVG 折线：把历史点映射到 viewBox 100x40 ——
function buildPath(history) {
  const arr = history.value
  if (arr.length < 2) return ''
  const w = 100, h = 40
  const step = w / (MAX_POINTS - 1)
  return arr.map((p, i) => {
    const x = i * step
    const y = h - (Math.min(100, Math.max(0, p.v)) / 100) * h
    return `${i === 0 ? 'M' : 'L'}${x.toFixed(1)},${y.toFixed(1)}`
  }).join(' ')
}
const cpuPath = computed(() => buildPath(cpuHistory))
const memPath = computed(() => buildPath(memHistory))

// uptime 秒转 "Xd Xh Xm"
function fmtUptime(sec) {
  if (!sec) return '-'
  const d = Math.floor(sec / 86400)
  const h = Math.floor((sec % 86400) / 3600)
  const m = Math.floor((sec % 3600) / 60)
  return [d ? d + 'd' : '', h ? h + 'h' : '', m + 'm'].filter(Boolean).join(' ')
}
function fmtGb(kb) {
  return (kb / 1024 / 1024).toFixed(1) + ' GB'
}
// JVM 内存是字节，转 MB
function fmtMb(bytes) {
  if (bytes == null) return '-'
  return (bytes / 1024 / 1024).toFixed(0) + ' MB'
}
// JVM 堆使用率
const heapPercent = computed(() => {
  const m = appMetrics.value
  if (!m || !m.memMax) return 0
  return Math.round(m.memUsed / m.memMax * 100)
})
// 使用率配色：高了变红
function pctColor(v) {
  if (v >= 90) return 'var(--danger)'
  if (v >= 70) return 'var(--tool)'
  return 'var(--ok)'
}

onMounted(() => {
  if (hostId.value == null) { router.push('/hosts'); return }
  start()
})
onUnmounted(stop)
// 切主机后清历史重开
watch(hostId, (id) => {
  cpuHistory.value = []
  memHistory.value = []
  metrics.value = null
  if (id != null) start(); else stop()
})
</script>

<template>
  <div class="monitor">
    <div class="toolbar">
      <div class="host-tag" v-if="conn.host">{{ conn.user }}@{{ conn.host }}</div>
      <div class="poll-hint">
        <span class="dot" :class="{ live: !errorMsg }" />
        {{ errorMsg ? '采集异常' : `每 ${POLL_MS / 1000}s 刷新` }}
      </div>
    </div>

    <div v-if="errorMsg" class="error-bar">{{ errorMsg }}</div>

    <div v-if="!metrics && loading" class="empty">采集中…</div>

    <div v-else-if="metrics" class="grid">
      <!-- CPU -->
      <div class="card">
        <div class="card-head">
          <span class="title">CPU</span>
          <span class="big" :style="{ color: pctColor(metrics.cpuPercent) }">{{ metrics.cpuPercent }}%</span>
        </div>
        <svg class="spark" viewBox="0 0 100 40" preserveAspectRatio="none">
          <path :d="cpuPath" fill="none" :stroke="pctColor(metrics.cpuPercent)" stroke-width="1.5" />
        </svg>
        <div class="sub">{{ metrics.cpuCores }} 核 · 负载 {{ metrics.load1 }} / {{ metrics.load5 }} / {{ metrics.load15 }}</div>
      </div>

      <!-- 内存 -->
      <div class="card">
        <div class="card-head">
          <span class="title">内存</span>
          <span class="big" :style="{ color: pctColor(metrics.memPercent) }">{{ metrics.memPercent }}%</span>
        </div>
        <svg class="spark" viewBox="0 0 100 40" preserveAspectRatio="none">
          <path :d="memPath" fill="none" :stroke="pctColor(metrics.memPercent)" stroke-width="1.5" />
        </svg>
        <div class="sub">{{ fmtGb(metrics.memUsedKb) }} / {{ fmtGb(metrics.memTotalKb) }}</div>
      </div>

      <!-- 磁盘 -->
      <div class="card">
        <div class="card-head">
          <span class="title">磁盘 /</span>
          <span class="big" :style="{ color: pctColor(metrics.diskPercent) }">{{ metrics.diskPercent }}%</span>
        </div>
        <div class="bar">
          <div class="bar-fill" :style="{ width: metrics.diskPercent + '%', background: pctColor(metrics.diskPercent) }" />
        </div>
        <div class="sub">{{ fmtGb(metrics.diskUsedKb) }} / {{ fmtGb(metrics.diskTotalKb) }}</div>
      </div>

      <!-- 运行时长 -->
      <div class="card">
        <div class="card-head">
          <span class="title">运行时长</span>
        </div>
        <div class="uptime">{{ fmtUptime(metrics.uptimeSec) }}</div>
        <div class="sub">开机至今</div>
      </div>
    </div>

    <!-- 应用自监控：LowenSSH 本服务的健康与 JVM 状态（Actuator） -->
    <div class="section-title">
      应用自监控
      <span class="badge" :class="appHealth === 'UP' ? 'up' : 'down'">{{ appHealth || '...' }}</span>
    </div>
    <div class="grid" v-if="appMetrics">
      <div class="card">
        <div class="card-head">
          <span class="title">JVM 堆内存</span>
          <span class="big">{{ fmtMb(appMetrics.memUsed) }}</span>
        </div>
        <div class="bar">
          <div class="bar-fill"
               :style="{ width: heapPercent + '%', background: pctColor(heapPercent) }" />
        </div>
        <div class="sub">{{ fmtMb(appMetrics.memUsed) }} / {{ fmtMb(appMetrics.memMax) }}（{{ heapPercent }}%）</div>
      </div>
      <div class="card">
        <div class="card-head">
          <span class="title">活动线程</span>
          <span class="big">{{ appMetrics.threads ?? '-' }}</span>
        </div>
        <div class="sub">JVM live threads</div>
      </div>
      <div class="card">
        <div class="card-head">
          <span class="title">服务运行时长</span>
        </div>
        <div class="uptime">{{ fmtUptime(appMetrics.uptime) }}</div>
        <div class="sub">本服务启动至今</div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.monitor {
  display: flex;
  flex-direction: column;
  height: 100%;
  padding: var(--sp-4);
  gap: var(--sp-4);
  overflow-y: auto;
}
.toolbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
}
.host-tag { font-family: var(--font-mono); font-size: 13px; color: var(--muted); }
.poll-hint { display: flex; align-items: center; gap: 6px; font-size: 12px; color: var(--muted); }
.poll-hint .dot {
  width: 7px; height: 7px; border-radius: 50%;
  background: var(--muted);
}
.poll-hint .dot.live { background: var(--ok); }

.error-bar {
  background: var(--danger-bg);
  color: var(--danger);
  border: 1px solid var(--danger);
  border-radius: 6px;
  padding: 8px 12px;
  font-size: 13px;
}
.empty { padding: var(--sp-8); text-align: center; color: var(--muted); }

.grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
  gap: var(--sp-4);
}
.card {
  border: 1px solid var(--border);
  border-radius: 10px;
  background: var(--surface);
  padding: var(--sp-4);
  display: flex;
  flex-direction: column;
  gap: var(--sp-3);
}
.card-head { display: flex; align-items: baseline; justify-content: space-between; }
.title { font-size: 13px; color: var(--muted); }
.big { font-size: 26px; font-weight: 600; font-family: var(--font-mono); }
.spark { width: 100%; height: 40px; }
.sub { font-size: 12px; color: var(--muted); font-family: var(--font-mono); }

.bar {
  height: 10px;
  background: var(--surface-2);
  border-radius: 5px;
  overflow: hidden;
}
.bar-fill { height: 100%; transition: width 0.4s ease; }

.uptime { font-size: 22px; font-weight: 600; font-family: var(--font-mono); color: var(--text); }

/* 分区标题（应用自监控） */
.section-title {
  display: flex;
  align-items: center;
  gap: var(--sp-3);
  font-size: 14px;
  font-weight: 600;
  color: var(--text);
  margin-top: var(--sp-4);
}
.badge {
  font-size: 11px;
  font-weight: 600;
  padding: 2px 8px;
  border-radius: 4px;
  font-family: var(--font-mono);
}
.badge.up { background: rgba(63, 185, 80, 0.15); color: var(--ok); }
.badge.down { background: var(--danger-bg); color: var(--danger); }
</style>
