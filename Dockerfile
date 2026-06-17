# ---- 阶段 1：构建前端 ----
# Vite 产物输出到 ../src/main/resources/static，被后端打进 jar 一起托管
FROM node:22-alpine AS frontend
WORKDIR /build/frontend
# 先拷依赖清单，利用 Docker 层缓存：源码变了不必重装依赖
COPY frontend/package*.json ./
RUN npm ci
COPY frontend/ ./
# 产物写到 /build/src/main/resources/static（相对 outDir ../src/...）
RUN npm run build

# ---- 阶段 2：打后端 jar ----
FROM maven:3.9-eclipse-temurin-17 AS backend
WORKDIR /build
# 先拷 pom 预热依赖缓存
COPY pom.xml ./
RUN mvn -q dependency:go-offline
# 拷后端源码 + 上一阶段构建好的前端产物
COPY src/ ./src/
COPY --from=frontend /build/src/main/resources/static ./src/main/resources/static
# 跳过测试打包（测试需要 MySQL，构建环境没有）
RUN mvn -q clean package -DskipTests

# ---- 阶段 3：运行 ----
# 只带 JRE，镜像更小
FROM eclipse-temurin:17-jre
WORKDIR /app
COPY --from=backend /build/target/xiaowenssh-*.jar app.jar
EXPOSE 8081
# 密钥全走环境变量，镜像里不含任何凭据
ENTRYPOINT ["java", "-jar", "app.jar"]
