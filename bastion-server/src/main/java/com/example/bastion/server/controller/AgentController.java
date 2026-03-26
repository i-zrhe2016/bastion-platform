package com.example.bastion.server.controller;

import com.example.bastion.server.dto.AgentHeartbeatRequest;
import com.example.bastion.server.dto.AgentInfoResponse;
import com.example.bastion.server.dto.AgentRegistrationRequest;
import com.example.bastion.server.model.AgentNode;
import com.example.bastion.server.service.AgentRegistryService;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import java.util.List;

@RestController
@RequestMapping("/api/v1/agents")
public class AgentController {

    private final AgentRegistryService registryService;

    public AgentController(AgentRegistryService registryService) {
        this.registryService = registryService;
    }

    @PostMapping("/register")
    public AgentInfoResponse register(@Valid @RequestBody AgentRegistrationRequest request) {
        AgentNode node = registryService.register(request);
        return AgentInfoResponse.from(node, true);
    }

    @PostMapping("/heartbeat")
    public ResponseEntity<Void> heartbeat(@Valid @RequestBody AgentHeartbeatRequest request) {
        boolean exists = registryService.heartbeat(request.agentId());
        if (!exists) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "agent not registered");
        }
        return ResponseEntity.noContent().build();
    }

    @GetMapping
    public List<AgentInfoResponse> listAgents() {
        return registryService.listAgents().stream()
                .map(node -> AgentInfoResponse.from(node, registryService.isOnline(node)))
                .toList();
    }

    @GetMapping("/{agentId}")
    public AgentInfoResponse get(@PathVariable("agentId") String agentId) {
        AgentNode node = registryService.findOnlineAgent(agentId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "agent not found or offline"));
        return AgentInfoResponse.from(node, true);
    }
}
