package com.xiaowenssh;

import org.mybatis.spring.annotation.MapperScan;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * XiaowenSSH 启动类 —— AI SSH 智能运维 Agent
 */
@SpringBootApplication
@MapperScan("com.xiaowenssh.persistence.mapper")  // 扫描 MyBatis Mapper 接口
public class XiaowenSshApplication {

    public static void main(String[] args) {
        SpringApplication.run(XiaowenSshApplication.class, args);
    }
}
