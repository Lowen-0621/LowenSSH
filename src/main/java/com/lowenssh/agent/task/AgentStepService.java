package com.lowenssh.agent.task;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.lowenssh.persistence.entity.AgentStepEntity;
import com.lowenssh.persistence.entity.AgentTaskEntity;
import com.lowenssh.persistence.mapper.AgentStepMapper;
import com.lowenssh.persistence.mapper.AgentTaskMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.UUID;

/**
 * Step 持久化服务。
 *
 * 同一 taskId/toolCallId/actionDigest 只创建一条记录，为后续工具“一次执行权”奠定数据库边界。
 */
@Service
public class AgentStepService {

    private final AgentTaskMapper taskMapper;
    private final AgentStepMapper stepMapper;
    private final ObjectMapper objectMapper;

    public AgentStepService(AgentTaskMapper taskMapper,
                            AgentStepMapper stepMapper,
                            ObjectMapper objectMapper) {
        this.taskMapper = taskMapper;
        this.stepMapper = stepMapper;
        this.objectMapper = objectMapper;
    }

    @Transactional
    public AgentStepEntity createOrGet(String taskId,
                                       String toolCallId,
                                       TaskPhase phase,
                                       String stepType,
                                       String toolName,
                                       String argumentsJson,
                                       String policyVersion) {
        AgentTaskEntity task = taskMapper.selectForUpdate(taskId);
        if (task == null) {
            throw new TaskNotFoundException(taskId);
        }
        String canonicalArgs = CanonicalJson.canonicalize(objectMapper, argumentsJson);
        String actionDigest = RequestFingerprint.sha256(
                toolName, canonicalArgs, task.getHostId(), policyVersion);

        AgentStepEntity existing = stepMapper.selectByBusinessKeyForUpdate(
                taskId, toolCallId, actionDigest);
        if (existing != null) {
            return existing;
        }

        long sequence = task.getNextStepSequence();
        AgentStepEntity step = new AgentStepEntity();
        step.setStepId(UUID.randomUUID().toString());
        step.setTaskId(taskId);
        step.setSequenceNo(Math.toIntExact(sequence));
        step.setToolCallId(toolCallId);
        step.setPhase(phase.name());
        step.setStepType(stepType);
        step.setStatus("PENDING");
        step.setToolName(toolName);
        step.setArgumentsJson(canonicalArgs);
        step.setActionDigest(actionDigest);
        step.setVersion(0L);

        int advanced = taskMapper.advanceStepSequence(
                taskId, sequence + 1, task.getVersion());
        if (advanced != 1) {
            throw new IllegalStateException("任务 Step 序号并发更新失败: " + taskId);
        }
        int inserted = stepMapper.insertIgnore(step);
        if (inserted == 1) {
            return step;
        }
        AgentStepEntity raced = stepMapper.selectByBusinessKeyForUpdate(
                taskId, toolCallId, actionDigest);
        if (raced == null) {
            throw new IllegalStateException("Step 幂等插入失败且无法读取已有记录");
        }
        return raced;
    }
}
