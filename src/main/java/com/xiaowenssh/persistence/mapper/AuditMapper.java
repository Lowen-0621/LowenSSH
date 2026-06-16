package com.xiaowenssh.persistence.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.xiaowenssh.persistence.entity.AuditEntity;
import org.apache.ibatis.annotations.Mapper;

/**
 * 审计 Mapper
 */
@Mapper
public interface AuditMapper extends BaseMapper<AuditEntity> {
}
