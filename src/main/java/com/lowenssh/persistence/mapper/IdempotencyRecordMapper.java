package com.lowenssh.persistence.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.lowenssh.persistence.entity.IdempotencyRecordEntity;
import org.apache.ibatis.annotations.Insert;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;
import org.apache.ibatis.annotations.Update;

import java.time.LocalDateTime;

/** HTTP 幂等记录 Mapper。 */
@Mapper
public interface IdempotencyRecordMapper extends BaseMapper<IdempotencyRecordEntity> {

    @Insert("""
            INSERT INTO t_idempotency_record (
                scope, idempotency_key, request_hash, expires_at
            ) VALUES (
                #{scope}, #{key}, #{requestHash}, #{expiresAt}
            )
            ON DUPLICATE KEY UPDATE id = id
            """)
    int insertPlaceholder(@Param("scope") String scope,
                          @Param("key") String key,
                          @Param("requestHash") String requestHash,
                          @Param("expiresAt") LocalDateTime expiresAt);

    @Select("""
            SELECT * FROM t_idempotency_record
            WHERE scope = #{scope} AND idempotency_key = #{key}
            FOR UPDATE
            """)
    IdempotencyRecordEntity selectForUpdate(@Param("scope") String scope,
                                             @Param("key") String key);

    @org.apache.ibatis.annotations.Delete("""
            DELETE FROM t_idempotency_record
            WHERE scope = #{scope} AND idempotency_key = #{key}
              AND expires_at < CURRENT_TIMESTAMP(6)
            """)
    int deleteExpiredKey(@Param("scope") String scope, @Param("key") String key);

    @Update("""
            UPDATE t_idempotency_record
            SET resource_id = #{resourceId}, response_status = #{responseStatus},
                response_json = #{responseJson}, updated_at = CURRENT_TIMESTAMP(6)
            WHERE id = #{id}
            """)
    int saveResponse(@Param("id") long id,
                     @Param("resourceId") String resourceId,
                     @Param("responseStatus") int responseStatus,
                     @Param("responseJson") String responseJson);
}
