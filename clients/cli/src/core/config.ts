/**
 * 本地配置 —— 主机簿 + GLM 接入设置，存 ~/.lowenssh/config.json。
 *
 * 内置版（不依赖后端）的持久化层：替代 Java 版的 MySQL t_host。
 * 主机密码用 AES-GCM 加密后存 passwordEnc 字段，绝不存明文（复用 crypto.ts）。
 * 配置文件权限设为 600，只有属主可读写。
 */
import { homedir } from 'node:os'
import { join } from 'node:path'
import { mkdirSync, readFileSync, writeFileSync, existsSync, chmodSync } from 'node:fs'
import { randomUUID } from 'node:crypto'
import { encrypt, decrypt } from './crypto.js'

/** 一台主机的连接信息 */
export interface Host {
  id: string
  alias?: string
  host: string
  port: number
  user: string
  /** AES-GCM 加密后的密码；未存密码则为空 */
  passwordEnc?: string
}

/** GLM/OpenAI 兼容接入设置 */
export interface LlmConfig {
  baseURL: string
  apiKey: string
  model: string
}

export interface AppConfig {
  hosts: Host[]
  llm: LlmConfig
}

const CONFIG_DIR = join(homedir(), '.lowenssh')
const CONFIG_FILE = join(CONFIG_DIR, 'config.json')

/** 默认 LLM 设置：GLM。apiKey 留空，首次运行提示用户填或从环境变量读 */
const DEFAULT_LLM: LlmConfig = {
  baseURL: 'https://open.bigmodel.cn/api/paas/v4',
  apiKey: '',
  model: 'glm-4.6',
}

function emptyConfig(): AppConfig {
  return { hosts: [], llm: { ...DEFAULT_LLM } }
}

/** 读配置；不存在则返回空配置。环境变量 GLM_API_KEY 优先覆盖文件里的 apiKey。 */
export function loadConfig(): AppConfig {
  let cfg: AppConfig
  if (!existsSync(CONFIG_FILE)) {
    cfg = emptyConfig()
  } else {
    try {
      const raw = readFileSync(CONFIG_FILE, 'utf8')
      const parsed = JSON.parse(raw) as Partial<AppConfig>
      cfg = {
        hosts: parsed.hosts ?? [],
        llm: { ...DEFAULT_LLM, ...parsed.llm },
      }
    } catch {
      // 配置损坏不影响启动，退回空配置（用户可重新添加）
      cfg = emptyConfig()
    }
  }
  // 环境变量优先：方便 CI / 临时覆盖，且不把 key 写进文件
  const envKey = process.env.GLM_API_KEY
  if (envKey && envKey.trim() !== '') {
    cfg.llm.apiKey = envKey
  }
  return cfg
}

/** 写配置（权限 600）。注意：不会把环境变量注入的 apiKey 持久化回文件。 */
export function saveConfig(cfg: AppConfig): void {
  if (!existsSync(CONFIG_DIR)) {
    mkdirSync(CONFIG_DIR, { recursive: true, mode: 0o700 })
  }
  writeFileSync(CONFIG_FILE, JSON.stringify(cfg, null, 2), { mode: 0o600 })
  try {
    chmodSync(CONFIG_FILE, 0o600)
  } catch {
    // Windows 不支持 chmod，忽略
  }
}

/** 新增主机：密码加密后落库，返回带 id 的 Host */
export function addHost(input: Omit<Host, 'id' | 'passwordEnc'> & { password?: string }): Host {
  const cfg = loadConfig()
  const host: Host = {
    id: randomUUID(),
    alias: input.alias,
    host: input.host,
    port: input.port || 22,
    user: input.user || 'root',
    passwordEnc: input.password ? encrypt(input.password) ?? undefined : undefined,
  }
  cfg.hosts.push(host)
  saveConfig(cfg)
  return host
}

/** 删除主机 */
export function removeHost(id: string): void {
  const cfg = loadConfig()
  cfg.hosts = cfg.hosts.filter((h) => h.id !== id)
  saveConfig(cfg)
}

/** 取某主机的明文密码（解密）；未存返回 null */
export function getHostPassword(host: Host): string | null {
  if (!host.passwordEnc) return null
  return decrypt(host.passwordEnc)
}

/** 主机是否已存密码 */
export function hasPassword(host: Host): boolean {
  return !!host.passwordEnc
}

export { CONFIG_FILE }
