package com.lowenssh.agent;

/**
 * 远程主机监控指标快照（一次采集的结果）。
 * 字段都是采集瞬间的值，CPU 使用率由两次 /proc/stat 采样差值算得。
 */
public record HostMetrics(
        double cpuPercent,   // CPU 使用率 %（0~100）
        int cpuCores,        // 核数
        double load1,        // 1 分钟负载
        double load5,        // 5 分钟负载
        double load15,       // 15 分钟负载
        long memTotalKb,     // 内存总量 KB
        long memUsedKb,      // 已用内存 KB（total - available）
        double memPercent,   // 内存使用率 %
        long diskTotalKb,    // 根分区总量 KB
        long diskUsedKb,     // 根分区已用 KB
        double diskPercent,  // 根分区使用率 %
        long uptimeSec       // 开机时长（秒）
) {}
