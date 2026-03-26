package com.example.bastion.server.service;

import com.example.bastion.server.config.ConnectionProperties;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class ConnectionTokenServiceTest {

    @Test
    void shouldIssueAndValidateToken() {
        ConnectionProperties properties = new ConnectionProperties();
        properties.setTokenTtlSeconds(30);
        ConnectionTokenService service = new ConnectionTokenService(properties);

        String token = service.issue("node-1", "root").token();

        assertThat(service.validate(token)).isPresent();
    }

    @Test
    void shouldExpireToken() throws Exception {
        ConnectionProperties properties = new ConnectionProperties();
        properties.setTokenTtlSeconds(1);
        ConnectionTokenService service = new ConnectionTokenService(properties);

        String token = service.issue("node-1", "root").token();
        Thread.sleep(1200L);

        assertThat(service.validate(token)).isEmpty();
    }
}
