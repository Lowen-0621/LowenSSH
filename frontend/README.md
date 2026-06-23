# LowenSSH 前端

AI SSH 智能运维 Agent 的 Web 界面。一套代码两种界面，共享同一份会话状态：

- **图形版** `/`：卡片 + 气泡混排，定位「这是个产品」，适合演示和不熟命令行的用户。
- **终端版** `/terminal`：仿 SSH 会话的单列 log 流，全等宽字体，定位「这是个工具」，适合运维人员。

技术栈：Vite 6 + Vue 3.5（Composition API）+ vue-router 4。设计规范见仓库根目录 `DESIGN.md`。

## 开发

```bash
npm install
npm run dev      # 启动 dev server（默认 5173），/api 代理到 localhost:8081 后端
```

后端需先跑起来（见根目录 README），dev server 通过 `vite.config.js` 里的 proxy 把 `/api` 转发到后端，避免跨域。

## 构建

```bash
npm run build    # 产物输出到 ../src/main/resources/static/，由 Spring Boot 直接托管
```

构建后启动后端即可访问完整应用，无需单独部署前端。`static/` 目录不提交（已在 .gitignore），由构建生成。

## 关键实现

- **SSE 流式**：后端是 POST 流式端点，`EventSource` 只支持 GET，所以用 `fetch` + `ReadableStream` 手动解析 SSE（见 `composables/useAgentStream.js`）。
- **跨视图共享**：`useAgentStream` 用模块级单例，图形版和终端版切换时会话不丢。
- **6 类事件渲染**：`token`/`tool_call`/`tool_result`/`blocked`/`done`/`error`，其中 `blocked`（安全门禁拦截）视觉权重最重——红边框 + 染底 + 图标，让人一眼看到护栏起了作用。

## 安全

密码字段 `type=password` + `autocomplete=off`，不写入 localStorage/sessionStorage，不打印到 console。
