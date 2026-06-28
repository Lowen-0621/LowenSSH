# ---- 阶段 1：打后端 jar ----
FROM maven:3.9-eclipse-temurin-17 AS backend
WORKDIR /build
# 先拷 pom 预热依赖缓存：源码变了不必重新下依赖
COPY pom.xml ./
RUN mvn -q dependency:go-offline
# 拷后端源码
COPY src/ ./src/
# 跳过测试打包（测试需要 MySQL，构建环境没有）
RUN mvn -q clean package -DskipTests

# ---- 阶段 2：运行 ----
# 只带 JRE，镜像更小
FROM eclipse-temurin:17-jre
WORKDIR /app
COPY --from=backend /build/target/lowenssh-*.jar app.jar
EXPOSE 8081
# 纯后端 API 服务，供 Flutter 桌面端 / CLI 客户端连接
# 密钥全走环境变量，镜像里不含任何凭据
ENTRYPOINT ["java", "-jar", "app.jar"]
