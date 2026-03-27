#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="bastion-agent"
INSTALL_DIR="/opt/bastion-agent"
BINARY_SOURCE="./target/release/bastion-agent"
DOWNLOAD_URL=""
DOWNLOAD_SHA256=""
SERVER_URL="http://82.156.46.158:8080"
SSH_PORT="22"
HEARTBEAT_MS="10000"
TAGS=()
DOWNLOADED_BINARY=""

usage() {
  cat <<USAGE
Usage:
  $0 [options]

Options:
  --bin <path>               Agent binary path (default: ${BINARY_SOURCE})
  --download-url <url>       Download prebuilt binary if --bin is missing
                             (supports {arch} placeholder, e.g. .../bastion-agent-linux-{arch})
  --download-sha256 <hex>    Optional SHA-256 checksum for downloaded binary
  --server-url <url>         Bastion server URL (default: ${SERVER_URL})
  --install-dir <dir>        Install directory (default: ${INSTALL_DIR})
  --service-name <name>      Systemd service name (default: ${SERVICE_NAME})
  --ssh-port <port>          SSH port reported by agent (default: ${SSH_PORT})
  --heartbeat-ms <ms>        Heartbeat interval (default: ${HEARTBEAT_MS})
  --tag <k=v>                Repeatable tag, e.g. --tag env=prod
  -h, --help                 Show help
USAGE
}

cleanup() {
  if [[ -n "${DOWNLOADED_BINARY}" && -f "${DOWNLOADED_BINARY}" ]]; then
    rm -f "${DOWNLOADED_BINARY}"
  fi
}

detect_arch() {
  local machine
  machine="$(uname -m)"
  case "${machine}" in
    x86_64|amd64) echo "amd64" ;;
    *)
      echo "Only amd64 is supported for automatic download. Detected: ${machine}" >&2
      return 1
      ;;
  esac
}

download_file() {
  local url="$1"
  local output="$2"

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "${url}" -o "${output}"
    return 0
  fi

  if command -v wget >/dev/null 2>&1; then
    wget -qO "${output}" "${url}"
    return 0
  fi

  echo "Neither curl nor wget is installed. Install one of them or provide --bin." >&2
  return 1
}

verify_sha256() {
  local file="$1"
  local expected="$2"
  local actual

  if [[ -z "${expected}" ]]; then
    return 0
  fi

  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "${file}" | awk '{print $1}')"
  elif command -v shasum >/dev/null 2>&1; then
    actual="$(shasum -a 256 "${file}" | awk '{print $1}')"
  else
    echo "Checksum tool missing: need sha256sum or shasum to use --download-sha256." >&2
    return 1
  fi

  if [[ "${actual}" != "${expected}" ]]; then
    echo "Checksum mismatch for downloaded binary." >&2
    echo "Expected: ${expected}" >&2
    echo "Actual:   ${actual}" >&2
    return 1
  fi
}

resolve_binary_source() {
  if [[ -f "${BINARY_SOURCE}" ]]; then
    return 0
  fi

  if [[ -z "${DOWNLOAD_URL}" ]]; then
    echo "Binary not found: ${BINARY_SOURCE}" >&2
    echo "Provide --download-url to install without local build dependencies." >&2
    return 1
  fi

  local arch
  arch="$(detect_arch)"

  local resolved_download_url
  resolved_download_url="${DOWNLOAD_URL//\{arch\}/${arch}}"

  DOWNLOADED_BINARY="$(mktemp -t bastion-agent.XXXXXX)"
  echo "Local binary not found, downloading prebuilt agent from: ${resolved_download_url}"
  download_file "${resolved_download_url}" "${DOWNLOADED_BINARY}"
  verify_sha256 "${DOWNLOADED_BINARY}" "${DOWNLOAD_SHA256}"
  chmod +x "${DOWNLOADED_BINARY}"

  BINARY_SOURCE="${DOWNLOADED_BINARY}"
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --bin) BINARY_SOURCE="$2"; shift 2 ;;
      --download-url) DOWNLOAD_URL="$2"; shift 2 ;;
      --download-sha256) DOWNLOAD_SHA256="$2"; shift 2 ;;
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
    echo "Please run as root (required for installation)."
    exit 1
  fi

  resolve_binary_source

  mkdir -p "${INSTALL_DIR}"
  cp "${BINARY_SOURCE}" "${INSTALL_DIR}/bastion-agent"
  chmod +x "${INSTALL_DIR}/bastion-agent"

  TAG_LINES=""
  for kv in "${TAGS[@]}"; do
    key="${kv%%=*}"
    value="${kv#*=}"
    TAG_LINES+="      ${key}: ${value}"$'\n'
  done

  cat > "${INSTALL_DIR}/application.yml" <<YAML
spring:
  main:
    web-application-type: none

bastion:
  server:
    base-url: ${SERVER_URL}
  agent:
    ssh-port: ${SSH_PORT}
    id-file: ~/.bastion-agent/agent-id
    ssh-authorized-keys-file: ~/.ssh/authorized_keys
    heartbeat-interval-ms: ${HEARTBEAT_MS}
    tags:
${TAG_LINES:-      role: jump}
YAML

  if [[ "${BASTION_AGENT_INSTALL_SKIP_SYSTEMD:-0}" == "1" ]]; then
    echo "Installed files successfully (systemd setup skipped)."
    return 0
  fi

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
}

trap cleanup EXIT

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
