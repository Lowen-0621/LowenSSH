package com.lowenssh.agent;

import com.lowenssh.ssh.ExecResult;
import com.lowenssh.ssh.SshClient;

/**
 * 主机指标采集器：用一条复合 shell 命令把 CPU/内存/磁盘/负载/uptime 的原始数据一次取回，
 * 在 Java 端解析，避免多次 SSH 往返。
 *
 * CPU 使用率需要两次 /proc/stat 采样求差：命令里 sleep 0.3 取前后两行，
 * 解析时算 (busyΔ / totalΔ) * 100。
 *
 * 输出用标记行分隔，逐段解析，避免被 locale / 多余空白干扰。
 */
public final class MetricsCollector {

    private MetricsCollector() {}

    // 一条命令取全部原始指标。各段用 ===TAG=== 包起来，Java 端按标记切分。
    private static final String CMD = String.join(" ; ",
            "echo ===CPU1===", "cat /proc/stat | grep '^cpu '",
            "sleep 0.3",
            "echo ===CPU2===", "cat /proc/stat | grep '^cpu '",
            "echo ===CORES===", "nproc",
            "echo ===LOAD===", "cat /proc/loadavg",
            "echo ===MEM===", "cat /proc/meminfo | grep -E '^(MemTotal|MemAvailable):'",
            "echo ===DISK===", "df -k / | tail -1",
            "echo ===UPTIME===", "cat /proc/uptime"
    );

    /** 在已加锁的 SshClient 上采集一次。调用方负责 lock。 */
    public static HostMetrics collect(SshClient ssh) throws Exception {
        ExecResult r = ssh.exec(CMD);
        if (!r.isSuccess()) {
            throw new IllegalStateException("采集失败 exit=" + r.exitCode() + " " + r.stderr());
        }
        return parse(r.stdout());
    }

    // —— 解析 ——
    static HostMetrics parse(String out) {
        String[] lines = out.split("\n");
        // 先把各标记段的内容收集起来
        String cpu1 = null, cpu2 = null, cores = null, load = null, disk = null, uptime = null;
        String memTotal = null, memAvail = null;
        String tag = "";
        for (String raw : lines) {
            String line = raw.trim();
            if (line.startsWith("===") && line.endsWith("===")) {
                tag = line;
                continue;
            }
            if (line.isEmpty()) continue;
            switch (tag) {
                case "===CPU1===" -> cpu1 = line;
                case "===CPU2===" -> cpu2 = line;
                case "===CORES===" -> cores = line;
                case "===LOAD===" -> load = line;
                case "===MEM===" -> {
                    if (line.startsWith("MemTotal")) memTotal = line;
                    else if (line.startsWith("MemAvailable")) memAvail = line;
                }
                case "===DISK===" -> disk = line;
                case "===UPTIME===" -> uptime = line;
                default -> { /* 忽略 */ }
            }
        }

        double cpuPercent = parseCpu(cpu1, cpu2);
        int cpuCores = parseInt(cores, 1);

        double[] loads = parseLoad(load);

        long memTotalKb = parseMemKb(memTotal);
        long memAvailKb = parseMemKb(memAvail);
        long memUsedKb = Math.max(0, memTotalKb - memAvailKb);
        double memPercent = memTotalKb > 0 ? memUsedKb * 100.0 / memTotalKb : 0;

        long[] diskKb = parseDisk(disk);       // [total, used]
        double diskPercent = diskKb[0] > 0 ? diskKb[1] * 100.0 / diskKb[0] : 0;

        long uptimeSec = parseUptime(uptime);

        return new HostMetrics(
                round1(cpuPercent), cpuCores,
                loads[0], loads[1], loads[2],
                memTotalKb, memUsedKb, round1(memPercent),
                diskKb[0], diskKb[1], round1(diskPercent),
                uptimeSec
        );
    }

    // /proc/stat 行：cpu  user nice system idle iowait irq softirq steal guest guest_nice
    // 使用率 = (totalΔ - idleΔ) / totalΔ * 100，idle = idle + iowait
    private static double parseCpu(String l1, String l2) {
        if (l1 == null || l2 == null) return 0;
        long[] a = cpuFields(l1);
        long[] b = cpuFields(l2);
        if (a == null || b == null) return 0;
        long idleA = a[3] + (a.length > 4 ? a[4] : 0);
        long idleB = b[3] + (b.length > 4 ? b[4] : 0);
        long totalA = sum(a), totalB = sum(b);
        long totalD = totalB - totalA, idleD = idleB - idleA;
        if (totalD <= 0) return 0;
        double pct = (totalD - idleD) * 100.0 / totalD;
        return clamp(pct);
    }

    private static long[] cpuFields(String line) {
        // 去掉开头的 "cpu" 标签
        String[] p = line.split("\\s+");
        if (p.length < 5) return null;
        long[] v = new long[p.length - 1];
        for (int i = 1; i < p.length; i++) {
            v[i - 1] = parseLong(p[i], 0);
        }
        return v;
    }

    // /proc/loadavg: "0.00 0.01 0.05 1/123 4567"
    private static double[] parseLoad(String line) {
        double[] d = {0, 0, 0};
        if (line == null) return d;
        String[] p = line.split("\\s+");
        for (int i = 0; i < 3 && i < p.length; i++) d[i] = parseDouble(p[i], 0);
        return d;
    }

    // "MemTotal:       16331756 kB"
    private static long parseMemKb(String line) {
        if (line == null) return 0;
        String[] p = line.split("\\s+");
        if (p.length < 2) return 0;
        return parseLong(p[1], 0);
    }

    // df -k / 末行: "/dev/vda1 41152736 8765432 30293560 23% /"
    private static long[] parseDisk(String line) {
        long[] r = {0, 0};
        if (line == null) return r;
        String[] p = line.split("\\s+");
        if (p.length >= 4) {
            r[0] = parseLong(p[1], 0); // total
            r[1] = parseLong(p[2], 0); // used
        }
        return r;
    }

    // /proc/uptime: "350735.47 234388.90"，取第一个
    private static long parseUptime(String line) {
        if (line == null) return 0;
        String[] p = line.split("\\s+");
        return (long) parseDouble(p[0], 0);
    }

    // —— 小工具 ——
    private static long sum(long[] a) { long s = 0; for (long x : a) s += x; return s; }
    private static double clamp(double v) { return v < 0 ? 0 : (v > 100 ? 100 : v); }
    private static double round1(double v) { return Math.round(v * 10) / 10.0; }

    private static int parseInt(String s, int def) {
        try { return Integer.parseInt(s.trim()); } catch (Exception e) { return def; }
    }
    private static long parseLong(String s, long def) {
        try { return Long.parseLong(s.trim()); } catch (Exception e) { return def; }
    }
    private static double parseDouble(String s, double def) {
        try { return Double.parseDouble(s.trim()); } catch (Exception e) { return def; }
    }
}
