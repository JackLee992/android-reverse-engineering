#!/usr/bin/env bash
# check-ida-mcp.sh - Verify local IDA Pro and ida-pro-mcp handoff readiness.
set -euo pipefail

IDA_MCP_URL="${IDA_MCP_URL:-http://127.0.0.1:13337/mcp}"
IDA_PLUGIN_DIR="${IDA_PLUGIN_DIR:-$HOME/.idapro/plugins}"
CODEX_CONFIG="${CODEX_CONFIG:-$HOME/.codex/config.toml}"

echo "=== Android Reverse Engineering: IDA MCP Check ==="
echo

find_ida_app() {
  local dir candidate
  for dir in /Applications "$HOME/Applications"; do
    [[ -d "$dir" ]] || continue
    while IFS= read -r candidate; do
      if [[ -x "$candidate/Contents/MacOS/ida" || -x "$candidate/Contents/MacOS/idat" ]]; then
        printf '%s\n' "$candidate"
        return 0
      fi
    done < <(find "$dir" -maxdepth 2 -type d -iname '*IDA*.app' 2>/dev/null | sort -r)
  done
}

probe_tcp() {
  local host="$1"
  local port="$2"
  python3 - "$host" "$port" <<'PY'
import socket
import sys

host, port = sys.argv[1], int(sys.argv[2])
s = socket.socket()
s.settimeout(1.5)
try:
    s.connect((host, port))
except OSError as exc:
    print(f"FAIL {type(exc).__name__}: {exc}")
    sys.exit(1)
finally:
    s.close()
print("OK")
PY
}

probe_mcp() {
  local url="$1"
  python3 - "$url" <<'PY'
import json
import sys
import urllib.request

url = sys.argv[1]

def call(payload):
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "Accept": "application/json, text/event-stream",
        },
    )
    with urllib.request.urlopen(req, timeout=5) as resp:
        return json.loads(resp.read().decode("utf-8"))

tools_response = call({"jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": {}})
tools = tools_response.get("result", {}).get("tools", [])
tool_names = {tool.get("name") for tool in tools}
if "server_health" not in tool_names:
    print("[WARN] MCP tools/list succeeded but server_health is missing")
    print("IDA_MCP_READY:0")
    sys.exit(0)

print("[OK] MCP tools/list succeeded")
print("IDA_MCP_READY:1")

health_response = call(
    {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {"name": "server_health", "arguments": {}},
    }
)
health = health_response.get("result", {}).get("structuredContent") or {}
if not health:
    print("[WARN] server_health returned no structured content")
    sys.exit(0)

status = health.get("status", "unknown")
idb_path = health.get("idb_path") or ""
module = health.get("module") or ""
imagebase = health.get("imagebase") or ""
hexrays_ready = bool(health.get("hexrays_ready"))
auto_ready = health.get("auto_analysis_ready")

print(f"[OK] server_health status: {status}")
print(f"IDA_IDB_OPEN:{1 if idb_path or module else 0}")
if idb_path:
    print(f"IDA_IDB_PATH:{idb_path}")
if module:
    print(f"IDA_MODULE:{module}")
if imagebase:
    print(f"IDA_IMAGEBASE:{imagebase}")
print(f"IDA_HEXRAYS_READY:{1 if hexrays_ready else 0}")
if auto_ready is not None:
    print(f"IDA_AUTO_ANALYSIS_READY:{1 if auto_ready else 0}")
if not idb_path and not module:
    print("[WARN] MCP is live, but no target binary/IDB is open yet")
PY
}

