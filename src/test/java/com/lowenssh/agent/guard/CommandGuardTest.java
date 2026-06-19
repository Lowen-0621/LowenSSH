package com.lowenssh.agent.guard;

import com.lowenssh.agent.guard.CommandGuard.Decision;
import com.lowenssh.agent.guard.CommandGuard.Verdict;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;

/**
 * 门禁单测 —— 三态判定是 Agent 安全的硬边界，必须覆盖到位。
 * 不依赖 SSH/模型，纯逻辑，跑得快。
 */
class CommandGuardTest {

    private final CommandGuard guard = new CommandGuard();

    private Decision decide(String cmd) {
        return guard.evaluate(cmd).decision();
    }

    // —— allow：只读命令 ——
    @Test
    void 只读命令放行() {
        assertEquals(Decision.ALLOW, decide("df -h"));
        assertEquals(Decision.ALLOW, decide("ps aux | grep java"));
        assertEquals(Decision.ALLOW, decide("cat /etc/hostname"));
        assertEquals(Decision.ALLOW, decide("free -m"));
    }

    // —— deny：毁灭性命令直接拒 ——
    @Test
    void 危险命令拒绝() {
        assertEquals(Decision.DENY, decide("rm -rf /"));
        assertEquals(Decision.DENY, decide("rm -rf /var/data"));
        assertEquals(Decision.DENY, decide("rm -fr /tmp/x"));
        assertEquals(Decision.DENY, decide("mkfs.ext4 /dev/sdb"));
        assertEquals(Decision.DENY, decide("dd if=/dev/zero of=/dev/sda"));
        assertEquals(Decision.DENY, decide("shutdown -h now"));
        assertEquals(Decision.DENY, decide("reboot"));
    }

    // —— ask：有副作用，要确认 ——
    @Test
    void 副作用命令要确认() {
        assertEquals(Decision.ASK, decide("rm /tmp/a.log"));      // 普通 rm（非 -rf）
        assertEquals(Decision.ASK, decide("kill 1234"));
        assertEquals(Decision.ASK, decide("systemctl restart nginx"));
        assertEquals(Decision.ASK, decide("chmod 777 /etc/passwd"));
        assertEquals(Decision.ASK, decide("apt-get install vim"));
    }

    // —— 复合命令拆段：任一段最严即整条最严 ——
    @Test
    void 复合命令取最严() {
        // 前段安全、后段毁灭 → DENY（防整条被当一段漏过）
        assertEquals(Decision.DENY, decide("ls && rm -rf /data"));
        // 管道里藏 dd → DENY
        assertEquals(Decision.DENY, decide("cat x | dd of=/dev/sda"));
        // 分号串联，含 ask 段 → ASK
        assertEquals(Decision.ASK, decide("df -h; systemctl stop nginx"));
        // 全段安全 → ALLOW
        assertEquals(Decision.ALLOW, decide("cd /var && ls -al"));
    }

    // —— deny 优先于 ask：评估顺序保证 deny 永远赢 ——
    @Test
    void deny优先于ask() {
        // rm -rf 同时命中 ask(rm) 和 deny(rm -rf)，必须 DENY
        assertEquals(Decision.DENY, decide("rm -rf /opt/app"));
    }

    // —— 边界 ——
    @Test
    void 空命令放行() {
        assertEquals(Decision.ALLOW, decide(""));
        assertEquals(Decision.ALLOW, decide("   "));
        assertEquals(Decision.ALLOW, decide(null));
    }

    // —— 防误伤：dd 不该误伤 add，rm 不该误伤 chmod 之外的词 ——
    @Test
    void 不误伤子串() {
        assertEquals(Decision.ALLOW, decide("git add ."));     // add 含 dd 不该命中
        assertEquals(Decision.ALLOW, decide("echo warm"));      // warm 含 rm 不该命中
    }

    @Test
    void 拒绝原因可读() {
        Verdict v = guard.evaluate("rm -rf /");
        assertEquals(Decision.DENY, v.decision());
        // 原因里应带命中片段，便于回灌给模型/展示用户
        org.junit.jupiter.api.Assertions.assertTrue(v.reason().contains("rm"));
    }

    // —— find 等价绕过：真机联调发现模型被拦 rm -rf 后改用 find 删除 ——
    @Test
    void find删除变体也拒绝() {
        assertEquals(Decision.DENY, decide("find /tmp -mindepth 1 -delete"));
        assertEquals(Decision.DENY, decide("find /var/log -name '*.log' -delete"));
        assertEquals(Decision.DENY, decide("find /data -type f -exec rm -f {} \\;"));
        // 普通 find 查找不该误伤
        assertEquals(Decision.ALLOW, decide("find /etc -name nginx.conf"));
    }
}
