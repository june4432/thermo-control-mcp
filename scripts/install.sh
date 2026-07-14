#!/bin/bash
#
# Build and install the thermod daemon (root LaunchDaemon) that
# thermo-control-mcp uses for fan control.
#
# Usage: sudo ./scripts/install.sh
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BINARY_DEST="/usr/local/libexec/thermod"
PLIST_SRC="$REPO_ROOT/launchd/com.thermocontrol.thermod.plist"
PLIST_DEST="/Library/LaunchDaemons/com.thermocontrol.thermod.plist"
LABEL="com.thermocontrol.thermod"
SOCKET="/var/run/thermod.sock"

if [[ "$(uname)" != "Darwin" ]]; then
  echo "error: thermod only runs on macOS" >&2
  exit 1
fi

if [[ $EUID -ne 0 ]]; then
  echo "error: this script must run as root (try: sudo $0)" >&2
  exit 1
fi

# Build as the invoking user, not root, so build artifacts stay user-owned.
BUILD_USER="${SUDO_USER:-$(whoami)}"
echo "==> Building thermod (swift build -c release) as $BUILD_USER"
sudo -u "$BUILD_USER" swift build --package-path "$REPO_ROOT/daemon" -c release

BINARY_SRC="$REPO_ROOT/daemon/.build/release/thermod"
if [[ ! -x "$BINARY_SRC" ]]; then
  echo "error: build did not produce $BINARY_SRC" >&2
  exit 1
fi

echo "==> Installing binary to $BINARY_DEST"
mkdir -p "$(dirname "$BINARY_DEST")"
install -m 755 -o root -g wheel "$BINARY_SRC" "$BINARY_DEST"

echo "==> Installing LaunchDaemon $PLIST_DEST"
launchctl bootout system "$PLIST_DEST" 2>/dev/null || true
install -m 644 -o root -g wheel "$PLIST_SRC" "$PLIST_DEST"
launchctl bootstrap system "$PLIST_DEST"

echo "==> Waiting for daemon socket"
for _ in $(seq 1 20); do
  [[ -S "$SOCKET" ]] && break
  sleep 0.5
done

if [[ ! -S "$SOCKET" ]]; then
  echo "error: daemon did not create $SOCKET — check /Library/Logs/thermod.log" >&2
  exit 1
fi

echo "==> Ping"
if command -v nc >/dev/null; then
  echo '{"cmd":"ping"}' | nc -U "$SOCKET" || {
    echo "error: daemon is not answering — check /Library/Logs/thermod.log" >&2
    exit 1
  }
fi

cat <<EOF

thermod is installed and running.

  daemon : $BINARY_DEST (LaunchDaemon $LABEL)
  socket : $SOCKET (root:admin, mode 0660)
  logs   : /Library/Logs/thermod.log

Next, register the MCP server with Claude Code:

  cd $REPO_ROOT && npm install && npm run build
  claude mcp add thermo-control -- node $REPO_ROOT/dist/index.js

To remove everything later: sudo $REPO_ROOT/scripts/uninstall.sh
EOF
