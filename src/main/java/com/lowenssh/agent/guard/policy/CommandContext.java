package com.lowenssh.agent.guard.policy;

import java.util.Map;

/** 为后续用户/主机级策略保留稳定上下文，不把规则绑死在纯命令字符串上。 */
public record CommandContext(
        String command,
        Long hostId,
        String username,
        Map<String, Object> attributes
) {
    public CommandContext {
        attributes = attributes == null ? Map.of() : Map.copyOf(attributes);
    }

    public static CommandContext of(String command) {
        return new CommandContext(command, null, null, Map.of());
    }
}
