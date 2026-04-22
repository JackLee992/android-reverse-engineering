#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/_frida_env.sh"

if [[ $# -eq 0 || "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'EOF'
Usage: run-frida-dexdump.sh --package <package> [OPTIONS]

Dump runtime DEX files from an Android app using Frida.

Options:
  --package PKG        Package name to spawn or attach to
  --pid PID            Attach to an already-running process ID
  --mode MODE          spawn (default) or attach
  --output-dir DIR     Local output directory for dumped dex files
  --usb-timeout-ms N   USB device lookup timeout in milliseconds (default: 5000)
  -h, --help           Show this help message

Examples:
  run-frida-dexdump.sh --package com.example.app
  run-frida-dexdump.sh --package com.example.app --mode attach --output-dir output/runtime-dex
EOF
  exit 0
fi

FRIDA_PYTHON="$(ensure_frida_python_or_die)"
exec "$FRIDA_PYTHON" "$SCRIPT_DIR/frida_dexdump_host.py" "$@"
