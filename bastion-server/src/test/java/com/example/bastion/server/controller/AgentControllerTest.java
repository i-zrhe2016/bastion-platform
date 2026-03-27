package com.example.bastion.server.controller;

import com.example.bastion.server.config.ConnectionProperties;
import com.example.bastion.server.config.RegistryProperties;
import com.example.bastion.server.dto.AgentRegistrationRequest;
import com.example.bastion.server.service.AgentRegistryService;
import org.junit.jupiter.api.Test;

import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

class AgentControllerTest {

    @Test
    void shouldIncludeServerPublicKeyInRegisterResponse() {
        RegistryProperties registryProperties = new RegistryProperties();
        registryProperties.setTtlSeconds(60);
        AgentRegistryService registryService = new AgentRegistryService(registryProperties);

        ConnectionProperties connectionProperties = new ConnectionProperties();
        connectionProperties.setServerPublicKey("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestServerKey bastion-server");

        AgentController controller = new AgentController(registryService, connectionProperties);

        var response = controller.register(new AgentRegistrationRequest(
                "agent-1",
                "host-a",
                "10.0.0.1",
                22,
                Map.of("env", "prod")
        ));

        assertThat(response.serverPublicKey())
                .isEqualTo("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestServerKey bastion-server");
    }
}
