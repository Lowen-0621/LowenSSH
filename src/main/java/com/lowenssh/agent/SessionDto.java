package com.lowenssh.agent;

import java.util.List;

/**
 * 左侧历史栏用的只读 DTO 集合。
 * 这些接口只查库 + 查常驻连接状态，不碰 SSH 执行，给前端会话列表/历史回看用。
 */
public final class SessionDto {

    private SessionDto() {
    }

    /** 会话列表项：左栏每一行 */
    public record SessionItem(Long id, String title, String host, String user, Integer port, String updatedAt) {
    }

    /** 单条历史消息：转成前端能直接渲染的格式 */
    public record HistoryMessage(String type, String text, String name, String summary) {
    }

    /**
     * 点开某会话的完整回看数据：连接信息 + 历史消息 + 常驻连接是否还活着。
     * live=true 表示能直接续聊（复用常驻连接）；false 则前端提示需重连。
     */
    public record SessionDetail(Long id, String host, Integer port, String user,
                                boolean live, List<HistoryMessage> messages) {
    }
}
