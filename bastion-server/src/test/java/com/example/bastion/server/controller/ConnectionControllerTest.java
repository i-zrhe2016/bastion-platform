package com.example.bastion.server.controller;

import com.example.bastion.server.config.ConnectionProperties;
import com.example.bastion.server.dto.OneClickConnectRequest;
import com.example.bastion.server.dto.OneClickConnectResponse;
import com.example.bastion.server.model.AgentNode;
import com.example.bastion.server.model.ConnectionToken;
import com.example.bastion.server.service.AgentRegistryService;
import com.example.bastion.server.service.ConnectionTokenService;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class ConnectionControllerTest {

    @Test
    void shouldUseMoshCommandByDefault() {
        AgentRegistryService registryService = mock(AgentRegistryService.class);
        ConnectionTokenService tokenService = mock(ConnectionTokenService.class);
        ConnectionController controller = new ConnectionController(
                registryService,
                tokenService,
                new ConnectionProperties()
        );

        AgentNode agent = new AgentNode();
        agent.setAgentId("agent-1");
        agent.setIp("10.0.0.2");
        agent.setSshPort(2202);

        when(registryService.findOnlineAgent("agent-1")).thenReturn(Optional.of(agent));
        when(tokenService.issue("agent-1", "demo")).thenReturn(
                new ConnectionToken(
                        "tok-123",
                        "agent-1",
                        "demo",
                        Instant.parse("2099-01-01T00:00:00Z"),
                        Instant.parse("2099-01-01T00:02:00Z")
                )
        );

        OneClickConnectResponse response = controller.oneClickConnect(new OneClickConnectRequest("agent-1", "demo"));

        assertThat(response.connectCommand())
                .isEqualTo("BASTION_TOKEN=tok-123 mosh demo@10.0.0.2 --ssh='ssh -p 2202'");
    }

    @Test
    void shouldAllowSshModeWhenConfigured() {
        AgentRegistryService registryService = mock(AgentRegistryService.class);
        ConnectionTokenService tokenService = mock(ConnectionTokenService.class);
        ConnectionProperties connectionProperties = new ConnectionProperties();
        connectionProperties.setDefaultMode("ssh");

        ConnectionController controller = new ConnectionController(registryService, tokenService, connectionProperties);

        AgentNode agent = new AgentNode();
        agent.setAgentId("agent-1");
        agent.setIp("10.0.0.2");
        agent.setSshPort(2202);

        when(registryService.findOnlineAgent("agent-1")).thenReturn(Optional.of(agent));
        when(tokenService.issue("agent-1", "demo")).thenReturn(
                new ConnectionToken(
                        "tok-123",
                        "agent-1",
                        "demo",
                        Instant.parse("2099-01-01T00:00:00Z"),
                        Instant.parse("2099-01-01T00:02:00Z")
                )
        );

        OneClickConnectResponse response = controller.oneClickConnect(new OneClickConnectRequest("agent-1", "demo"));

        assertThat(response.connectCommand())
                .isEqualTo("BASTION_TOKEN=tok-123 ssh demo@10.0.0.2 -p 2202");
    }
}
