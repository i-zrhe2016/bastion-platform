#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [server-url] [--user <username>] [--agent <agent-id>]
  $0 --server-url <url> [--user <username>] [--agent <agent-id>]

Examples:
  $0
  $0 --user root
  $0 --agent 2f0f7c9f-1f10-471d-aef4-815dbf8dafe9 --user root
  $0 http://127.0.0.1:8080 --user root
USAGE
}

SERVER_URL="http://127.0.0.1:8080"
USERNAME="${USER:-$(id -un)}"
AGENT_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --server-url)
      SERVER_URL="$2"
      shift 2
      ;;
    --user)
      USERNAME="$2"
      shift 2
      ;;
    --agent)
      AGENT_ID="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    http://*|https://*)
      SERVER_URL="$1"
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "${AGENT_ID}" ]]; then
  AGENTS_RESPONSE="$(curl -fsS "${SERVER_URL%/}/api/v1/agents")"

  mapfile -t AGENT_IDS < <(printf '%s' "${AGENTS_RESPONSE}" | python3 -c 'import json,sys
agents = json.load(sys.stdin)
for item in agents:
    agent_id = item.get("agentId")
    if agent_id:
        print(agent_id)
')

  if [[ ${#AGENT_IDS[@]} -eq 0 ]]; then
    echo "No online agents found at ${SERVER_URL%/}/api/v1/agents" >&2
    exit 1
  fi

  echo "Online agents:"
  printf '%s' "${AGENTS_RESPONSE}" | python3 -c 'import json,sys
agents = json.load(sys.stdin)
for idx, item in enumerate(agents, 1):
    agent_id = item.get("agentId", "-")
    host = item.get("hostname", "-")
    ip = item.get("ip", "-")
    port = item.get("sshPort", "-")
    print(f"{idx}) {agent_id}\thost={host}\tip={ip}:{port}")
'

  if ! read -r -p "Select agent [1-${#AGENT_IDS[@]}] (default 1): " selection; then
    echo "Failed to read agent selection" >&2
    exit 1
  fi

  if [[ -z "${selection}" ]]; then
    selection=1
  fi

  if ! [[ "${selection}" =~ ^[0-9]+$ ]]; then
    echo "Invalid selection: ${selection}" >&2
    exit 1
  fi

  if (( selection < 1 || selection > ${#AGENT_IDS[@]} )); then
    echo "Selection out of range: ${selection}" >&2
    exit 1
  fi

  AGENT_ID="${AGENT_IDS[$((selection - 1))]}"
fi

JSON_PAYLOAD=$(cat <<JSON
{"agentId":"${AGENT_ID}","username":"${USERNAME}"}
JSON
)

RESPONSE=$(curl -fsS -X POST "${SERVER_URL%/}/api/v1/connections/one-click" \
  -H "Content-Type: application/json" \
  -d "$JSON_PAYLOAD")

CONNECT_CMD=$(printf '%s' "$RESPONSE" | python3 -c 'import json,sys; print(json.load(sys.stdin)["connectCommand"])')
TOKEN=$(printf '%s' "$RESPONSE" | python3 -c 'import json,sys; print(json.load(sys.stdin)["token"])')
EXPIRES_AT=$(printf '%s' "$RESPONSE" | python3 -c 'import json,sys; print(json.load(sys.stdin)["expiresAt"])')

echo "server=${SERVER_URL%/}"
echo "selectedAgent=${AGENT_ID}"
echo "username=${USERNAME}"
echo "token=${TOKEN}"
echo "expiresAt=${EXPIRES_AT}"
echo "executing: ${CONNECT_CMD}"
exec bash -lc "$CONNECT_CMD"
