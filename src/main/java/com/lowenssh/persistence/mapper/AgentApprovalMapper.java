package com.lowenssh.persistence.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.lowenssh.persistence.entity.AgentApprovalEntity;
import org.apache.ibatis.annotations.Insert;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;
import org.apache.ibatis.annotations.Update;

import java.time.LocalDateTime;
import java.util.List;

/** Agent 审批 Mapper。 */
@Mapper
public interface AgentApprovalMapper extends BaseMapper<AgentApprovalEntity> {

    @Insert("""
            INSERT INTO t_agent_approval (
                approval_id, task_id, step_id, tool_call_id, action_digest, status,
                risk_level, reason, matched_rules, expires_at, version
            ) VALUES (
                #{approval.approvalId}, #{approval.taskId}, #{approval.stepId},
                #{approval.toolCallId}, #{approval.actionDigest}, #{approval.status},
                #{approval.riskLevel}, #{approval.reason}, #{approval.matchedRules},
                #{approval.expiresAt}, 0
            )
            ON DUPLICATE KEY UPDATE approval_id = approval_id
            """)
    int insertOrKeepExisting(@Param("approval") AgentApprovalEntity approval);

    @Select("""
            SELECT * FROM t_agent_approval
            WHERE task_id = #{taskId}
              AND tool_call_id = #{toolCallId}
              AND action_digest = #{actionDigest}
            FOR UPDATE
            """)
    AgentApprovalEntity selectByActionForUpdate(@Param("taskId") String taskId,
                                                 @Param("toolCallId") String toolCallId,
                                                 @Param("actionDigest") String actionDigest);

    @Select("SELECT * FROM t_agent_approval WHERE approval_id = #{approvalId} FOR UPDATE")
    AgentApprovalEntity selectForUpdate(@Param("approvalId") String approvalId);

    @Update("""
            UPDATE t_agent_approval
            SET status = #{targetStatus}, decided_at = #{decidedAt},
                version = version + 1, updated_at = CURRENT_TIMESTAMP(6)
            WHERE approval_id = #{approvalId}
              AND status = 'PENDING'
              AND version = #{version}
            """)
    int decidePending(@Param("approvalId") String approvalId,
                      @Param("targetStatus") String targetStatus,
                      @Param("decidedAt") LocalDateTime decidedAt,
                      @Param("version") long version);

    @Select("""
            SELECT * FROM t_agent_approval
            WHERE status = 'PENDING' AND expires_at <= #{now}
            ORDER BY expires_at ASC
            LIMIT #{limit}
            """)
    List<AgentApprovalEntity> selectExpiredPending(@Param("now") LocalDateTime now,
                                                    @Param("limit") int limit);

    @Select("""
            SELECT * FROM t_agent_approval
            WHERE task_id = #{taskId}
            ORDER BY created_at DESC
            LIMIT 1
            """)
    AgentApprovalEntity selectLatestByTask(@Param("taskId") String taskId);
}
