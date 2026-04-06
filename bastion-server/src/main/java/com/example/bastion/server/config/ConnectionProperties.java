package com.example.bastion.server.config;

import jakarta.annotation.PostConstruct;
import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "bastion.connection")
public class ConnectionProperties {

    private long tokenTtlSeconds = 120;
    private String defaultMode = "mosh";
    private String serverPublicKey;

    @PostConstruct
    public void validate() {
        if (serverPublicKey == null || serverPublicKey.isBlank()) {
            throw new IllegalStateException(
                "bastion.connection.server-public-key (env: BASTION_SERVER_PUBLIC_KEY) is required. " +
                "Set it to the server's SSH public key so agents can authorize incoming connections."
            );
        }
    }

    public long getTokenTtlSeconds() {
        return tokenTtlSeconds;
    }

    public void setTokenTtlSeconds(long tokenTtlSeconds) {
        this.tokenTtlSeconds = tokenTtlSeconds;
    }

    public String getDefaultMode() {
        return defaultMode;
    }

    public void setDefaultMode(String defaultMode) {
        this.defaultMode = defaultMode;
    }

    public String getServerPublicKey() {
        return serverPublicKey;
    }

    public void setServerPublicKey(String serverPublicKey) {
        this.serverPublicKey = serverPublicKey;
    }
}
