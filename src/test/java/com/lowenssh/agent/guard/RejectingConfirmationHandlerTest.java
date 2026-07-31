package com.lowenssh.agent.guard;

import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertFalse;

class RejectingConfirmationHandlerTest {

    @Test
    void 旧接口对两种确认入口都失败关闭() {
        var handler = RejectingConfirmationHandler.INSTANCE;

        assertFalse(handler.confirm("systemctl restart nginx", "服务重启"));
        assertFalse(handler.confirm(new ConfirmationRequest(
                "call-1", "execCommand", "{}", "systemctl restart nginx",
                "服务重启", "HIGH", List.of("service-control"), "v1")));
    }
}
