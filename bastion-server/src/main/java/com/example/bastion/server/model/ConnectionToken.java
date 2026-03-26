package com.example.bastion.server.model;

import java.time.Instant;

public record ConnectionToken(String token,
                              String agentId,
                              String username,
                              Instant createdAt,
                              Instant expiresAt) {

    public boolean isExpired(Instant now) {
        return expiresAt.isBefore(now);
    }
}
