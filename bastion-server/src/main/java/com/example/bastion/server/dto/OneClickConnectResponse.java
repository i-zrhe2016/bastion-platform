package com.example.bastion.server.dto;

import java.time.Instant;

public record OneClickConnectResponse(
        String agentId,
        String host,
        int sshPort,
        String token,
        Instant expiresAt,
        String connectCommand
) {
}
