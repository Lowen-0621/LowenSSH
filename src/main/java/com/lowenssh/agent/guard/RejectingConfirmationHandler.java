package com.lowenssh.agent.guard;

/**
 * 失败关闭的确认器。
 *
 * 旧 REST/SSE 接口没有独立的审批回传通道，不能安全地等待用户确认。
 * 因此 ASK 一律拒绝；需要审批的任务必须改用持久化任务接口。
 */
public final class RejectingConfirmationHandler implements ConfirmationHandler {

    public static final RejectingConfirmationHandler INSTANCE = new RejectingConfirmationHandler();

    private RejectingConfirmationHandler() {
    }

    @Override
    public boolean confirm(String command, String reason) {
        return false;
    }
}
