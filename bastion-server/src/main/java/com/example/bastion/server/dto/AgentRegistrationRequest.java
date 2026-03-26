package com.example.bastion.server.dto;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

import java.util.Map;

public record AgentRegistrationRequest(
        @NotBlank String agentId,
        @NotBlank String hostname,
        @NotBlank String ip,
        @NotNull @Min(1) @Max(65535) Integer sshPort,
        Map<String, String> tags
) {
}
