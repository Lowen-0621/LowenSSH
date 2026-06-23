package com.lowenssh.agent;

/**
 * 主机簿相关 DTO。密码绝不出现在响应里（只在 connect 入参里临时补填）。
 */
public final class HostDto {

    private HostDto() {
    }

    /** 主机列表项 / 新增响应。hasPassword 表示库里是否已存密码（false 则连接时需补填）。 */
    public record HostItem(Long id, String alias, String host, Integer port, String user, boolean hasPassword) {
    }

    /** 新增主机请求 */
    public record CreateRequest(String alias, String host, Integer port, String user, String password) {
    }

    /** 进入主机连接请求：库里没存密码时带上明文补连，否则可不传 */
    public record ConnectRequest(String password) {
    }

    /** 连接结果：成功带 sessionId，失败带 error */
    public record ConnectResult(Long sessionId, String error) {
    }
}
