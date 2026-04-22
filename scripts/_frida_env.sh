#!/usr/bin/env bash
set -euo pipefail

# Prefer Java 17 when present so any Java-based reverse engineering tools use
# the same known-good runtime as the static pipeline.
ANDROID_RE_JAVA_HOME="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
if [[ -x "$ANDROID_RE_JAVA_HOME/bin/java" ]]; then
  export JAVA_HOME="$ANDROID_RE_JAVA_HOME"
  export PATH="$JAVA_HOME/bin:$PATH"
fi

frida_python_candidates() {
  if [[ -n "${FRIDA_PYTHON:-}" ]]; then
    printf '%s\n' "$FRIDA_PYTHON"
  fi

  if [[ -n "${VIRTUAL_ENV:-}" ]] && [[ -x "${VIRTUAL_ENV}/bin/python" ]]; then
    printf '%s\n' "${VIRTUAL_ENV}/bin/python"
  fi

  printf '%s\n' \
    python3 \
    python \
    /opt/homebrew/bin/python3 \
    /usr/bin/python3
}

resolve_frida_python() {
  local candidate=""
  local candidate_path=""

  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue

    if [[ "$candidate" == /* ]]; then
      [[ -x "$candidate" ]] || continue
      candidate_path="$candidate"
    else
      command -v "$candidate" >/dev/null 2>&1 || continue
      candidate_path="$(command -v "$candidate")"
    fi

    if "$candidate_path" - <<'PY' >/dev/null 2>&1
import importlib.util
import sys

sys.exit(0 if importlib.util.find_spec("frida") else 1)
PY
    then
      printf '%s\n' "$candidate_path"
      return 0
    fi
  done < <(frida_python_candidates)

  return 1
}

ensure_frida_python_or_die() {
  local frida_python=""
  if ! frida_python="$(resolve_frida_python)"; then
    cat >&2 <<'EOF'
Error: could not find a Python interpreter with the `frida` module installed.

Try one of:
  python3 -m pip install --user frida frida-tools
  export FRIDA_PYTHON=/absolute/path/to/python-with-frida

Then rerun the command.
EOF
    exit 1
  fi

  printf '%s\n' "$frida_python"
}

has_working_frida_cli() {
  command -v frida >/dev/null 2>&1 && frida --version >/dev/null 2>&1
}
