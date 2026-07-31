package com.lowenssh.agent;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

/** 将有副作用的工具参数统一转换为安全策略可分析的等价命令。 */
public final class ToolRiskCommand {

    private ToolRiskCommand() {
    }

    /** 返回 null 表示该工具只读。 */
    public static String from(String toolName, String argumentsJson, ObjectMapper objectMapper) {
        try {
            JsonNode node = objectMapper.readTree(argumentsJson);
            return switch (toolName) {
                case "execCommand" -> text(node, "command");
                case "deleteFile" -> "rm -- " + shellQuote(text(node, "path"));
                case "makeDir" -> "mkdir -- " + shellQuote(text(node, "path"));
                case "moveFile" -> "mv -- " + shellQuote(text(node, "from"))
                        + " " + shellQuote(text(node, "to"));
                default -> null;
            };
        } catch (Exception e) {
            // 参数损坏也必须失败关闭。
            return "bash -c 'invalid tool arguments'";
        }
    }

    private static String text(JsonNode node, String field) {
        JsonNode value = node.get(field);
        if (value == null || !value.isTextual() || value.asText().isBlank()) {
            throw new IllegalArgumentException("缺少工具参数: " + field);
        }
        return value.asText();
    }

    private static String shellQuote(String value) {
        return "'" + value.replace("'", "'\"'\"'") + "'";
    }
}
