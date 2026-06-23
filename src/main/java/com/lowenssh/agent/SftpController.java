package com.lowenssh.agent;

import com.lowenssh.ssh.RemoteFile;
import org.springframework.core.io.InputStreamResource;
import org.springframework.http.ContentDisposition;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Map;

/**
 * SFTP 文件管理接口（给人用）—— 复用主机的常驻 SSH 连接开 sftp 通道，不重连。
 *
 *  - GET    /api/sftp/{hostId}/list?path=/xxx     列目录
 *  - POST   /api/sftp/{hostId}/upload             上传（multipart：file + path）
 *  - GET    /api/sftp/{hostId}/download?path=/xxx 下载（流式）
 *  - DELETE /api/sftp/{hostId}/file?path=/xxx     删除文件
 *  - POST   /api/sftp/{hostId}/mkdir              建目录（body: {path}）
 *
 * 关键：SFTP / Agent 命令 / 监控共用同一条 JSch Session，必须用 LiveSession.lock()
 * 串行化，否则 channel 会串数据。每个接口都在 lock 内操作。
 */
@RestController
public class SftpController {

    private final SessionManager sessionManager;

    public SftpController(SessionManager sessionManager) {
        this.sessionManager = sessionManager;
    }

    /** 取该主机的常驻连接，没连上返回 null */
    private SessionManager.LiveSession live(Long hostId) {
        return sessionManager.getByHost(hostId);
    }

    /** 列目录 */
    @GetMapping("/api/sftp/{hostId}/list")
    public ResponseEntity<?> list(@PathVariable("hostId") Long hostId,
                                  @RequestParam(value = "path", defaultValue = "/") String path) {
        SessionManager.LiveSession ls = live(hostId);
        if (ls == null) return notConnected();
        ls.lock().lock();
        try {
            List<RemoteFile> files = ls.ssh().listDir(path);
            return ResponseEntity.ok(Map.of("path", path, "files", files));
        } catch (Exception e) {
            return ResponseEntity.status(500).body(Map.of("error", "列目录失败: " + e.getMessage()));
        } finally {
            ls.lock().unlock();
        }
    }

    /** 上传文件到指定目录 */
    @PostMapping("/api/sftp/{hostId}/upload")
    public ResponseEntity<?> upload(@PathVariable("hostId") Long hostId,
                                    @RequestParam("file") MultipartFile file,
                                    @RequestParam("path") String dir) {
        SessionManager.LiveSession ls = live(hostId);
        if (ls == null) return notConnected();
        String remote = (dir.endsWith("/") ? dir : dir + "/") + file.getOriginalFilename();
        ls.lock().lock();
        try {
            ls.ssh().upload(file.getInputStream(), remote);
            return ResponseEntity.ok(Map.of("path", remote));
        } catch (Exception e) {
            return ResponseEntity.status(500).body(Map.of("error", "上传失败: " + e.getMessage()));
        } finally {
            ls.lock().unlock();
        }
    }

    /** 下载文件。先在 lock 内读进内存再返回，避免流式期间长期占着 lock。 */
    @GetMapping("/api/sftp/{hostId}/download")
    public ResponseEntity<?> download(@PathVariable("hostId") Long hostId,
                                      @RequestParam("path") String path) {
        SessionManager.LiveSession ls = live(hostId);
        if (ls == null) return notConnected();
        ByteArrayOutputStream buf = new ByteArrayOutputStream();
        ls.lock().lock();
        try {
            ls.ssh().download(path, buf);
        } catch (Exception e) {
            return ResponseEntity.status(500).body(Map.of("error", "下载失败: " + e.getMessage()));
        } finally {
            ls.lock().unlock();
        }
        String name = path.substring(path.lastIndexOf('/') + 1);
        byte[] data = buf.toByteArray();
        HttpHeaders headers = new HttpHeaders();
        headers.setContentDisposition(ContentDisposition.attachment().filename(name).build());
        return ResponseEntity.ok()
                .headers(headers)
                .contentType(MediaType.APPLICATION_OCTET_STREAM)
                .contentLength(data.length)
                .body(new InputStreamResource(new ByteArrayInputStream(data)));
    }

    /** 删除文件 */
    @DeleteMapping("/api/sftp/{hostId}/file")
    public ResponseEntity<?> delete(@PathVariable("hostId") Long hostId,
                                    @RequestParam("path") String path) {
        SessionManager.LiveSession ls = live(hostId);
        if (ls == null) return notConnected();
        ls.lock().lock();
        try {
            ls.ssh().deleteFile(path);
            return ResponseEntity.noContent().build();
        } catch (Exception e) {
            return ResponseEntity.status(500).body(Map.of("error", "删除失败: " + e.getMessage()));
        } finally {
            ls.lock().unlock();
        }
    }

    /** 新建目录 */
    @PostMapping("/api/sftp/{hostId}/mkdir")
    public ResponseEntity<?> mkdir(@PathVariable("hostId") Long hostId,
                                   @RequestBody Map<String, String> body) {
        String path = body.get("path");
        if (path == null || path.isBlank()) {
            return ResponseEntity.status(400).body(Map.of("error", "path 不能为空"));
        }
        SessionManager.LiveSession ls = live(hostId);
        if (ls == null) return notConnected();
        ls.lock().lock();
        try {
            ls.ssh().mkdir(path);
            return ResponseEntity.ok(Map.of("path", path));
        } catch (Exception e) {
            return ResponseEntity.status(500).body(Map.of("error", "建目录失败: " + e.getMessage()));
        } finally {
            ls.lock().unlock();
        }
    }

    private ResponseEntity<?> notConnected() {
        return ResponseEntity.status(409).body(Map.of("error", "该主机未连接，请先从主机簿进入"));
    }
}
