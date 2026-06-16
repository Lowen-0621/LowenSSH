package com.xiaowenssh.ssh;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * SSH 测试接口 —— M1 第二步验证 SshClient 用，验证完会删掉。
 * 例：http://localhost:8081/api/ssh/exec?host=1.2.3.4&user=root&password=xxx&cmd=ls -al
 */
@RestController
public class SshTestController {

    @GetMapping("/api/ssh/exec")
    public String exec(@RequestParam String host,
                       @RequestParam(defaultValue = "22") int port,
                       @RequestParam String user,
                       @RequestParam String password,
                       @RequestParam String cmd) {
        try (SshClient client = new SshClient()) {
            client.connect(host, port, user, password);
            ExecResult r = client.exec(cmd);
            return "exitCode=" + r.exitCode() + "\n"
                    + "--- stdout ---\n" + r.stdout()
                    + "--- stderr ---\n" + r.stderr();
        } catch (Exception e) {
            return "执行失败: " + e.getMessage();
        }
    }
}
