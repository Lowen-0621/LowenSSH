package com.lowenssh.agent.task;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import static com.lowenssh.agent.task.TaskApiDto.ApiError;

/** 新任务 API 的稳定错误码。 */
@RestControllerAdvice(assignableTypes = TaskController.class)
public class TaskApiExceptionHandler {

    @ExceptionHandler(IdempotencyConflictException.class)
    public ResponseEntity<ApiError> idempotencyConflict(IdempotencyConflictException e) {
        return ResponseEntity.status(HttpStatus.CONFLICT)
                .body(new ApiError("IDEMPOTENCY_KEY_REUSED", e.getMessage()));
    }

    @ExceptionHandler(TaskNotFoundException.class)
    public ResponseEntity<ApiError> taskNotFound(TaskNotFoundException e) {
        return ResponseEntity.status(HttpStatus.NOT_FOUND)
                .body(new ApiError("TASK_NOT_FOUND", e.getMessage()));
    }

    @ExceptionHandler(IllegalTaskTransitionException.class)
    public ResponseEntity<ApiError> illegalTransition(IllegalTaskTransitionException e) {
        return ResponseEntity.status(HttpStatus.CONFLICT)
                .body(new ApiError("ILLEGAL_TASK_TRANSITION", e.getMessage()));
    }

    @ExceptionHandler(IllegalArgumentException.class)
    public ResponseEntity<ApiError> badRequest(IllegalArgumentException e) {
        return ResponseEntity.badRequest()
                .body(new ApiError("INVALID_REQUEST", e.getMessage()));
    }
}
