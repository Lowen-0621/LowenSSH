package com.lowenssh.ssh;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Base64;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class KnownHostsServiceTest {

    @TempDir
    Path tempDir;

    @Test
    void 必须先核对相同指纹才能信任且重复导入幂等() throws Exception {
        Path file = tempDir.resolve("known_hosts");
        KnownHostsService service = new KnownHostsService(file.toString());
        String line = "example.com ssh-ed25519 "
                + Base64.getEncoder().encodeToString("public-key".getBytes());
        KnownHostsService.KnownHostPreview preview =
                service.preview("example.com", line);

        KnownHostsService.KnownHostPreview trusted =
                service.trust("example.com", line, preview.fingerprint());
        KnownHostsService.KnownHostPreview replay =
                service.trust("example.com", line, preview.fingerprint());

        assertThat(trusted.trusted()).isTrue();
        assertThat(replay).isEqualTo(trusted);
        assertThat(Files.readAllLines(file)).containsExactly(line);
    }

    @Test
    void 同主机Key变化时拒绝静默覆盖() {
        Path file = tempDir.resolve("changed_known_hosts");
        KnownHostsService service = new KnownHostsService(file.toString());
        String first = line("example.com", "key-one");
        var firstPreview = service.preview("example.com", first);
        service.trust("example.com", first, firstPreview.fingerprint());
        String changed = line("example.com", "key-two");
        var changedPreview = service.preview("example.com", changed);

        assertThatThrownBy(() ->
                service.trust("example.com", changed, changedPreview.fingerprint()))
                .isInstanceOf(KnownHostConflictException.class)
                .hasMessageContaining("不同 Host Key");
    }

    @Test
    void 主机不一致和错误确认指纹都拒绝() {
        KnownHostsService service =
                new KnownHostsService(tempDir.resolve("invalid_hosts").toString());
        String line = line("other.example", "key");

        assertThatThrownBy(() -> service.preview("expected.example", line))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("不一致");
        assertThatThrownBy(() ->
                service.trust("other.example", line, "SHA256:wrong"))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("指纹");
    }

    private String line(String host, String key) {
        return host + " ssh-ed25519 "
                + Base64.getEncoder().encodeToString(key.getBytes());
    }
}
