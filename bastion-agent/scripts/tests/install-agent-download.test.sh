#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_SCRIPT="$(cd "${SCRIPT_DIR}/.." && pwd)/install-agent.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

pass() {
  echo "PASS: $1"
}

test_downloads_binary_when_local_missing() (
  local tmpdir
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT

  mkdir -p "$tmpdir/bin" "$tmpdir/install"
  cat > "$tmpdir/fake-agent" <<'AGENT'
#!/usr/bin/env bash
echo "agent"
AGENT
  chmod +x "$tmpdir/fake-agent"

  cat > "$tmpdir/bin/curl" <<'CURL'
#!/usr/bin/env bash
set -euo pipefail
out=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o)
      out="$2"
      shift 2
      ;;
    -fsSL)
      shift
      ;;
    *)
      shift
      ;;
  esac
done
[[ -n "$out" ]] || exit 1
cat "$FAKE_AGENT_PAYLOAD" > "$out"
CURL
  chmod +x "$tmpdir/bin/curl"

  PATH="$tmpdir/bin:$PATH" \
  FAKE_AGENT_PAYLOAD="$tmpdir/fake-agent" \
  BASTION_AGENT_INSTALL_SKIP_SYSTEMD=1 \
  bash "$INSTALL_SCRIPT" \
    --bin "$tmpdir/missing-local-binary" \
    --download-url "https://example.com/bastion-agent-linux-amd64" \
    --install-dir "$tmpdir/install" \
    --service-name "test-bastion-agent" \
    --server-url "http://127.0.0.1:8080"

  [[ -x "$tmpdir/install/bastion-agent" ]] || fail "downloaded binary was not installed"
  [[ -f "$tmpdir/install/application.yml" ]] || fail "application.yml was not generated"
  pass "download when local binary missing"
)

test_rejects_non_amd64_auto_download() (
  local tmpdir
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT

  mkdir -p "$tmpdir/bin"
  cat > "$tmpdir/bin/uname" <<'UNAME'
#!/usr/bin/env bash
if [[ "${1:-}" == "-m" ]]; then
  echo "aarch64"
else
  /usr/bin/uname "$@"
fi
UNAME
  chmod +x "$tmpdir/bin/uname"

  set +e
  local output
  output="$({ PATH="$tmpdir/bin:$PATH" BASTION_AGENT_INSTALL_SKIP_SYSTEMD=1 bash "$INSTALL_SCRIPT" --bin "$tmpdir/missing-local-binary" --download-url "https://example.com/bastion-agent"; } 2>&1)"
  local status=$?
  set -e

  [[ "$status" -ne 0 ]] || fail "installer should fail on non-amd64 auto download"
  echo "$output" | grep -q "Only amd64 is supported" || fail "missing non-amd64 error message"
  pass "reject non-amd64 auto download"
)

main() {
  test_downloads_binary_when_local_missing
  test_rejects_non_amd64_auto_download
}

main "$@"
