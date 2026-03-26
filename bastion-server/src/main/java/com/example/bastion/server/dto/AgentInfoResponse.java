package com.example.bastion.server.dto;

import com.example.bastion.server.model.AgentNode;

import java.time.Instant;
import java.util.Map;

public record AgentInfoResponse(
        String agentId,
        String hostname,
        String ip,
        int sshPort,
        Map<String, String> tags,
        Instant registeredAt,
        Instant lastSeenAt,
        boolean online
) {
    public static AgentInfoResponse from(AgentNode node, boolean online) {
        return new AgentInfoResponse(
                node.getAgentId(),
                node.getHostname(),
                node.getIp(),
                node.getSshPort(),
                node.getTags(),
                node.getRegisteredAt(),
                node.getLastSeenAt(),
                online
        );
    }
}
