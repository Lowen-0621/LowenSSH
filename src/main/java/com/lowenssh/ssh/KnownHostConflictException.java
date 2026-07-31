package com.lowenssh.ssh;

/** 同一 hostToken 已存在不同 Host Key，禁止静默覆盖。 */
public class KnownHostConflictException extends RuntimeException {

    public KnownHostConflictException(String hostToken) {
        super("主机 " + hostToken + " 已有不同 Host Key；请先人工核对变更原因");
    }
}
