package com.example.bastion.server.service;

import com.example.bastion.server.config.ConnectionProperties;
import com.example.bastion.server.model.ConnectionToken;
import org.springframework.stereotype.Service;

import java.time.Instant;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

@Service
public class ConnectionTokenService {

    private final ConcurrentHashMap<String, ConnectionToken> tokens = new ConcurrentHashMap<>();
    private final ConnectionProperties properties;

    public ConnectionTokenService(ConnectionProperties properties) {
        this.properties = properties;
    }

    public ConnectionToken issue(String agentId, String username) {
        Instant now = Instant.now();
        String token = UUID.randomUUID().toString().replace("-", "");
        ConnectionToken connectionToken = new ConnectionToken(
                token,
                agentId,
                username,
                now,
                now.plusSeconds(properties.getTokenTtlSeconds())
        );
        tokens.put(token, connectionToken);
        return connectionToken;
    }

    public Optional<ConnectionToken> validate(String tokenValue) {
        ConnectionToken token = tokens.get(tokenValue);
        if (token == null) {
            return Optional.empty();
        }
        if (token.isExpired(Instant.now())) {
            tokens.remove(tokenValue);
            return Optional.empty();
        }
        return Optional.of(token);
    }

    @org.springframework.scheduling.annotation.Scheduled(fixedDelayString = "${bastion.connection.cleanup-interval-ms:30000}")
    public void evictExpired() {
        Instant now = Instant.now();
        tokens.entrySet().removeIf(entry -> entry.getValue().isExpired(now));
    }
}
