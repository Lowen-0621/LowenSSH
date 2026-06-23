package com.lowenssh;

import org.mybatis.spring.annotation.MapperScan;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

/**
 * LowenSSH 启动类 —— AI SSH 智能运维 Agent
 */
@SpringBootApplication
@EnableScheduling  // 开启定时任务：SessionManager 定时回收超时的常驻 SSH 连接
@MapperScan("com.lowenssh.persistence.mapper")  // 扫描 MyBatis Mapper 接口
public class LowenSshApplication {

    public static void main(String[] args) {
        SpringApplication.run(LowenSshApplication.class, args);
    }
}
