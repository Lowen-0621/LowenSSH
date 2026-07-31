package com.lowenssh.agent;

import com.lowenssh.ssh.KnownHostConflictException;
import com.lowenssh.ssh.KnownHostsService;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** 显式预览和确认 Host Key；不会自动信任首次连接。 */
@RestController
@RequestMapping("/api/ssh/known-hosts")
public class SshSecurityController {

    private final KnownHostsService knownHostsService;

    public SshSecurityController(KnownHostsService knownHostsService) {
        this.knownHostsService = knownHostsService;
    }

    @PostMapping("/preview")
    public KnownHostsService.KnownHostPreview preview(
            @RequestBody KnownHostRequest request) {
        return knownHostsService.preview(request.hostToken(), request.knownHostsLine());
    }

    @PostMapping("/trust")
    public KnownHostsService.KnownHostPreview trust(
            @RequestBody TrustKnownHostRequest request) {
        return knownHostsService.trust(
                request.hostToken(), request.knownHostsLine(),
                request.expectedFingerprint());
    }

    @ExceptionHandler(KnownHostConflictException.class)
    public ResponseEntity<ApiError> conflict(KnownHostConflictException e) {
        return ResponseEntity.status(HttpStatus.CONFLICT)
                .body(new ApiError("HOST_KEY_CHANGED", e.getMessage()));
    }

    @ExceptionHandler(IllegalArgumentException.class)
    public ResponseEntity<ApiError> invalid(IllegalArgumentException e) {
        return ResponseEntity.badRequest()
                .body(new ApiError("INVALID_HOST_KEY", e.getMessage()));
    }

    public record KnownHostRequest(String hostToken, String knownHostsLine) {
    }

    public record TrustKnownHostRequest(
            String hostToken,
            String knownHostsLine,
            String expectedFingerprint
    ) {
    }

    public record ApiError(String code, String message) {
    }
}
