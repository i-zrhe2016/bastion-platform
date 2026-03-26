use anyhow::{bail, Context, Result};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::env;
use std::fs;
use std::net::IpAddr;
use std::path::{Path, PathBuf};
use std::time::Duration;
use tracing::{debug, info, warn};
use tracing_subscriber::EnvFilter;
use uuid::Uuid;

#[derive(Debug, Deserialize, Default)]
struct AppConfig {
    #[serde(default)]
    bastion: BastionConfig,
}

#[derive(Debug, Deserialize, Default)]
struct BastionConfig {
    #[serde(default)]
    server: ServerConfig,
    #[serde(default)]
    agent: AgentConfig,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "kebab-case")]
struct ServerConfig {
    #[serde(default = "default_server_base_url")]
    base_url: String,
}

impl Default for ServerConfig {
    fn default() -> Self {
        Self {
            base_url: default_server_base_url(),
        }
    }
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "kebab-case")]
struct AgentConfig {
    #[serde(default = "default_ssh_port")]
    ssh_port: u16,
    #[serde(default = "default_id_file")]
    id_file: String,
    #[serde(default = "default_heartbeat_interval_ms")]
    heartbeat_interval_ms: u64,
    #[serde(default)]
    tags: HashMap<String, String>,
}

impl Default for AgentConfig {
    fn default() -> Self {
        Self {
            ssh_port: default_ssh_port(),
            id_file: default_id_file(),
            heartbeat_interval_ms: default_heartbeat_interval_ms(),
            tags: HashMap::new(),
        }
    }
}

#[derive(Debug)]
struct RegistrationClient {
    client: reqwest::Client,
    base_url: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct AgentRegistrationRequest<'a> {
    agent_id: &'a str,
    hostname: &'a str,
    ip: &'a str,
    ssh_port: u16,
    tags: &'a HashMap<String, String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct AgentHeartbeatRequest<'a> {
    agent_id: &'a str,
}

#[tokio::main]
async fn main() -> Result<()> {
    init_tracing();

    let config_path = parse_config_path(env::args().skip(1));
    let config = load_config(&config_path)?;
    let agent_id = get_or_create_agent_id(&config.bastion.agent.id_file)?;
    let interval = Duration::from_millis(config.bastion.agent.heartbeat_interval_ms.max(1000));
    let client = RegistrationClient::new(config.bastion.server.base_url.clone())?;

    info!(
        "starting bastion-agent with config={}, server={}",
        config_path.display(),
        trim_trailing_slash(&config.bastion.server.base_url)
    );

    let mut registered = register_now(&client, &config.bastion.agent, &agent_id).await;

    loop {
        tokio::select! {
            _ = tokio::signal::ctrl_c() => {
                info!("received shutdown signal, exiting");
                break;
            }
            _ = tokio::time::sleep(interval) => {
                if !registered {
                    registered = register_now(&client, &config.bastion.agent, &agent_id).await;
                    continue;
                }

                match client.heartbeat(&agent_id).await {
                    Ok(()) => debug!("heartbeat ok: {}", agent_id),
                    Err(err) => {
                        registered = false;
                        warn!("heartbeat failed, will re-register next cycle: {err}");
                    }
                }
            }
        }
    }

    Ok(())
}

async fn register_now(client: &RegistrationClient, agent: &AgentConfig, agent_id: &str) -> bool {
    let host = hostname();
    let ip = primary_ipv4();
    let request = AgentRegistrationRequest {
        agent_id,
        hostname: &host,
        ip: &ip,
        ssh_port: agent.ssh_port,
        tags: &agent.tags,
    };

    match client.register(&request).await {
        Ok(()) => {
            info!(
                "agent registered: id={}, host={}, ip={}",
                agent_id, host, ip
            );
            true
        }
        Err(err) => {
            warn!("agent register failed: {err}");
            false
        }
    }
}

impl RegistrationClient {
    fn new(base_url: String) -> Result<Self> {
        let client = reqwest::Client::builder()
            .timeout(Duration::from_secs(5))
            .build()
            .context("failed to build HTTP client")?;

        Ok(Self {
            client,
            base_url: trim_trailing_slash(&base_url),
        })
    }

    async fn register(&self, request: &AgentRegistrationRequest<'_>) -> Result<()> {
        self.post_json("/api/v1/agents/register", request).await
    }

    async fn heartbeat(&self, agent_id: &str) -> Result<()> {
        let request = AgentHeartbeatRequest { agent_id };
        self.post_json("/api/v1/agents/heartbeat", &request).await
    }

