package com.lowenssh.agent.guard;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

/** 30 个固定场景的可重复离线评测；不连接真实服务器，不调用计费模型。 */
class AgentSecurityEvaluationTest {

    private final ObjectMapper objectMapper = new ObjectMapper();
    private final CommandGuard guard = new CommandGuard();

    @Test
    void 固定评测集生成机器可读报告且危险误放行为零() throws Exception {
        List<Scenario> scenarios;
        try (var input = getClass().getResourceAsStream(
                "/agent-evaluation-scenarios.json")) {
            scenarios = objectMapper.readValue(input, new TypeReference<>() {
            });
        }
        int correct = 0;
        int dangerousReleased = 0;
        int safeBlocked = 0;
        Map<String, Integer> decisionCounts = new LinkedHashMap<>();
        java.util.ArrayList<Map<String, Object>> rows = new java.util.ArrayList<>();

        for (Scenario scenario : scenarios) {
            CommandGuard.Decision actual = guard.evaluate(scenario.command()).decision();
            boolean matched = actual.name().equals(scenario.expected());
            if (matched) {
                correct++;
            }
            if ("DENY".equals(scenario.expected()) && actual != CommandGuard.Decision.DENY) {
                dangerousReleased++;
            }
            if ("ALLOW".equals(scenario.expected()) && actual != CommandGuard.Decision.ALLOW) {
                safeBlocked++;
            }
            decisionCounts.merge(actual.name(), 1, Integer::sum);
            rows.add(Map.of(
                    "id", scenario.id(),
                    "category", scenario.category(),
                    "expected", scenario.expected(),
                    "actual", actual.name(),
                    "passed", matched));
        }

        Map<String, Object> report = new LinkedHashMap<>();
        report.put("generatedAt", Instant.now().toString());
        report.put("scenarioCount", scenarios.size());
        report.put("correct", correct);
        report.put("accuracy", correct * 1.0 / scenarios.size());
        report.put("dangerousReleaseCount", dangerousReleased);
        report.put("safeFalseBlockCount", safeBlocked);
        report.put("decisionCounts", decisionCounts);
        report.put("results", rows);
        Path output = Path.of("target", "agent-evaluation-report.json");
        Files.createDirectories(output.getParent());
        objectMapper.writerWithDefaultPrettyPrinter().writeValue(output.toFile(), report);

        assertThat(scenarios).hasSize(30);
        assertThat(correct).isEqualTo(30);
        assertThat(dangerousReleased).isZero();
        assertThat(safeBlocked).isZero();
    }

    record Scenario(String id, String category, String command, String expected) {
    }
}
