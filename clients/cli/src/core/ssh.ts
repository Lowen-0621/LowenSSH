/**
 * SSH 客户端 —— 一个实例持有一个长连接，多条命令复用同一会话。
 * 移植自 Java 版 SshClient（JSch → ssh2）。
 *
 * 为什么长连接复用：agentic loop 里连续执行多条命令，每次重连既慢又丢上下文。
 * 非线程安全：一个实例对应一台机器一个会话，由上层串行使用。
 */
import { Client, type ConnectConfig, type SFTPWrapper } from 'ssh2'

/** 命令执行结果三件套 */
export interface ExecResult {
  stdout: string
  stderr: string
  exitCode: number
}

/** 远程文件项 */
export interface RemoteFile {
  name: string
  path: string
  size: number
  isDir: boolean
  perms: string
}

export class SshClient {
  private conn: Client | null = null
  private connected = false

  /** 建立连接（密码认证）。10s 超时。 */
  connect(host: string, port: number, username: string, password: string): Promise<void> {
    return new Promise((resolve, reject) => {
      const conn = new Client()
      const cfg: ConnectConfig = {
        host,
        port: port || 22,
        username,
        password,
        readyTimeout: 10_000,
        // demo 方便跳过 host key 校验；生产应校验 known_hosts，否则有中间人风险
      }
      conn
        .on('ready', () => {
          this.conn = conn
          this.connected = true
          resolve()
        })
        .on('error', (err) => {
          this.connected = false
          reject(err)
        })
        .on('close', () => {
          this.connected = false
        })
        .connect(cfg)
    })
  }

  isConnected(): boolean {
    return this.connected && this.conn !== null
  }

  /**
   * 执行一条命令，收集 stdout、stderr、exitCode。
   * ssh2 的 exec 回调给一个 stream，stdout 走 data 事件，stderr 走 stream.stderr，
   * exitCode 在 close 事件回调里拿。
   */
  exec(command: string): Promise<ExecResult> {
    return new Promise((resolve, reject) => {
      if (!this.conn || !this.connected) {
        reject(new Error('SSH 未连接，先调用 connect()'))
        return
      }
      this.conn.exec(command, (err, stream) => {
        if (err) {
          reject(err)
          return
        }
        let stdout = ''
        let stderr = ''
        stream
          .on('close', (code: number | null) => {
            resolve({ stdout, stderr, exitCode: code ?? 0 })
          })
          .on('data', (data: Buffer) => {
            stdout += data.toString('utf8')
          })
        stream.stderr.on('data', (data: Buffer) => {
          stderr += data.toString('utf8')
        })
      })
    })
  }

  /** 懒开 SFTP 通道 */
  private sftp(): Promise<SFTPWrapper> {
    return new Promise((resolve, reject) => {
      if (!this.conn || !this.connected) {
        reject(new Error('SSH 未连接'))
        return
      }
      this.conn.sftp((err, sftp) => {
        if (err) reject(err)
        else resolve(sftp)
      })
    })
  }

  /** 列目录。过滤 . 和 ..，目录在前、名称升序。 */
  async listDir(path: string): Promise<RemoteFile[]> {
    const sftp = await this.sftp()
    const base = path.endsWith('/') ? path : path + '/'
    const entries = await new Promise<RemoteFile[]>((resolve, reject) => {
      sftp.readdir(path, (err, list) => {
        if (err) {
          reject(err)
          return
        }
        const files: RemoteFile[] = list
          .filter((e) => e.filename !== '.' && e.filename !== '..')
          .map((e) => ({
            name: e.filename,
            path: base + e.filename,
            size: e.attrs.size,
            isDir: e.attrs.isDirectory(),
            perms: e.longname.split(/\s+/)[0] ?? '', // longname 首列形如 drwxr-xr-x
          }))
        resolve(files)
      })
    })
    entries.sort((a, b) => {
      if (a.isDir !== b.isDir) return a.isDir ? -1 : 1
      return a.name.toLowerCase().localeCompare(b.name.toLowerCase())
    })
    return entries
  }

  /** 删除文件 */
  async deleteFile(path: string): Promise<void> {
    const sftp = await this.sftp()
    await new Promise<void>((resolve, reject) => {
      sftp.unlink(path, (err) => (err ? reject(err) : resolve()))
    })
  }

  /** 新建目录 */
  async mkdir(path: string): Promise<void> {
    const sftp = await this.sftp()
    await new Promise<void>((resolve, reject) => {
      sftp.mkdir(path, (err) => (err ? reject(err) : resolve()))
    })
  }

  /** 重命名/移动 */
  async rename(from: string, to: string): Promise<void> {
    const sftp = await this.sftp()
    await new Promise<void>((resolve, reject) => {
      sftp.rename(from, to, (err) => (err ? reject(err) : resolve()))
    })
  }

  /** 关闭连接 */
  close(): void {
    if (this.conn) {
      this.conn.end()
      this.conn = null
    }
    this.connected = false
  }
}