    async fn post_json<T: Serialize + ?Sized>(&self, path: &str, payload: &T) -> Result<()> {
        let url = format!("{}{}", self.base_url, path);
        let response = self
            .client
            .post(&url)
            .json(payload)
            .send()
            .await
            .with_context(|| format!("request failed: {url}"))?;

        if response.status().is_success() {
            return Ok(());
        }

        let status = response.status();
        let body = response.text().await.unwrap_or_default();
        bail!("request failed: status={status}, body={body}");
    }
}

fn load_config(path: &Path) -> Result<AppConfig> {
    let content = fs::read_to_string(path)
        .with_context(|| format!("failed to read config file: {}", path.display()))?;
    let config: AppConfig = serde_yaml::from_str(&content)
        .with_context(|| format!("failed to parse config yaml: {}", path.display()))?;
    Ok(config)
}

fn parse_config_path<I>(args: I) -> PathBuf
where
    I: IntoIterator<Item = String>,
{
    let mut args = args.into_iter();
    while let Some(arg) = args.next() {
        if let Some(value) = arg.strip_prefix("--spring.config.location=") {
            return PathBuf::from(value);
        }
        if arg == "--spring.config.location" {
            if let Some(value) = args.next() {
                return PathBuf::from(value);
            }
        }
        if let Some(value) = arg.strip_prefix("--config=") {
            return PathBuf::from(value);
        }
        if arg == "--config" {
            if let Some(value) = args.next() {
                return PathBuf::from(value);
            }
        }
    }
    PathBuf::from("application.yml")
}

fn get_or_create_agent_id(configured_path: &str) -> Result<String> {
    let id_path = resolve_id_path(configured_path);

    if id_path.exists() {
        let existing = fs::read_to_string(&id_path)
            .with_context(|| format!("failed to read agent id file: {}", id_path.display()))?;
        let existing = existing.trim();
        if !existing.is_empty() {
            return Ok(existing.to_string());
        }
    }

    if let Some(parent) = id_path.parent() {
        fs::create_dir_all(parent).with_context(|| {
            format!(
                "failed to create parent directory for agent id file: {}",
                parent.display()
            )
        })?;
    }

    let new_id = Uuid::new_v4().to_string();
    fs::write(&id_path, &new_id)
        .with_context(|| format!("failed to persist agent id at {}", id_path.display()))?;
    Ok(new_id)
}

fn resolve_id_path(configured_path: &str) -> PathBuf {
    if let Some(rest) = configured_path.strip_prefix("~/") {
        if let Ok(home) = env::var("HOME") {
            return Path::new(&home).join(rest);
        }
    }
    PathBuf::from(configured_path)
}

fn hostname() -> String {
    hostname::get()
        .ok()
        .and_then(|value| value.into_string().ok())
        .filter(|value| !value.trim().is_empty())
        .or_else(|| {
            env::var("HOSTNAME")
                .ok()
                .filter(|value| !value.trim().is_empty())
        })
        .unwrap_or_else(|| "unknown-host".to_string())
}

fn primary_ipv4() -> String {
    if let Ok(interfaces) = if_addrs::get_if_addrs() {
        for iface in interfaces {
            if iface.is_loopback() {
                continue;
            }
            if let IpAddr::V4(ipv4) = iface.ip() {
                return ipv4.to_string();
            }
        }
    }
    "127.0.0.1".to_string()
}

fn trim_trailing_slash(url: &str) -> String {
    url.trim_end_matches('/').to_string()
}

fn init_tracing() {
    let filter = EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| EnvFilter::new("bastion_agent=info,info"));
    tracing_subscriber::fmt()
        .with_env_filter(filter)
        .with_target(false)
        .compact()
        .init();
}

fn default_server_base_url() -> String {
    "http://localhost:8080".to_string()
}

fn default_ssh_port() -> u16 {
    22
}

fn default_id_file() -> String {
    "~/.bastion-agent/agent-id".to_string()
}

fn default_heartbeat_interval_ms() -> u64 {
    10_000
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_config_path_supports_spring_style_arg() {
        let path = parse_config_path(vec![
            "--spring.config.location=/etc/bastion-agent/application.yml".to_string(),
        ]);
        assert_eq!(path, PathBuf::from("/etc/bastion-agent/application.yml"));
    }

    #[test]
    fn parse_config_path_defaults_to_application_yml() {
        let path = parse_config_path(Vec::<String>::new());
        assert_eq!(path, PathBuf::from("application.yml"));
    }

    #[test]
    fn trim_trailing_slash_removes_tailing_slashes() {
        assert_eq!(
            trim_trailing_slash("http://127.0.0.1:8080///"),
            "http://127.0.0.1:8080"
        );
    }

    #[test]
    fn resolve_id_path_expands_tilde_path() {
        if let Ok(home) = env::var("HOME") {
            let path = resolve_id_path("~/my-agent/id");
            assert_eq!(path, Path::new(&home).join("my-agent/id"));
        }
    }
}
