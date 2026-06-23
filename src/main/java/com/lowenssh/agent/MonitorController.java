package com.lowenssh.agent;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

/**
 * 远程主机监控接口（给人用）：前端轮询拉一次快照，自己在内存里攒历史画趋势。
 *
 *  - GET /api/monitor/{hostId}/metrics  采集一次 CPU/内存/磁盘/负载/uptime
 *
 * 复用主机常驻连接，lock 串行化，避免和 SFTP/Agent 抢同一 Session。
 */
@RestController
public class MonitorController {

    private final SessionManager sessionManager;

    public MonitorController(SessionManager sessionManager) {
        this.sessionManager = sessionManager;
    }

    @GetMapping("/api/monitor/{hostId}/metrics")
    public ResponseEntity<?> metrics(@PathVariable("hostId") Long hostId) {
        SessionManager.LiveSession ls = sessionManager.getByHost(hostId);
        if (ls == null) {
            return ResponseEntity.status(409).body(Map.of("error", "该主机未连接，请先从主机簿进入"));
        }
        ls.lock().lock();
        try {
            HostMetrics m = MetricsCollector.collect(ls.ssh());
            return ResponseEntity.ok(m);
        } catch (Exception e) {
            return ResponseEntity.status(500).body(Map.of("error", "采集失败: " + e.getMessage()));
        } finally {
            ls.lock().unlock();
        }
    }
}
