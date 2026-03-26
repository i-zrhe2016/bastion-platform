#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="bastion-agent"
INSTALL_DIR="/opt/bastion-agent"
BINARY_SOURCE="./target/release/bastion-agent"
SERVER_URL="http://127.0.0.1:8080"
SSH_PORT="22"
HEARTBEAT_MS="10000"
TAGS=()

usage() {
  cat <<USAGE
Usage:
  $0 [options]

Options:
  --bin <path>               Agent binary path (default: ${BINARY_SOURCE})
  --server-url <url>         Bastion server URL (default: ${SERVER_URL})
  --install-dir <dir>        Install directory (default: ${INSTALL_DIR})
  --service-name <name>      Systemd service name (default: ${SERVICE_NAME})
  --ssh-port <port>          SSH port reported by agent (default: ${SSH_PORT})
  --heartbeat-ms <ms>        Heartbeat interval (default: ${HEARTBEAT_MS})
  --tag <k=v>                Repeatable tag, e.g. --tag env=prod
  -h, --help                 Show help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bin) BINARY_SOURCE="$2"; shift 2 ;;
    --server-url) SERVER_URL="$2"; shift 2 ;;
    --install-dir) INSTALL_DIR="$2"; shift 2 ;;
    --service-name) SERVICE_NAME="$2"; shift 2 ;;
    --ssh-port) SSH_PORT="$2"; shift 2 ;;
    --heartbeat-ms) HEARTBEAT_MS="$2"; shift 2 ;;
    --tag) TAGS+=("$2"); shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

if [[ "$EUID" -ne 0 ]]; then
  echo "Please run as root (required for systemd installation)."
  exit 1
fi

if [[ ! -f "$BINARY_SOURCE" ]]; then
  echo "Binary not found: $BINARY_SOURCE"
  exit 1
fi

mkdir -p "$INSTALL_DIR"
cp "$BINARY_SOURCE" "$INSTALL_DIR/bastion-agent"
chmod +x "$INSTALL_DIR/bastion-agent"

TAG_LINES=""
for kv in "${TAGS[@]}"; do
  key="${kv%%=*}"
  value="${kv#*=}"
  TAG_LINES+="      ${key}: ${value}"$'\n'
done

cat > "$INSTALL_DIR/application.yml" <<YAML
spring:
  main:
    web-application-type: none

bastion:
  server:
    base-url: ${SERVER_URL}
  agent:
    ssh-port: ${SSH_PORT}
    id-file: ~/.bastion-agent/agent-id
    heartbeat-interval-ms: ${HEARTBEAT_MS}
    tags:
${TAG_LINES:-      role: jump}
YAML

cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<SERVICE
[Unit]
Description=Bastion Agent
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/bastion-agent --spring.config.location=${INSTALL_DIR}/application.yml
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable --now "${SERVICE_NAME}"
systemctl status "${SERVICE_NAME}" --no-pager

echo "Installed successfully."
