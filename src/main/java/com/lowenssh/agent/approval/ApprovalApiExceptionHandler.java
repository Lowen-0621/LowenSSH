package com.lowenssh.agent.approval;

import com.lowenssh.agent.task.TaskApiDto;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

/** 审批接口参数错误的稳定响应。 */
@RestControllerAdvice(assignableTypes = ApprovalController.class)
public class ApprovalApiExceptionHandler {

    @ExceptionHandler(IllegalArgumentException.class)
    public ResponseEntity<TaskApiDto.ApiError> badRequest(IllegalArgumentException e) {
        return ResponseEntity.badRequest()
                .body(new TaskApiDto.ApiError("INVALID_REQUEST", e.getMessage()));
    }
}
