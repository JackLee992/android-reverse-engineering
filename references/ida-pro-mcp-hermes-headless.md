# IDA Pro MCP — Hermes client + headless idalib (verified recipe)

The bundled `ida-pro-mcp.md` reference is Codex-centric and only covers the
GUI-bridge path. This file captures the **verified** end-to-end setup for using
`ida-pro-mcp` (mrexodia) with **Hermes as the MCP client**, including the
fully-automatable **headless idalib** path that needs no IDA GUI open.

Verified against **IDA Professional 9.3** on macOS arm64, `ida-pro-mcp` 2.0.0,
in a Python **3.14** venv at `~/.local/share/ida-pro-mcp-venv/`.

## Three-layer architecture (understand this first)

1. **IDA plugin `ida_mcp`** — runs *inside* IDA (GUI or idalib). Exposes a
   JSON-RPC service. GUI default port **13337**; idalib server default **8745**.
2. **Bridge / server** (`ida_pro_mcp/server.py` or `idalib_server.py`) — the MCP
   server other agents connect to. `server.py` = stdio bridge to a running IDA
   RPC; `idalib_server.py` = self-contained headless HTTP MCP that loads the
   binary itself via idalib.
3. **MCP client** — Codex, Claude, Cursor, **or Hermes** (`hermes mcp add`).

## Two modes, pick per task

- **Headless idalib (no GUI):** `idalib_server.py` opens the binary itself, runs
  auto-analysis, serves streamable-HTTP MCP on `:8745`. Best for automated /
  batch analysis of `.so` files dumped from the Frida pipeline. **This is the
  path proven end-to-end below.**
- **GUI bridge:** user opens the target in IDA, plugin serves on `:13337`,
  Hermes connects via the stdio `server.py` bridge. Best for interactive digging
  on one open database while the user watches.

## One-time: activate idalib into the bridge's venv

idalib ships with IDA 9.x but must be bound to the Python that runs the server.
The Python module is named **`idapro`**, NOT `idalib` — `import idalib` will
always fail; test with `import idapro`.

```bash
VENV_PY="$HOME/.local/share/ida-pro-mcp-venv/bin/python"
IDA_DIR="/Applications/IDA Professional 9.3.app/Contents/MacOS"
"$VENV_PY" "$IDA_DIR/idalib/python/py-activate-idalib.py" -d "$IDA_DIR"
# verify:
"$VENV_PY" -c "import idapro; print('idalib OK', idapro.__file__)"
```

The activate step writes `~/.idapro/ida-config.json` with the install dir.

## PITFALL: `ida-pro-mcp --config` emits the WRONG interpreter

`ida-pro-mcp --config` generates stdio config whose `command` is whatever
`python3` resolves to on PATH — which may be an unrelated project venv (e.g. a
3.11 venv) that lacks the deps installed in the 3.14 idalib venv. **Do not copy
that command verbatim.** Always point the MCP client at the bridge's own venv
interpreter: `~/.local/share/ida-pro-mcp-venv/bin/python`.

## Headless smoke test (fully automated, no GUI)

Start the idalib server on a copy of a test binary (copy first so the `.i64`
database lands in scratch, not a system path). `timeout` is absent on macOS —
run in the background and poll instead. Unset `VIRTUAL_ENV` so the venv's site
config is clean:

```bash
VENV_PY="$HOME/.local/share/ida-pro-mcp-venv/bin/python"
SERVER="$HOME/.local/share/ida-pro-mcp-venv/lib/python3.14/site-packages/ida_pro_mcp/idalib_server.py"
TESTDIR=$(mktemp -d); cp /bin/ls "$TESTDIR/ls_sample"
env -u VIRTUAL_ENV "$VENV_PY" "$SERVER" --host 127.0.0.1 --port 8745 "$TESTDIR/ls_sample"
# Ready when the log prints:  [MCP] Server started: Streamable HTTP: http://127.0.0.1:8745/mcp
```

Auto-analysis takes ~10s before the port serves. Health is confirmed when
`server_health` returns `auto_analysis_ready:true` and `hexrays_ready:true`.

## Driving it over MCP (streamable-HTTP)

Endpoint `http://127.0.0.1:8745/mcp`. Headers:
`Accept: application/json, text/event-stream`. Responses may be SSE-framed
(`data: {...}` lines) — parse the last `data:` line as JSON. In shared-fallback
mode `initialize` returns no `Mcp-Session-Id`; you can call tools directly after
`initialize` + `notifications/initialized`. ~67 tools exposed.

### Tool param names that bit us (schema, not guessable)

- `decompile` → `{"addr": "0x..."}`  (NOT `address`)
- `disasm` → `{"addr": "0x...", "max_instructions": N}`
- `func_query` → `{"queries": [{"limit": N}]}`  (requires `queries`, a list)
- `list_funcs` also requires `queries`, not `offset/count`
- `imports` → `{"offset": 0, "count": N}`
Always fetch `tools/list` and read each tool's `inputSchema.properties` before
calling — don't assume names.

## Registering into Hermes

Headless HTTP (recommended for automation):
```bash
hermes mcp add ida-pro-mcp --url http://127.0.0.1:8745/mcp
```
GUI bridge (stdio) — point `--command` at the bridge venv python, `--args` at
`server.py`; do NOT reuse the `--config` command line. Verify with
`hermes mcp test ida-pro-mcp`.
