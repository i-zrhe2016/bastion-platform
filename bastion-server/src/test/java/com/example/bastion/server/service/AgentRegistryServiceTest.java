package com.example.bastion.server.service;

import com.example.bastion.server.config.RegistryProperties;
import com.example.bastion.server.dto.AgentRegistrationRequest;
import org.junit.jupiter.api.Test;

import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

class AgentRegistryServiceTest {

    @Test
    void shouldRegisterAndListAgent() {
        RegistryProperties properties = new RegistryProperties();
        properties.setTtlSeconds(60);
        AgentRegistryService service = new AgentRegistryService(properties);

        service.register(new AgentRegistrationRequest("node-1", "host-a", "10.0.0.1", 22, Map.of("env", "prod")));

        assertThat(service.listAgents()).hasSize(1);
        assertThat(service.listAgents().get(0).getAgentId()).isEqualTo("node-1");
    }

    @Test
    void shouldMarkAgentOfflineAfterTtl() throws Exception {
        RegistryProperties properties = new RegistryProperties();
        properties.setTtlSeconds(1);
        AgentRegistryService service = new AgentRegistryService(properties);

        service.register(new AgentRegistrationRequest("node-2", "host-b", "10.0.0.2", 22, Map.of()));
        Thread.sleep(1200L);

        assertThat(service.findOnlineAgent("node-2")).isEmpty();
    }
}
