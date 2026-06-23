# 开发计划：SFTP 文件管理 + 监控

> 目标：在现有 AI 运维 Agent 基础上，增加 ①SFTP 文件管理（人 + AI 双形态）②监控（远端主机指标 + 应用自身）。
> 原则：复用现有常驻 JSch 连接，零重连；分阶段可独立交付；改动范围最小。

## 一、现状复用点（已确认）

- `SshClient` 持有 JSch `Session`，可在同一 Session 上 `openChannel("sftp")`，**SFTP 不用重连**。
- `SessionManager.LiveSession` 按 hostId/sessionId 管理常驻连接，FTP/监控都从这里取连接。
- `SshTools` 已是 `@Tool` 模式，新增 SFTP 工具直接挂上去给 Agent 用。
- 监控指标采集走现有 `SshClient.exec()`，无需新通道。

---

## 阶段 1：SFTP 底层能力（SshClient 扩展）

**目标**：在 SshClient 上加 SFTP 原子操作，作为人/AI 两条路径的共同底座。

- `SshClient` 新增方法（复用同一 Session，懒开 ChannelSftp）：
  - `List<RemoteFile> listDir(String path)` — ls，返回名称/大小/权限/是否目录/修改时间
  - `void upload(InputStream in, String remotePath)` — 上传
  - `void download(String remotePath, OutputStream out)` — 下载
  - `void deleteFile(String path)` / `void mkdir(String path)` / `void rename(String from, String to)`
- 新增 `ssh/RemoteFile.java`（record：name/path/size/isDir/perms/mtime）
- ChannelSftp 生命周期：随 Session 关闭一并释放，加进 `SshClient.close()`
- **安全**：路径做基本规范化校验，拒绝明显越权（可选，先不做沙箱）

**验证**：单元测试或对京东生产那台跑一次 list/upload/download 往返。

---

## 阶段 2：SFTP 文件管理面板（给人用）

**目标**：图形界面浏览/上传/下载/删除远端文件，类似宝塔文件管理器的轻量版。

后端：
- 新增 `SftpController`，REST 接口（按 hostId 取 LiveSession）：
  - `GET /api/sftp/{hostId}/list?path=/xxx` — 列目录
  - `POST /api/sftp/{hostId}/upload`（multipart）— 上传
  - `GET /api/sftp/{hostId}/download?path=/xxx` — 下载（流式）
  - `DELETE /api/sftp/{hostId}/file?path=/xxx` — 删除
  - `POST /api/sftp/{hostId}/mkdir` — 建目录
- 复用 `LiveSession.lock()` 串行化，避免 SFTP 与 Agent 命令抢同一 Session 冲突

前端：
- 新增 `FilesView.vue`（或在 HostsView 加「文件」入口）
- 文件列表（面包屑路径 + 表格）、上传按钮、下载/删除操作
- 大文件下载用浏览器原生下载，不走内存

**验证**：browse 实测一遍浏览→上传→下载→删除。

---

## 阶段 3：SFTP 作为 Agent 工具（给 AI 用）

**目标**：Agent 能自主传文件、改配置（如下载日志分析、上传修复脚本）。

- `SshTools` 新增 `@Tool`：
  - `downloadAndRead(path)` — 下载并返回文本内容（已有 readRemoteFile，可能够用，差异在二进制/大文件）
  - `writeRemoteFile(path, content)` — 写入/覆盖远端文件（**危险操作，过 CommandGuard 安全门禁**）
  - `uploadScript(path, content)` — 上传脚本
- **安全重点**：写文件类工具必须接入现有 `CommandGuard` 的 deny/ask/allow 流程，
  覆盖系统配置（/etc 下）默认 ask。这是这一阶段的核心，不能裸放。

**验证**：让 Agent 执行「把 /etc/nginx/nginx.conf 下载下来看看」+「上传一个测试脚本」，确认安全门禁拦截写操作。

---

## 阶段 4：远端主机指标监控

**目标**：实时展示目标服务器 CPU/内存/磁盘/负载，折线图。

后端：
- 新增 `MetricsService`：用 `LiveSession.ssh().exec()` 采集
  - CPU：`top -bn1` 或 `/proc/stat` 两次采样算使用率
  - 内存：`free -b`
  - 磁盘：`df -B1`
  - 负载：`/proc/loadavg`
  - 解析成 `HostMetrics` record
- 接口形态二选一（plan 里默认轮询，简单稳；如需推送再升级 SSE）：
  - `GET /api/metrics/{hostId}` — 返回一次快照，前端定时轮询（默认 5s）
- 采集走 LiveSession.lock()，避免和 Agent / SFTP 抢连接

前端：
- 新增 `MonitorView.vue`，用轻量图表库（如 ECharts 或纯 canvas）
- 4 个指标卡片 + 折线图，前端维护滑动窗口（最近 N 个采样点）
- 异常阈值高亮（如磁盘 >90% 标红）

**验证**：browse 打开监控页，确认指标刷新、图表滚动。

---

## 阶段 5：应用自身监控（Actuator + Micrometer）

**目标**：监控 LowenSSH 应用本身：JVM、连接数、请求耗时、GLM 调用量。

- `pom.xml` 加 `spring-boot-starter-actuator` + `micrometer-registry-prometheus`
- 暴露 `/actuator/health`、`/actuator/metrics`、`/actuator/prometheus`
- 自定义指标（@Timed / Counter）：
  - 活跃 LiveSession 数（Gauge）
  - Agent 任务执行次数/耗时
  - GLM API 调用次数/token 消耗（如能从 Spring AI 拿到）
- 前端（可选）：在监控页加「应用」tab，读 /actuator/metrics 展示
- 或直接对接 Prometheus + Grafana（如果你有现成的）

**验证**：curl /actuator/health 返回 UP；/actuator/prometheus 有自定义指标。

---

## 建议交付顺序

1. **阶段 1**（底层，必做，1~2 个文件）
2. **阶段 2**（人用面板，独立可演示）
3. **阶段 4**（远端监控，独立可演示，面试亮点）
4. **阶段 3**（Agent 工具，依赖安全门禁，体现 AI 运维深度）
5. **阶段 5**（应用监控，工程完整性加分）

每阶段做完即可 commit + browse 验证，互不阻塞。

## 风险点

- **连接竞争**：SFTP/监控/Agent 共用同一 JSch Session，必须用 LiveSession.lock() 串行化，否则 channel 串数据。这是最大的坑。
- **监控采集开销**：5s 轮询跑 top/free/df，注意别给目标服务器加负载；间隔可配。
- **写文件安全**：阶段 3 的写操作是真能改坏服务器的，安全门禁不能省。
