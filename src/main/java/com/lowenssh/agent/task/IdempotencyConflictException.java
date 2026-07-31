package com.lowenssh.agent.task;

/** 同一个 Idempotency-Key 被用于不同请求。 */
public class IdempotencyConflictException extends RuntimeException {

    private final String key;

    public IdempotencyConflictException(String key) {
        super("Idempotency-Key 已被其他请求使用");
        this.key = key;
    }

    public String key() {
        return key;
    }
}
