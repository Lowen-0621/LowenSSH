package com.lowenssh.persistence.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.lowenssh.persistence.entity.MessageEntity;
import org.apache.ibatis.annotations.Mapper;

/**
 * 消息 Mapper
 */
@Mapper
public interface MessageMapper extends BaseMapper<MessageEntity> {
}
