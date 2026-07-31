package com.lowenssh.persistence.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.lowenssh.persistence.entity.AgentTaskEventEntity;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

import java.util.List;

/** 可回放任务事件 Mapper。 */
@Mapper
public interface AgentTaskEventMapper extends BaseMapper<AgentTaskEventEntity> {

    @Select("""
            SELECT * FROM t_agent_event
            WHERE task_id = #{taskId} AND id > #{afterId}
            ORDER BY id ASC
            """)
    List<AgentTaskEventEntity> selectAfter(@Param("taskId") String taskId,
                                           @Param("afterId") long afterId);
}
