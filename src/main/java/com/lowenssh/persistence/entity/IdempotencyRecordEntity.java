package com.lowenssh.persistence.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.time.LocalDateTime;

/** HTTP 幂等记录，对应 t_idempotency_record。 */
@Data
@TableName("t_idempotency_record")
public class IdempotencyRecordEntity {

    @TableId(type = IdType.AUTO)
    private Long id;
    private String scope;
    private String idempotencyKey;
    private String requestHash;
    private String resourceId;
    private Integer responseStatus;
    private String responseJson;
    private LocalDateTime expiresAt;
    private LocalDateTime createdAt;
    private LocalDateTime updatedAt;
}
