package com.lowenssh.agent.task;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

/** JSON 参数规范化，保证字段顺序不同但语义相同的 Tool Call 得到相同摘要。 */
public final class CanonicalJson {

    private CanonicalJson() {
    }

    public static String canonicalize(ObjectMapper mapper, String json) {
        if (json == null || json.isBlank()) {
            return "{}";
        }
        try {
            return mapper.writeValueAsString(sort(mapper, mapper.readTree(json)));
        } catch (JsonProcessingException e) {
            return json.strip();
        }
    }

    private static JsonNode sort(ObjectMapper mapper, JsonNode node) {
        if (node.isObject()) {
            ObjectNode sorted = mapper.createObjectNode();
            List<String> names = new ArrayList<>();
            node.fieldNames().forEachRemaining(names::add);
            names.stream().sorted(Comparator.naturalOrder())
                    .forEach(name -> sorted.set(name, sort(mapper, node.get(name))));
            return sorted;
        }
        if (node.isArray()) {
            ArrayNode sorted = mapper.createArrayNode();
            node.forEach(item -> sorted.add(sort(mapper, item)));
            return sorted;
        }
        return node;
    }
}
