package com.xiaowenssh.persistence;

import com.xiaowenssh.persistence.entity.SessionEntity;
import com.xiaowenssh.persistence.mapper.SessionMapper;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * 持久化测试接口 —— 验证 MyBatis-Plus 通路，验证完删。
 * 访问 http://localhost:8081/api/db/test 插一条 session 并返回自增 id
 */
@RestController
public class DbTestController {

    private final SessionMapper sessionMapper;

    public DbTestController(SessionMapper sessionMapper) {
        this.sessionMapper = sessionMapper;
    }

    @GetMapping("/api/db/test")
    public String test() {
        SessionEntity s = new SessionEntity();
        s.setTitle("测试会话");
        s.setSshHost("127.0.0.1");
        s.setSshPort(22);
        s.setSshUser("root");
        sessionMapper.insert(s);   // 插入后 MP 自动回填自增 id
        return "插入成功，新 session id = " + s.getId()
                + "，当前总会话数 = " + sessionMapper.selectCount(null);
    }
}
