package com.lowenssh.persistence.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.lowenssh.persistence.entity.SessionEntity;
import org.apache.ibatis.annotations.Mapper;

/**
 * 会话 Mapper —— 继承 BaseMapper 即得基础 CRUD，无需写 XML
 */
@Mapper
public interface SessionMapper extends BaseMapper<SessionEntity> {
}
