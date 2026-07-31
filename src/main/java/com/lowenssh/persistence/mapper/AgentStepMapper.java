package com.lowenssh.persistence.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.lowenssh.persistence.entity.AgentStepEntity;
import org.apache.ibatis.annotations.Insert;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;
import org.apache.ibatis.annotations.Update;

/** Agent Step Mapper。 */
@Mapper
public interface AgentStepMapper extends BaseMapper<AgentStepEntity> {

    @Insert("""
            INSERT INTO t_agent_step (
                step_id, task_id, sequence_no, tool_call_id, phase, step_type, status,
                tool_name, arguments_json, action_digest, version
            ) VALUES (
                #{step.stepId}, #{step.taskId}, #{step.sequenceNo}, #{step.toolCallId},
                #{step.phase}, #{step.stepType}, #{step.status}, #{step.toolName},
                #{step.argumentsJson}, #{step.actionDigest}, 0
            )
            ON DUPLICATE KEY UPDATE step_id = step_id
            """)
    int insertIgnore(@Param("step") AgentStepEntity step);

    @Select("""
            SELECT * FROM t_agent_step
            WHERE task_id = #{taskId}
              AND tool_call_id = #{toolCallId}
              AND action_digest = #{actionDigest}
            FOR UPDATE
            """)
    AgentStepEntity selectByBusinessKeyForUpdate(@Param("taskId") String taskId,
                                                  @Param("toolCallId") String toolCallId,
                                                  @Param("actionDigest") String actionDigest);

    @Select("SELECT * FROM t_agent_step WHERE step_id = #{stepId} FOR UPDATE")
    AgentStepEntity selectForUpdate(@Param("stepId") String stepId);

    @Update("""
            UPDATE t_agent_step
            SET status = #{status}, risk_level = #{riskLevel},
                policy_version = #{policyVersion}, matched_rules = #{matchedRules},
                version = version + 1, updated_at = CURRENT_TIMESTAMP(6)
            WHERE step_id = #{stepId} AND version = #{version}
            """)
    int markApprovalState(@Param("stepId") String stepId,
                          @Param("status") String status,
                          @Param("riskLevel") String riskLevel,
                          @Param("policyVersion") String policyVersion,
                          @Param("matchedRules") String matchedRules,
                          @Param("version") long version);

    @Update("""
            UPDATE t_agent_step
            SET phase = #{phase}, status = #{status}, risk_level = #{riskLevel},
                policy_version = #{policyVersion}, matched_rules = #{matchedRules},
                version = version + 1, updated_at = CURRENT_TIMESTAMP(6)
            WHERE step_id = #{stepId} AND version = #{version}
            """)
    int markRiskChecked(@Param("stepId") String stepId,
                        @Param("phase") String phase,
                        @Param("status") String status,
                        @Param("riskLevel") String riskLevel,
                        @Param("policyVersion") String policyVersion,
                        @Param("matchedRules") String matchedRules,
                        @Param("version") long version);

    @Update("""
            UPDATE t_agent_step
            SET phase = 'EXECUTE', status = 'EXECUTING', pre_snapshot = #{preSnapshot},
                started_at = CURRENT_TIMESTAMP(6), version = version + 1,
                updated_at = CURRENT_TIMESTAMP(6)
            WHERE step_id = #{stepId} AND version = #{version}
              AND status IN ('RISK_CHECKED', 'READY_TO_EXECUTE')
            """)
    int claimExecution(@Param("stepId") String stepId,
                       @Param("preSnapshot") String preSnapshot,
                       @Param("version") long version);

    @Update("""
            UPDATE t_agent_step
            SET status = #{status}, result_summary = #{resultSummary},
                exit_code = #{exitCode}, timed_out = #{timedOut}, truncated = #{truncated},
                finished_at = CURRENT_TIMESTAMP(6), version = version + 1,
                updated_at = CURRENT_TIMESTAMP(6)
            WHERE step_id = #{stepId} AND version = #{version}
              AND status = 'EXECUTING'
            """)
    int finishExecution(@Param("stepId") String stepId,
                        @Param("status") String status,
                        @Param("resultSummary") String resultSummary,
                        @Param("exitCode") Integer exitCode,
                        @Param("timedOut") boolean timedOut,
                        @Param("truncated") boolean truncated,
                        @Param("version") long version);

    @Update("""
            UPDATE t_agent_step
            SET phase = 'VERIFY', verification_plan = #{verificationPlan},
                verification_result = #{verificationResult},
                rollback_suggestion = #{rollbackSuggestion},
                version = version + 1, updated_at = CURRENT_TIMESTAMP(6)
            WHERE step_id = #{stepId} AND version = #{version}
            """)
    int saveVerification(@Param("stepId") String stepId,
                         @Param("verificationPlan") String verificationPlan,
                         @Param("verificationResult") String verificationResult,
                         @Param("rollbackSuggestion") String rollbackSuggestion,
                         @Param("version") long version);

    @Update("""
            UPDATE t_agent_step
            SET status = #{status}, result_summary = #{resultSummary},
                finished_at = CURRENT_TIMESTAMP(6), version = version + 1,
                updated_at = CURRENT_TIMESTAMP(6)
            WHERE step_id = #{stepId} AND version = #{version}
            """)
    int finishNonToolStep(@Param("stepId") String stepId,
                          @Param("status") String status,
                          @Param("resultSummary") String resultSummary,
                          @Param("version") long version);

    @Select("""
            SELECT * FROM t_agent_step
            WHERE task_id = #{taskId}
            ORDER BY sequence_no DESC
            LIMIT 1
            """)
    AgentStepEntity selectLatestByTask(@Param("taskId") String taskId);
}
