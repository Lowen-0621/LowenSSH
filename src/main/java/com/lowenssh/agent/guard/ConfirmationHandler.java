package com.lowenssh.agent.guard;

/**
 * 人工确认抽象 —— ask 态命令在执行前问一句"干不干"。
 *
 * 为什么抽象成接口：不同入口的确认方式不一样。控制台走 System.in 真敲 y/n；
 * 将来 WebSocket 走前端弹窗。loop 只依赖这个接口，换入口不动核心逻辑。
 */
public interface ConfirmationHandler {

    /**
     * 请求用户确认是否执行某条命令。
     *
     * @param command 待执行的完整命令
     * @param reason  为什么需要确认（门禁给出的原因，例如"涉及写操作 rm"）
     * @return true=批准执行，false=拒绝
     */
    boolean confirm(String command, String reason);
}
