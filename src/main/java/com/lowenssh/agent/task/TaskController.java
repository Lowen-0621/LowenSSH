package com.lowenssh.agent.task;

import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.http.codec.ServerSentEvent;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Flux;

import static com.lowenssh.agent.task.TaskApiDto.CreateTaskRequest;
import static com.lowenssh.agent.task.TaskApiDto.CreateTaskResponse;
import static com.lowenssh.agent.task.TaskApiDto.CancelTaskResponse;
import static com.lowenssh.agent.task.TaskApiDto.TaskView;

/** 可幂等创建、查询和订阅的新版 Agent 任务 API。 */
@RestController
@RequestMapping("/api/agent/tasks")
public class TaskController {

    private final TaskCommandService commandService;
    private final TaskEventService eventService;
    private final TaskCancellationService cancellationService;
    private final TaskWorkflowOrchestrator orchestrator;

    public TaskController(TaskCommandService commandService,
                          TaskEventService eventService,
                          TaskCancellationService cancellationService,
                          TaskWorkflowOrchestrator orchestrator) {
        this.commandService = commandService;
        this.eventService = eventService;
        this.cancellationService = cancellationService;
        this.orchestrator = orchestrator;
    }

    @PostMapping
    public ResponseEntity<CreateTaskResponse> create(
            @RequestHeader("Idempotency-Key") String idempotencyKey,
            @RequestBody CreateTaskRequest request) {
        TaskCommandService.CreateResult result = commandService.create(idempotencyKey, request);
        if (!result.replayed()) {
            orchestrator.start(result.response().taskId());
        }
        return ResponseEntity.accepted()
                .header("Idempotency-Replayed", Boolean.toString(result.replayed()))
                .body(result.response());
    }

    @GetMapping("/{taskId}")
    public TaskView get(@PathVariable String taskId) {
        return commandService.get(taskId);
    }

    @PostMapping("/{taskId}/cancel")
    public ResponseEntity<CancelTaskResponse> cancel(
            @PathVariable String taskId,
            @RequestHeader("Idempotency-Key") String idempotencyKey) {
        TaskCancellationService.CancelResult result =
                cancellationService.cancel(taskId, idempotencyKey);
        return ResponseEntity.ok()
                .header("Idempotency-Replayed", Boolean.toString(result.replayed()))
                .body(result.response());
    }

    @GetMapping(value = "/{taskId}/events", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public Flux<ServerSentEvent<TaskEventView>> events(
            @PathVariable String taskId,
            @RequestHeader(value = "Last-Event-ID", required = false) String lastEventId) {
        commandService.get(taskId); // 不存在立即返回 404，而不是建立一条永不出事件的流
        long afterId = parseLastEventId(lastEventId);
        return eventService.stream(taskId, afterId)
                .map(event -> ServerSentEvent.<TaskEventView>builder()
                        .id(Long.toString(event.id()))
                        .event(event.type())
                        .data(event)
                        .build());
    }

    private long parseLastEventId(String value) {
        if (value == null || value.isBlank()) {
            return 0;
        }
        try {
            long id = Long.parseLong(value);
            if (id < 0) {
                throw new IllegalArgumentException("Last-Event-ID 不能为负数");
            }
            return id;
        } catch (NumberFormatException e) {
            throw new IllegalArgumentException("Last-Event-ID 必须是整数", e);
        }
    }
}
