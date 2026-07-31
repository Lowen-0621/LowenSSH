package com.lowenssh.agent.task;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class TaskStateMachineTest {

    @Test
    void 主流程允许按阶段前进() {
        assertThat(TaskStateMachine.canTransition(TaskStatus.CREATED, TaskStatus.PLANNING)).isTrue();
        assertThat(TaskStateMachine.canTransition(TaskStatus.PLANNING, TaskStatus.RISK_CHECKING)).isTrue();
        assertThat(TaskStateMachine.canTransition(TaskStatus.RISK_CHECKING, TaskStatus.WAITING_APPROVAL)).isTrue();
        assertThat(TaskStateMachine.canTransition(TaskStatus.WAITING_APPROVAL, TaskStatus.EXECUTING)).isTrue();
        assertThat(TaskStateMachine.canTransition(TaskStatus.EXECUTING, TaskStatus.VERIFYING)).isTrue();
        assertThat(TaskStateMachine.canTransition(TaskStatus.VERIFYING, TaskStatus.SUMMARIZING)).isTrue();
        assertThat(TaskStateMachine.canTransition(TaskStatus.SUMMARIZING, TaskStatus.SUCCEEDED)).isTrue();
    }

    @Test
    void 相同状态重复提交是幂等操作() {
        assertThat(TaskStateMachine.canTransition(TaskStatus.WAITING_APPROVAL,
                TaskStatus.WAITING_APPROVAL)).isTrue();
    }

    @Test
    void 终态不能回退() {
        assertThatThrownBy(() -> TaskStateMachine.requireTransition(
                TaskStatus.SUCCEEDED, TaskStatus.EXECUTING))
                .isInstanceOf(IllegalTaskTransitionException.class)
                .hasMessageContaining("SUCCEEDED")
                .hasMessageContaining("EXECUTING");
    }

    @Test
    void 不能跳过风险检查直接执行() {
        assertThat(TaskStateMachine.canTransition(TaskStatus.CREATED, TaskStatus.EXECUTING)).isFalse();
    }

    @Test
    void 运行中状态可先取消中再取消完成() {
        assertThat(TaskStateMachine.canTransition(
                TaskStatus.EXECUTING, TaskStatus.CANCELLING)).isTrue();
        assertThat(TaskStateMachine.canTransition(
                TaskStatus.CANCELLING, TaskStatus.CANCELLED)).isTrue();
        assertThat(TaskStateMachine.canTransition(
                TaskStatus.CANCELLED, TaskStatus.EXECUTING)).isFalse();
    }
}
