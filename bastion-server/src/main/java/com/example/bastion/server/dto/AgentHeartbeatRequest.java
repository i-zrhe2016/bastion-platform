package com.example.bastion.server.dto;

import jakarta.validation.constraints.NotBlank;

public record AgentHeartbeatRequest(@NotBlank String agentId) {
}
