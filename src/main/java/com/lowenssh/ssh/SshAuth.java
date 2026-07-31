package com.lowenssh.ssh;

import java.nio.file.Path;

/** SSH 认证方式。私钥只保存路径/临时口令，不把私钥正文写入日志或任务表。 */
public sealed interface SshAuth permits SshAuth.Password, SshAuth.PrivateKey, SshAuth.Agent {

    record Password(String value) implements SshAuth {
    }

    record PrivateKey(Path path, String passphrase) implements SshAuth {
    }

    /**
     * JSch 需要额外的 agentproxy 连接器才能访问系统 SSH Agent。
     * 当前先显式建模并拒绝，不能把“尚未支持”伪装成密码认证成功。
     */
    record Agent() implements SshAuth {
    }
}
