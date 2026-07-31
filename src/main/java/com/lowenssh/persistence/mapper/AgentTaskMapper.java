package com.lowenssh.persistence.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.lowenssh.persistence.entity.AgentTaskEntity;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;
import org.apache.ibatis.annotations.Update;

import java.time.LocalDateTime;
import java.util.List;

/** Agent 任务 Mapper。 */
@Mapper
public interface AgentTaskMapper extends BaseMapper<AgentTaskEntity> {

    @Select("SELECT * FROM t_agent_task WHERE task_id = #{taskId} FOR UPDATE")
    AgentTaskEntity selectForUpdate(@Param("taskId") String taskId);

    @Update("""
            UPDATE t_agent_task
            SET status = #{status}, phase = #{phase}, version = version + 1,
                updated_at = CURRENT_TIMESTAMP(6)
            WHERE task_id = #{taskId} AND version = #{version}
            """)
    int transition(@Param("taskId") String taskId,
                   @Param("status") String status,
                   @Param("phase") String phase,
                   @Param("version") long version);

    @Update("""
            UPDATE t_agent_task
            SET next_event_sequence = #{nextSequence}, version = version + 1,
                updated_at = CURRENT_TIMESTAMP(6)
            WHERE task_id = #{taskId} AND version = #{version}
            """)
    int advanceEventSequence(@Param("taskId") String taskId,
                             @Param("nextSequence") long nextSequence,
                             @Param("version") long version);

    @Update("""
            UPDATE t_agent_task
            SET next_step_sequence = #{nextSequence}, version = version + 1,
                updated_at = CURRENT_TIMESTAMP(6)
            WHERE task_id = #{taskId} AND version = #{version}
            """)
    int advanceStepSequence(@Param("taskId") String taskId,
                            @Param("nextSequence") long nextSequence,
                            @Param("version") long version);

    @Update("""
            UPDATE t_agent_task
            SET status = #{status}, cancel_requested = 1, version = version + 1,
                updated_at = CURRENT_TIMESTAMP(6)
            WHERE task_id = #{taskId} AND version = #{version}
            """)
    int requestCancellation(@Param("taskId") String taskId,
                            @Param("status") String status,
                            @Param("version") long version);

    @Select("""
            SELECT * FROM t_agent_task
            WHERE deadline_at IS NOT NULL
              AND deadline_at <= #{now}
              AND status NOT IN ('SUCCEEDED', 'FAILED', 'CANCELLED', 'TIMED_OUT',
                                 'NEEDS_REVIEW', 'CANCELLING')
            ORDER BY deadline_at
            LIMIT #{limit}
            """)
    List<AgentTaskEntity> selectOverdue(@Param("now") LocalDateTime now,
                                        @Param("limit") int limit);

    @Update("""
            UPDATE t_agent_task
            SET tool_calls = tool_calls + 1, version = version + 1,
                updated_at = CURRENT_TIMESTAMP(6)
            WHERE task_id = #{taskId} AND version = #{version}
            """)
    int incrementToolCalls(@Param("taskId") String taskId,
                           @Param("version") long version);

    @Update("""
            UPDATE t_agent_task
            SET consecutive_failures = #{failures}, version = version + 1,
                updated_at = CURRENT_TIMESTAMP(6)
            WHERE task_id = #{taskId} AND version = #{version}
            """)
    int updateConsecutiveFailures(@Param("taskId") String taskId,
                                  @Param("failures") int failures,
                                  @Param("version") long version);

    @Update("""
            UPDATE t_agent_task
            SET model_calls = model_calls + 1, version = version + 1,
                updated_at = CURRENT_TIMESTAMP(6)
            WHERE task_id = #{taskId} AND version = #{version}
            """)
    int incrementModelCalls(@Param("taskId") String taskId,
                            @Param("version") long version);

    @Update("""
            UPDATE t_agent_task
            SET tool_calls = tool_calls + #{count}, version = version + 1,
                updated_at = CURRENT_TIMESTAMP(6)
            WHERE task_id = #{taskId} AND version = #{version}
            """)
    int addToolCalls(@Param("taskId") String taskId,
                     @Param("count") int count,
                     @Param("version") long version);

    @Update("""
            UPDATE t_agent_task
            SET status = #{status}, phase = #{phase}, final_summary = #{summary},
                error_code = #{errorCode}, error_message = #{errorMessage},
                finished_at = CURRENT_TIMESTAMP(6), version = version + 1,
                updated_at = CURRENT_TIMESTAMP(6)
            WHERE task_id = #{taskId} AND version = #{version}
            """)
    int finish(@Param("taskId") String taskId,
               @Param("status") String status,
               @Param("phase") String phase,
               @Param("summary") String summary,
               @Param("errorCode") String errorCode,
               @Param("errorMessage") String errorMessage,
               @Param("version") long version);

    @Select("""
            SELECT * FROM t_agent_task
            WHERE status IN ('CREATED', 'PLANNING', 'RISK_CHECKING',
                             'WAITING_APPROVAL', 'EXECUTING', 'VERIFYING',
                             'SUMMARIZING', 'CANCELLING')
            ORDER BY updated_at
            LIMIT #{limit}
            """)
    List<AgentTaskEntity> selectRecoverable(@Param("limit") int limit);
}
