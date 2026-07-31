package com.lowenssh.ssh;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.security.MessageDigest;
import java.util.Base64;
import java.util.List;
import java.util.Set;

/**
 * known_hosts 的显式导入流程。
 *
 * 本服务不替用户信任网络：用户应通过云控制台/运维渠道核对 preview 返回的 SHA256 指纹，
 * 再把同一指纹提交 trust。主机 Key 变化不会自动覆盖。
 */
@Service
public class KnownHostsService {

    private final Path knownHostsPath;

    public KnownHostsService(
            @Value("${xwssh.ssh.known-hosts-path:${user.home}/.lowenssh/known_hosts}")
            String knownHostsPath) {
        this.knownHostsPath = Path.of(knownHostsPath).toAbsolutePath().normalize();
    }

    public KnownHostPreview preview(String expectedHostToken, String line) {
        ParsedLine parsed = parse(expectedHostToken, line);
        return new KnownHostPreview(
                parsed.hostToken(), parsed.algorithm(),
                fingerprint(parsed.keyBytes()), false);
    }

    public synchronized KnownHostPreview trust(
            String expectedHostToken, String line, String expectedFingerprint) {
        ParsedLine parsed = parse(expectedHostToken, line);
        String actualFingerprint = fingerprint(parsed.keyBytes());
        if (expectedFingerprint == null
                || !MessageDigest.isEqual(
                actualFingerprint.getBytes(StandardCharsets.US_ASCII),
                expectedFingerprint.getBytes(StandardCharsets.US_ASCII))) {
            throw new IllegalArgumentException("确认指纹与主机 Key 不一致");
        }
        try {
            ensureFile();
            List<String> existing = Files.readAllLines(knownHostsPath, StandardCharsets.UTF_8);
            for (String existingLine : existing) {
                if (existingLine.isBlank() || existingLine.startsWith("#")) {
                    continue;
                }
                String[] fields = existingLine.strip().split("\\s+");
                if (fields.length >= 3 && fields[0].equals(parsed.hostToken())) {
                    if (existingLine.strip().equals(line.strip())) {
                        return new KnownHostPreview(
                                parsed.hostToken(), parsed.algorithm(),
                                actualFingerprint, true);
                    }
                    throw new KnownHostConflictException(parsed.hostToken());
                }
            }
            Files.writeString(
                    knownHostsPath, line.strip() + System.lineSeparator(),
                    StandardCharsets.UTF_8,
                    StandardOpenOption.APPEND);
            return new KnownHostPreview(
                    parsed.hostToken(), parsed.algorithm(), actualFingerprint, true);
        } catch (IOException e) {
            throw new IllegalStateException("写入 known_hosts 失败", e);
        }
    }

    private ParsedLine parse(String expectedHostToken, String line) {
        if (expectedHostToken == null || expectedHostToken.isBlank()) {
            throw new IllegalArgumentException("hostToken 不能为空");
        }
        if (line == null || line.isBlank() || line.contains("\n") || line.contains("\r")) {
            throw new IllegalArgumentException("known_hosts 行格式无效");
        }
        String[] fields = line.strip().split("\\s+");
        if (fields.length != 3) {
            throw new IllegalArgumentException("known_hosts 行必须包含 host、算法和公钥");
        }
        if (!fields[0].equals(expectedHostToken.strip())) {
            throw new IllegalArgumentException("known_hosts 主机与待信任主机不一致");
        }
        if (!fields[1].startsWith("ssh-") && !fields[1].startsWith("ecdsa-")) {
            throw new IllegalArgumentException("不支持的 SSH Host Key 算法");
        }
        try {
            return new ParsedLine(fields[0], fields[1], Base64.getDecoder().decode(fields[2]));
        } catch (IllegalArgumentException e) {
            throw new IllegalArgumentException("SSH Host Key 不是有效 Base64", e);
        }
    }

    private String fingerprint(byte[] key) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(key);
            return "SHA256:" + Base64.getEncoder().withoutPadding().encodeToString(digest);
        } catch (Exception e) {
            throw new IllegalStateException("计算 Host Key 指纹失败", e);
        }
    }

    private void ensureFile() throws IOException {
        Path parent = knownHostsPath.getParent();
        if (parent != null) {
            Files.createDirectories(parent);
        }
        if (Files.notExists(knownHostsPath)) {
            Files.createFile(knownHostsPath);
        }
        try {
            Files.setPosixFilePermissions(knownHostsPath, Set.of(
                    java.nio.file.attribute.PosixFilePermission.OWNER_READ,
                    java.nio.file.attribute.PosixFilePermission.OWNER_WRITE));
        } catch (UnsupportedOperationException ignored) {
            // Windows 等文件系统没有 POSIX 权限，仍依赖操作系统 ACL。
        }
    }

    private record ParsedLine(String hostToken, String algorithm, byte[] keyBytes) {
    }

    public record KnownHostPreview(
            String hostToken,
            String algorithm,
            String fingerprint,
            boolean trusted
    ) {
    }
}
