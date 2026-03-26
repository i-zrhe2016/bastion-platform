package com.example.bastion.server.service;

import com.example.bastion.server.config.RegistryProperties;
import com.example.bastion.server.dto.AgentRegistrationRequest;
import com.example.bastion.server.model.AgentNode;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;

import java.time.Instant;
import java.util.Comparator;
import java.util.List;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;

@Service
public class AgentRegistryService {

    private final ConcurrentHashMap<String, AgentNode> registry = new ConcurrentHashMap<>();
    private final RegistryProperties properties;

    public AgentRegistryService(RegistryProperties properties) {
        this.properties = properties;
    }

    public AgentNode register(AgentRegistrationRequest request) {
        Instant now = Instant.now();
        AgentNode agent = registry.computeIfAbsent(request.agentId(), ignored -> new AgentNode());
        synchronized (agent) {
            agent.setAgentId(request.agentId());
            agent.setHostname(request.hostname());
            agent.setIp(request.ip());
            agent.setSshPort(request.sshPort());
            agent.setTags(request.tags());
            if (agent.getRegisteredAt() == null) {
                agent.setRegisteredAt(now);
            }
            agent.setLastSeenAt(now);
        }
        return agent;
    }

    public boolean heartbeat(String agentId) {
        if (!StringUtils.hasText(agentId)) {
            return false;
        }
        AgentNode agent = registry.get(agentId);
        if (agent != null) {
            agent.setLastSeenAt(Instant.now());
            return true;
        }
        return false;
    }

    public Optional<AgentNode> findOnlineAgent(String agentId) {
        AgentNode node = registry.get(agentId);
        if (node == null) {
            return Optional.empty();
        }
        if (isExpired(node.getLastSeenAt(), Instant.now())) {
            return Optional.empty();
        }
        return Optional.of(node);
    }

    public List<AgentNode> listAgents() {
        Instant now = Instant.now();
        return registry.values().stream()
                .filter(agent -> !isExpired(agent.getLastSeenAt(), now))
                .sorted(Comparator.comparing(AgentNode::getAgentId))
                .toList();
    }

    public boolean isOnline(AgentNode agent) {
        return !isExpired(agent.getLastSeenAt(), Instant.now());
    }

    @org.springframework.scheduling.annotation.Scheduled(fixedDelayString = "${bastion.registry.cleanup-interval-ms:10000}")
    public void evictExpired() {
        Instant now = Instant.now();
        registry.entrySet().removeIf(entry -> isExpired(entry.getValue().getLastSeenAt(), now));
    }

    private boolean isExpired(Instant lastSeenAt, Instant now) {
        if (lastSeenAt == null) {
            return true;
        }
        return lastSeenAt.plusSeconds(properties.getTtlSeconds()).isBefore(now);
    }
}
