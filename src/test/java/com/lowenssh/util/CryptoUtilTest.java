package com.lowenssh.util;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class CryptoUtilTest {

    @Test
    void 新密文携带版本且轮换后仍能用旧Key解密() {
        CryptoUtil old = new CryptoUtil("", "v1=old-secret", "v1", false);
        String oldCipher = old.encrypt("server-password");
        CryptoUtil rotated = new CryptoUtil(
                "", "v2=new-secret,v1=old-secret", "v2", false);

        assertThat(oldCipher).startsWith("v1:");
        assertThat(rotated.decrypt(oldCipher)).isEqualTo("server-password");
        assertThat(rotated.encrypt("next-password")).startsWith("v2:");
    }

    @Test
    void 兼容没有版本前缀的历史密文() {
        CryptoUtil crypto = new CryptoUtil("legacy-secret");
        String versioned = crypto.encrypt("password");
        String legacy = versioned.substring(versioned.indexOf(':') + 1);

        assertThat(crypto.decrypt(legacy)).isEqualTo("password");
    }

    @Test
    void 未配置Key时生产模式拒绝启动() {
        assertThatThrownBy(() -> new CryptoUtil("", "", "v1", false))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("禁止使用默认加密密钥");
    }
}
