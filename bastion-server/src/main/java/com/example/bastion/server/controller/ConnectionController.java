package com.example.bastion.server.controller;

import com.example.bastion.server.config.ConnectionProperties;
import com.example.bastion.server.dto.OneClickConnectRequest;
import com.example.bastion.server.dto.OneClickConnectResponse;
import com.example.bastion.server.model.AgentNode;
import com.example.bastion.server.model.ConnectionToken;
import com.example.bastion.server.service.AgentRegistryService;
import com.example.bastion.server.service.ConnectionTokenService;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import java.util.HashMap;
import java.util.Locale;
import java.util.Map;

@RestController
@RequestMapping("/api/v1/connections")
public class ConnectionController {

    private final AgentRegistryService registryService;
    private final ConnectionTokenService tokenService;
    private final ConnectionProperties connectionProperties;

    public ConnectionController(AgentRegistryService registryService,
                                ConnectionTokenService tokenService,
                                ConnectionProperties connectionProperties) {
        this.registryService = registryService;
        this.tokenService = tokenService;
        this.connectionProperties = connectionProperties;
    }

    @PostMapping("/one-click")
    public OneClickConnectResponse oneClickConnect(@Valid @RequestBody OneClickConnectRequest request) {
        AgentNode target = registryService.findOnlineAgent(request.agentId())
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "agent not found or offline"));

        ConnectionToken token = tokenService.issue(target.getAgentId(), request.username());
        String command = buildCommand(request.username(), target, token.token());

        return new OneClickConnectResponse(
                target.getAgentId(),
                target.getIp(),
                target.getSshPort(),
                token.token(),
                token.expiresAt(),
                command
        );
    }

    @GetMapping("/token/{token}")
    public Map<String, Object> validateToken(@PathVariable("token") String token) {
        return tokenService.validate(token)
                .map(value -> {
                    Map<String, Object> result = new HashMap<>();
                    result.put("valid", true);
                    result.put("agentId", value.agentId());
                    result.put("username", value.username());
                    result.put("expiresAt", value.expiresAt());
                    return result;
                })
                .orElseGet(() -> {
                    Map<String, Object> result = new HashMap<>();
                    result.put("valid", false);
                    return result;
                });
    }

    private String buildCommand(String username, AgentNode target, String token) {
        // Token can be consumed by external auth logic in real deployments.
        String mode = connectionProperties.getDefaultMode() == null
                ? "mosh"
                : connectionProperties.getDefaultMode().trim().toLowerCase(Locale.ROOT);

        if ("ssh".equals(mode)) {
            return "BASTION_TOKEN=" + token + " ssh " + username + "@" + target.getIp() + " -p " + target.getSshPort();
        }
        if ("mosh".equals(mode)) {
            return "BASTION_TOKEN=" + token + " mosh " + username + "@" + target.getIp()
                    + " --ssh='ssh -p " + target.getSshPort() + "'";
        }
        throw new IllegalStateException("Unsupported bastion.connection.default-mode: " + mode);
    }
}
