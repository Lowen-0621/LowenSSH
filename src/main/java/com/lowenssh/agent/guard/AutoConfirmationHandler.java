package com.lowenssh.agent.guard;

/**
 * 自动确认实现 —— REST/自动化测试场景用：ask 态默认放行。
 *
 * 注意：这不削弱安全。deny 态命令在门禁那层就被拦死了，根本到不了这里；
 * 这里只处理 ask 态（"可疑但不致命"），自动场景下选择放行以便自动化跑通。
 * 真要人盯着的高危场景用 ConsoleConfirmationHandler 走真人 y/n。
 */
public class AutoConfirmationHandler implements ConfirmationHandler {

    @Override
    public boolean confirm(String command, String reason) {
        // 自动放行 ask 态命令（deny 已在门禁拦截）
        return true;
    }
}
