package com.example.bastion.server.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;

public record OneClickConnectRequest(
        @NotBlank String agentId,
        @NotBlank @Pattern(regexp = "^[a-zA-Z_][a-zA-Z0-9_-]{0,31}$",
                message = "username contains invalid characters") String username
) {
}
