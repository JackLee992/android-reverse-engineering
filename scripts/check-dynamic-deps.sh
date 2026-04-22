#!/usr/bin/env bash
# check-dynamic-deps.sh — Verify host/runtime dependencies for Frida workflows.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/_frida_env.sh"

errors=0
missing_required=()
missing_optional=()

echo "=== Android Reverse Engineering: Dynamic Dependency Check ==="
echo

if command -v adb >/dev/null 2>&1; then
  echo "[OK] adb detected: $(command -v adb)"
else
  echo "[MISSING] adb is not installed or not in PATH"
  missing_required+=("adb")
  errors=$((errors + 1))
fi

if frida_python="$(resolve_frida_python)"; then
  echo "[OK] Frida Python host detected: $frida_python"
else
  echo "[MISSING] no Python interpreter with the frida module was found"
  missing_required+=("frida-python")
  errors=$((errors + 1))
fi

if has_working_frida_cli; then
  echo "[OK] frida CLI detected"
else
  echo "[MISSING] frida CLI is missing or broken (optional if Python host works)"
  missing_optional+=("frida-cli")
fi

if command -v ida-pro-mcp >/dev/null 2>&1; then
  echo "[OK] ida-pro-mcp detected"
else
  echo "[MISSING] ida-pro-mcp not found (optional — required only for IDA handoff)"
  missing_optional+=("ida-pro-mcp")
fi

if command -v adb >/dev/null 2>&1; then
  device_id="$(adb devices 2>/dev/null | awk 'NR > 1 && $2 == "device" { print $1; exit }')"
  if [[ -n "$device_id" ]]; then
    echo "[OK] Android device detected over adb: $device_id"

    if adb shell 'pidof frida-server 2>/dev/null || ps -A 2>/dev/null | grep -F frida-server' >/dev/null 2>&1; then
      echo "[OK] frida-server appears to be running on the device"
    else
      echo "[MISSING] frida-server was not detected on the connected device (optional until runtime tracing)"
      missing_optional+=("frida-server-device")
    fi
  else
    echo "[MISSING] no adb-connected Android device detected (optional until runtime tracing)"
    missing_optional+=("android-device")
  fi
fi

echo
for dep in "${missing_required[@]:-}"; do
  [[ -n "$dep" ]] && echo "INSTALL_REQUIRED:$dep"
done
for dep in "${missing_optional[@]:-}"; do
  [[ -n "$dep" ]] && echo "INSTALL_OPTIONAL:$dep"
done

echo
if (( errors > 0 )); then
  echo "*** ${#missing_required[@]} required dynamic dependency/ies missing. ***"
  echo "Install the missing host tooling before using the Frida runtime workflows."
  exit 1
fi

if [[ ${#missing_optional[@]} -gt 0 ]]; then
  echo "Required dynamic dependencies OK. ${#missing_optional[@]} optional item(s) missing."
else
  echo "All dynamic dependencies detected. Ready for runtime tracing."
fi