ida_app="$(find_ida_app || true)"
if [[ -n "$ida_app" ]]; then
  echo "[OK] IDA app found: $ida_app"
  echo "IDA_APP:$ida_app"

  info_plist="$ida_app/Contents/Info.plist"
  if [[ -f "$info_plist" ]]; then
    version="$(plutil -extract CFBundleShortVersionString raw "$info_plist" 2>/dev/null || true)"
    bundle_id="$(plutil -extract CFBundleIdentifier raw "$info_plist" 2>/dev/null || true)"
    [[ -n "$version" ]] && echo "[OK] IDA version: $version"
    [[ -n "$bundle_id" ]] && echo "[OK] Bundle id: $bundle_id"
  fi

  ida_bin="$ida_app/Contents/MacOS/ida"
  idat_bin="$ida_app/Contents/MacOS/idat"
  if [[ -x "$ida_bin" ]]; then
    echo "[OK] GUI executable: $ida_bin"
    echo "IDA_GUI:$ida_bin"
  else
    echo "[WARN] GUI executable missing or not executable: $ida_bin"
  fi
  if [[ -x "$idat_bin" ]]; then
    echo "[OK] Text/headless executable: $idat_bin"
    echo "IDA_IDAT:$idat_bin"
    idat_help="$("$idat_bin" -h 2>&1 || true)"
    if [[ "$idat_help" == *"Command line switches"* || "$idat_help" == *"IDA can be launched"* ]]; then
      echo "[OK] idat help command runs"
    else
      echo "[WARN] idat exists but did not return help cleanly"
    fi
  else
    echo "[WARN] Text/headless executable missing or not executable: $idat_bin"
  fi
else
  echo "[MISSING] IDA app not found under /Applications or ~/Applications"
  echo "INSTALL_OPTIONAL:ida-pro"
fi

echo
if command -v ida-pro-mcp >/dev/null 2>&1; then
  echo "[OK] ida-pro-mcp CLI detected: $(command -v ida-pro-mcp)"
else
  echo "[MISSING] ida-pro-mcp CLI not found"
  echo "INSTALL_OPTIONAL:ida-pro-mcp"
fi

if [[ -e "$IDA_PLUGIN_DIR/ida_mcp.py" && -e "$IDA_PLUGIN_DIR/ida_mcp" ]]; then
  echo "[OK] IDA MCP plugin links exist in $IDA_PLUGIN_DIR"
  echo "IDA_MCP_PLUGIN:$IDA_PLUGIN_DIR/ida_mcp.py"
else
  echo "[MISSING] IDA MCP plugin links are not installed in $IDA_PLUGIN_DIR"
  echo "INSTALL_OPTIONAL:ida-pro-mcp-plugin"
fi

if [[ -f "$CODEX_CONFIG" ]] && grep -q '\[mcp_servers\.ida-pro-mcp\]' "$CODEX_CONFIG"; then
  echo "[OK] Codex config includes [mcp_servers.ida-pro-mcp]"
else
  echo "[WARN] Codex config does not include [mcp_servers.ida-pro-mcp]"
fi

echo
host_port="${IDA_MCP_URL#http://}"
host_port="${host_port%%/*}"
host="${host_port%%:*}"
port="${host_port##*:}"
if probe_result="$(probe_tcp "$host" "$port" 2>&1)"; then
  echo "[OK] IDA MCP TCP endpoint reachable: $host:$port"
  echo "IDA_MCP_REACHABLE:1"
else
  echo "[MISSING] IDA MCP TCP endpoint is not reachable: $host:$port ($probe_result)"
  echo "IDA_MCP_REACHABLE:0"
  cat <<'EOF'

Start or repair the IDA-side server:
1. Open IDA Pro and open a target binary or choose "Go" from Quick start.
2. Try Edit -> Plugins -> MCP, or Ctrl+Option+M on macOS.
3. If the plugin does not appear, paste this into IDA's Python console:

import os, sys, importlib.util; plugin_dir=os.path.expanduser("~/.idapro/plugins"); sys.path.insert(0, plugin_dir); spec=importlib.util.spec_from_file_location("codex_ida_mcp_loader", os.path.join(plugin_dir, "ida_mcp.py")); mod=importlib.util.module_from_spec(spec); spec.loader.exec_module(mod); _codex_ida_mcp_plugin=mod.PLUGIN_ENTRY(); print("init=", _codex_ida_mcp_plugin.init()); _codex_ida_mcp_plugin.run(0)

EOF
  exit 0
fi

probe_mcp "$IDA_MCP_URL"
