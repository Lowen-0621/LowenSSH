import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import { fileURLToPath, URL } from 'node:url'

// Vite 配置
// - dev: proxy 把 /api 转发到后端 8081，解决本地跨域
// - build: 产物直接输出到 Spring Boot 的 static 目录，生产单端口部署（访问 8081 即可）
export default defineConfig({
  plugins: [vue()],
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url))
    }
  },
  server: {
    port: 5173,
    proxy: {
      '/api': {
        target: 'http://localhost:8081',
        changeOrigin: true
      }
    }
  },
  build: {
    // 输出到后端静态资源目录，mvn 打包时一并带上
    outDir: '../src/main/resources/static',
    emptyOutDir: true
  }
})
