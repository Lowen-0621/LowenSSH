package com.lowenssh.persistence.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.lowenssh.persistence.entity.AuditEntity;
import org.apache.ibatis.annotations.Mapper;

/**
 * 审计 Mapper
 */
@Mapper
public interface AuditMapper extends BaseMapper<AuditEntity> {
}
