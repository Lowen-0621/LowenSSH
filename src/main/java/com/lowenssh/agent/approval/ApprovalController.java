package com.lowenssh.agent.approval;

import com.fasterxml.jackson.databind.JsonNode;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import static com.lowenssh.agent.approval.ApprovalApiDto.DecideApprovalRequest;

/** 独立审批 HTTP 入口；SSE 只负责推送 approval_required。 */
@RestController
@RequestMapping("/api/agent/approvals")
public class ApprovalController {

    private final ApprovalDecisionService decisionService;

    public ApprovalController(ApprovalDecisionService decisionService) {
        this.decisionService = decisionService;
    }

    @PostMapping("/{approvalId}")
    public ResponseEntity<JsonNode> decide(
            @PathVariable String approvalId,
            @RequestHeader("Idempotency-Key") String idempotencyKey,
            @RequestBody DecideApprovalRequest request) {
        ApprovalDecisionService.DecisionResult result =
                decisionService.decide(approvalId, idempotencyKey, request);
        return ResponseEntity.status(result.httpStatus())
                .header("Idempotency-Replayed", Boolean.toString(result.replayed()))
                .body(result.body());
    }
}
