#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_SCRIPT="${SCRIPT_DIR}/../one-click-connect.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

mkdir -p "${TMP_DIR}/bin" "${TMP_DIR}/logs"

cat > "${TMP_DIR}/bin/curl" <<'EOF'
#!/bin/bash
set -euo pipefail

LOG_DIR="${FAKE_LOG_DIR:?}"
url=""
payload=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--data|--data-raw|--data-binary)
      payload="${2:-}"
      shift 2
      ;;
    http://*|https://*)
      url="$1"
      shift
      ;;
    *)
      shift
      ;;
  esac
done

if [[ -n "${payload}" ]]; then
  printf '%s\n' "${payload}" > "${LOG_DIR}/last-payload.json"
fi

if [[ "${url}" == "http://127.0.0.1:8080/api/v1/agents" ]]; then
  cat <<'JSON'
[{"agentId":"agent-a","hostname":"jump-a","ip":"10.0.0.1","sshPort":22,"online":true},{"agentId":"agent-b","hostname":"jump-b","ip":"10.0.0.2","sshPort":2202,"online":true}]
JSON
  exit 0
fi

if [[ "${url}" == "http://127.0.0.1:8080/api/v1/connections/one-click" ]]; then
  cat <<'JSON'
{"token":"tok-123","expiresAt":"2099-01-01T00:00:00Z","connectCommand":"ssh demo@10.0.0.2 -p 2202"}
JSON
  exit 0
fi

echo "unexpected url: ${url}" >&2
exit 1
EOF
chmod +x "${TMP_DIR}/bin/curl"

cat > "${TMP_DIR}/bin/bash" <<'EOF'
#!/bin/bash
set -euo pipefail

if [[ "${1:-}" == "-lc" ]]; then
  printf '%s\n' "${2:-}" > "${FAKE_LOG_DIR:?}/executed-command.txt"
  exit 0
fi

echo "unexpected bash args: $*" >&2
exit 1
EOF
chmod +x "${TMP_DIR}/bin/bash"

if ! output="$(
  printf '2\n' | USER="demo" FAKE_LOG_DIR="${TMP_DIR}/logs" PATH="${TMP_DIR}/bin:/usr/bin:/bin" \
    /bin/bash "${TARGET_SCRIPT}" 2>&1
)"; then
  echo "script run failed"
  echo "${output}"
  exit 1
fi

EXPECTED_PAYLOAD='{"agentId":"agent-b","username":"demo"}'
ACTUAL_PAYLOAD="$(cat "${TMP_DIR}/logs/last-payload.json")"
if [[ "${ACTUAL_PAYLOAD}" != "${EXPECTED_PAYLOAD}" ]]; then
  echo "unexpected payload"
  echo "expected: ${EXPECTED_PAYLOAD}"
  echo "actual:   ${ACTUAL_PAYLOAD}"
  exit 1
fi

EXECUTED_CMD="$(cat "${TMP_DIR}/logs/executed-command.txt")"
if [[ "${EXECUTED_CMD}" != "ssh demo@10.0.0.2 -p 2202" ]]; then
  echo "unexpected executed command: ${EXECUTED_CMD}"
  exit 1
fi

if ! printf '%s' "${output}" | grep -q "selectedAgent=agent-b"; then
  echo "expected selectedAgent output missing"
  echo "${output}"
  exit 1
fi

if ! printf '%s' "${output}" | grep -q "token=tok-123"; then
  echo "expected token output missing"
  echo "${output}"
  exit 1
fi

echo "PASS: one-click connect defaults + choose agent"
