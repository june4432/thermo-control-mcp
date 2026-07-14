#!/bin/bash
#
# Remove the thermod daemon. Fans revert to macOS system control on
# daemon shutdown.
#
# Usage: sudo ./scripts/uninstall.sh
#
set -euo pipefail

PLIST_DEST="/Library/LaunchDaemons/com.thermocontrol.thermod.plist"
BINARY_DEST="/usr/local/libexec/thermod"
SOCKET="/var/run/thermod.sock"

if [[ $EUID -ne 0 ]]; then
  echo "error: this script must run as root (try: sudo $0)" >&2
  exit 1
fi

echo "==> Stopping daemon (fans revert to system control)"
launchctl bootout system "$PLIST_DEST" 2>/dev/null || true

echo "==> Removing files"
rm -f "$PLIST_DEST" "$BINARY_DEST" "$SOCKET"

echo "thermod removed. If you registered the MCP server, remove it with:"
echo "  claude mcp remove thermo-control"
