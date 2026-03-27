package com.example.bastion.server.dto;

import com.example.bastion.server.model.AgentNode;

import java.time.Instant;
import java.util.Map;

public record AgentRegistrationResponse(
        String agentId,
        String hostname,
        String ip,
        int sshPort,
        Map<String, String> tags,
        Instant registeredAt,
        Instant lastSeenAt,
        boolean online,
        String serverPublicKey
) {
    public static AgentRegistrationResponse from(AgentNode node, boolean online, String serverPublicKey) {
        return new AgentRegistrationResponse(
                node.getAgentId(),
                node.getHostname(),
                node.getIp(),
                node.getSshPort(),
                node.getTags(),
                node.getRegisteredAt(),
                node.getLastSeenAt(),
                online,
                serverPublicKey
        );
    }
}
