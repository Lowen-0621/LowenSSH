package com.lowenssh.util;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

import javax.crypto.Cipher;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * 密码加密工具 —— 主机簿密码落库前用 AES-GCM 加密，绝不存明文。
 *
 * 为什么 AES-GCM：对称加密里 GCM 自带完整性校验（认证标签），密文被篡改解密会失败，
 * 比 AES-CBC 安全。密钥从环境变量 XWSSH_CRYPTO_KEY 读，遵循本项目「密钥走环境变量」惯例。
 *
 * 密文格式：Base64( iv[12] + cipherText + tag[16] )，IV 每次随机生成同密文一起存，
 * 解密时切出来用。同一明文每次加密结果不同（IV 随机），符合预期。
 *
 * 注意：这是演示/面试项目的够用方案。生产应上 KMS / Vault 管密钥，不靠单个环境变量。
 */
@Component
public class CryptoUtil {

    private static final Logger log = LoggerFactory.getLogger(CryptoUtil.class);
    private static final String ALGO = "AES/GCM/NoPadding";
    private static final int IV_LEN = 12;       // GCM 推荐 12 字节 IV
    private static final int TAG_BITS = 128;     // 认证标签 128 位
    private final Map<String, SecretKeySpec> keys;
    private final String activeVersion;
    private final SecureRandom random = new SecureRandom();

    @Autowired
    public CryptoUtil(
            @Value("${XWSSH_CRYPTO_KEY:}") String rawKey,
            @Value("${XWSSH_CRYPTO_KEYS:}") String keyRing,
            @Value("${xwssh.crypto.active-key-version:v1}") String activeVersion,
            @Value("${xwssh.crypto.allow-insecure-development-key:false}")
            boolean allowInsecureDevelopmentKey) {
        this.activeVersion = activeVersion;
        Map<String, String> material = parseKeyRing(keyRing);
        if (rawKey != null && !rawKey.isBlank()) {
            material.putIfAbsent(activeVersion, rawKey);
        }
        if (material.isEmpty()) {
            if (!allowInsecureDevelopmentKey) {
                throw new IllegalStateException(
                        "未配置 XWSSH_CRYPTO_KEY/XWSSH_CRYPTO_KEYS，禁止使用默认加密密钥");
            }
            material.put(activeVersion, "xwssh-dev-default-key-change-me");
            log.warn("仅测试模式：正在使用不安全的开发加密密钥");
        }
        if (!material.containsKey(activeVersion)) {
            throw new IllegalStateException("活动加密密钥版本不存在: " + activeVersion);
        }
        Map<String, SecretKeySpec> derived = new LinkedHashMap<>();
        material.forEach((version, value) ->
                derived.put(version, new SecretKeySpec(sha256(value), "AES")));
        this.keys = Map.copyOf(derived);
    }

    /** 纯单元测试兼容构造器。 */
    public CryptoUtil(String rawKey) {
        this(rawKey, "", "v1", false);
    }

    /** 加密：明文 → Base64(iv + 密文 + tag)。入参为空返回 null。 */
    public String encrypt(String plain) {
        if (plain == null || plain.isEmpty()) return null;
        try {
            byte[] iv = new byte[IV_LEN];
            random.nextBytes(iv);
            Cipher cipher = Cipher.getInstance(ALGO);
            cipher.init(Cipher.ENCRYPT_MODE, keys.get(activeVersion), new GCMParameterSpec(TAG_BITS, iv));
            byte[] ct = cipher.doFinal(plain.getBytes(StandardCharsets.UTF_8));
            // iv 拼在密文前一起 Base64
            byte[] out = new byte[iv.length + ct.length];
            System.arraycopy(iv, 0, out, 0, iv.length);
            System.arraycopy(ct, 0, out, iv.length, ct.length);
            return activeVersion + ":" + Base64.getEncoder().encodeToString(out);
        } catch (Exception e) {
            throw new IllegalStateException("密码加密失败", e);
        }
    }

    /** 解密：Base64(iv + 密文 + tag) → 明文。入参为空返回 null。 */
    public String decrypt(String enc) {
        if (enc == null || enc.isEmpty()) return null;
        try {
            String version = activeVersion;
            String payload = enc;
            int separator = enc.indexOf(':');
            if (separator > 0) {
                version = enc.substring(0, separator);
                payload = enc.substring(separator + 1);
            }
            SecretKeySpec key = keys.get(version);
            if (key == null) {
                throw new IllegalStateException("缺少解密密钥版本: " + version);
            }
            byte[] all = Base64.getDecoder().decode(payload);
            if (all.length < IV_LEN + 16) {
                throw new IllegalArgumentException("密文长度无效");
            }
            byte[] iv = new byte[IV_LEN];
            System.arraycopy(all, 0, iv, 0, IV_LEN);
            Cipher cipher = Cipher.getInstance(ALGO);
            cipher.init(Cipher.DECRYPT_MODE, key, new GCMParameterSpec(TAG_BITS, iv));
            byte[] plain = cipher.doFinal(all, IV_LEN, all.length - IV_LEN);
            return new String(plain, StandardCharsets.UTF_8);
        } catch (Exception e) {
            throw new IllegalStateException("密码解密失败（密钥变更或密文损坏）", e);
        }
    }

    private static byte[] sha256(String s) {
        try {
            return MessageDigest.getInstance("SHA-256").digest(s.getBytes(StandardCharsets.UTF_8));
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }

    private Map<String, String> parseKeyRing(String keyRing) {
        Map<String, String> result = new LinkedHashMap<>();
        if (keyRing == null || keyRing.isBlank()) {
            return result;
        }
        for (String entry : keyRing.split(",")) {
            String[] pair = entry.strip().split("=", 2);
            if (pair.length != 2 || pair[0].isBlank() || pair[1].isBlank()) {
                throw new IllegalArgumentException(
                        "XWSSH_CRYPTO_KEYS 格式应为 v2=新密钥,v1=旧密钥");
            }
            result.put(pair[0].strip(), pair[1]);
        }
        return result;
    }
}
