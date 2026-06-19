package com.lowenssh.agent;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.lowenssh.persistence.entity.HostEntity;
import com.lowenssh.persistence.mapper.HostMapper;
import com.lowenssh.ssh.SshClient;
import com.lowenssh.util.CryptoUtil;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/**
 * 主机簿接口 —— 管理常用服务器 + 进入主机时建立连接。
 *
 *  - GET    /api/hosts            列出主机（不回传密码）
 *  - POST   /api/hosts            新增主机（密码 AES 加密落库）
 *  - DELETE /api/hosts/{id}       删除主机
 *  - POST   /api/hosts/{id}/connect  进入主机：解密密码 → 建/复用常驻连接 → 回 sessionId
 *
 * 密码只在 connect 时解密用一次去连 SSH，不回传前端、不落明文。
 */
@RestController
public class HostController {

    private final HostMapper hostMapper;
    private final SessionManager sessionManager;
    private final CryptoUtil crypto;

    public HostController(HostMapper hostMapper, SessionManager sessionManager, CryptoUtil crypto) {
        this.hostMapper = hostMapper;
        this.sessionManager = sessionManager;
        this.crypto = crypto;
    }

    /** 列主机，按更新时间倒序。hasPassword 标记是否存了密码（迁移出的老主机没有，前端提示补填）。 */
    @GetMapping("/api/hosts")
    public List<HostDto.HostItem> list() {
        LambdaQueryWrapper<HostEntity> wrapper = new LambdaQueryWrapper<HostEntity>()
                .orderByDesc(HostEntity::getUpdatedAt)
                .orderByDesc(HostEntity::getId);
        return hostMapper.selectList(wrapper).stream()
                .map(h -> new HostDto.HostItem(
                        h.getId(), h.getAlias(), h.getSshHost(), h.getSshPort(), h.getSshUser(),
                        h.getPasswordEnc() != null && !h.getPasswordEnc().isBlank()))
                .toList();
    }

    /** 新增主机：密码加密存。返回新主机 id。 */
    @PostMapping("/api/hosts")
    public HostDto.HostItem create(@RequestBody HostDto.CreateRequest req) {
        HostEntity h = new HostEntity();
        h.setAlias(req.alias());
        h.setSshHost(req.host());
        h.setSshPort(req.port() == null || req.port() == 0 ? 22 : req.port());
        h.setSshUser(req.user());
        h.setPasswordEnc(crypto.encrypt(req.password()));  // 明文不落库
        hostMapper.insert(h);
        return new HostDto.HostItem(h.getId(), h.getAlias(), h.getSshHost(), h.getSshPort(),
                h.getSshUser(), h.getPasswordEnc() != null);
    }

    /** 删除主机（历史会话仍在库里，只是从主机簿移除入口） */
    @DeleteMapping("/api/hosts/{id}")
    public ResponseEntity<Void> delete(@PathVariable("id") Long id) {
        hostMapper.deleteById(id);
        return ResponseEntity.noContent().build();
    }

    /**
     * 进入主机：解密密码连一次 SSH（或复用该主机已活会话），返回 sessionId 给前端续聊。
     * 没存密码（迁移出的老主机）则要求前端带 password 进来补连。
     */
    @PostMapping("/api/hosts/{id}/connect")
    public ResponseEntity<?> connect(@PathVariable("id") Long id,
                                     @RequestBody(required = false) HostDto.ConnectRequest req) {
        HostEntity h = hostMapper.selectById(id);
        if (h == null) {
            return ResponseEntity.status(404).body(new HostDto.ConnectResult(null, "主机不存在"));
        }
        // 优先用库里存的密码；没存则用前端补填的
        String password;
        try {
            String stored = crypto.decrypt(h.getPasswordEnc());
            password = (stored != null && !stored.isBlank())
                    ? stored
                    : (req == null ? null : req.password());
        } catch (Exception e) {
            return ResponseEntity.status(500).body(new HostDto.ConnectResult(null, "密码解密失败，请重新保存主机密码"));
        }
        if (password == null || password.isBlank()) {
            return ResponseEntity.status(400).body(new HostDto.ConnectResult(null, "该主机未保存密码，请补填密码后连接"));
        }

        try {
            SessionManager.LiveSession live = sessionManager.openForHost(
                    id, h.getSshHost(), h.getSshPort() == null ? 22 : h.getSshPort(), h.getSshUser(), password);
            return ResponseEntity.ok(new HostDto.ConnectResult(live.sessionId(), null));
        } catch (Exception e) {
            return ResponseEntity.status(502).body(new HostDto.ConnectResult(null, "SSH 连接失败: " + e.getMessage()));
        }
    }
}
