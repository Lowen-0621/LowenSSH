package com.lowenssh.agent.approval;

import com.lowenssh.agent.task.AgentStepService;
import com.lowenssh.agent.task.TaskTransitionService;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.time.Duration;

/** 为每个任务创建独立的持久化确认器。 */
@Component
public class PersistentConfirmationHandlerFactory {

    private final AgentStepService stepService;
    private final ApprovalCoordinator coordinator;
    private final TaskTransitionService transitionService;
    private final Duration timeout;
    private final String policyVersion;

    public PersistentConfirmationHandlerFactory(
            AgentStepService stepService,
            ApprovalCoordinator coordinator,
            TaskTransitionService transitionService,
            @Value("${xwssh.agent.approval-timeout:PT2M}") Duration timeout,
            @Value("${xwssh.security.policy-version:v1}") String policyVersion) {
        this.stepService = stepService;
        this.coordinator = coordinator;
        this.transitionService = transitionService;
        this.timeout = timeout;
        this.policyVersion = policyVersion;
    }

    public PersistentConfirmationHandler create(String taskId) {
        return new PersistentConfirmationHandler(
                taskId,
                stepService,
                coordinator,
                transitionService,
                timeout,
                policyVersion
        );
    }
}
