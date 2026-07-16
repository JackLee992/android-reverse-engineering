# IDA Pro MCP

`ida-pro-mcp` is the recommended companion for deep native analysis once the Frida traces tell you which `.so` file and function offsets matter.

Repository:

```text
https://github.com/mrexodia/ida-pro-mcp
```

## Prerequisites

- Python 3.11+
- IDA Pro 8.3 or newer
- A Codex installation that can use MCP servers

## Install

Install the package:

```bash
pip uninstall ida-pro-mcp
pip install https://github.com/mrexodia/ida-pro-mcp/archive/refs/heads/main.zip
```

Install the IDA plugin and configure the MCP server:

```bash
ida-pro-mcp --install
```

Then restart:

- IDA Pro
- Codex

The upstream project explicitly supports Codex as an MCP client.

## How this skill uses it

After collecting:

- runtime DEX dumps
- `.so` load traces
- JNI registration traces

you should:

1. open the target `.so` in IDA
2. make sure `ida-pro-mcp` is connected
3. ask Codex to:
   - inspect the decompilation
   - rename functions and variables
   - add comments from the Frida traces
   - follow offsets from `jni-trace.jsonl`

## Handoff example

Once IDA is open and connected, ask Codex something like:

```text
Use IDA MCP to analyze the native login code in libtarget.so.
Start from the offsets listed in output/jni-trace.jsonl and rename the JNI entrypoints.
```

## Using it from Hermes (headless idalib, no GUI) — VERIFIED

`ida-pro-mcp` (v2.x) ships a **headless idalib server** (`idalib_server.py`) that runs
IDA's analysis engine + Hex-Rays without opening the GUI. This is the path to use
inside Hermes: register it as an MCP server and drive it with `delegate_task`/tools.

### One-time setup (already done on this machine)

1. **Activate idalib for the ida-pro-mcp venv.** The package installs into its own
   venv at `~/.local/share/ida-pro-mcp-venv/` (Python **3.14**). idalib must be bound
   to that interpreter — the module is imported as **`idapro`** (NOT `idalib`):
   ```bash
   VENV_PY="$HOME/.local/share/ida-pro-mcp-venv/bin/python"
   "$VENV_PY" "/Applications/IDA Professional 9.3.app/Contents/MacOS/idalib/python/py-activate-idalib.py" \
     -d "/Applications/IDA Professional 9.3.app/Contents/MacOS"
   "$VENV_PY" -c "import idapro; print('idalib OK')"
   ```

2. **Register a stdio launcher in Hermes.** Upstream `idalib_server.main()` only
   exposes Streamable-HTTP (port 8745), forcing a manually-started long-lived server.
   The bundled `scripts/idalib_stdio_launcher.py` reuses the same init but drives the
   underlying `MCP_SERVER.stdio()` so **Hermes spawns it on demand**:
   ```bash
   hermes mcp add ida-pro \
     --command "$HOME/.local/share/ida-pro-mcp-venv/bin/python" \
     --args   "$HOME/.hermes/skills/android/android-reverse-engineering/scripts/idalib_stdio_launcher.py"
   # answer "Y" to "Enable all 67 tools?" — then START A NEW SESSION
   ```

### Pitfalls (learned the hard way)

- **idalib module is `idapro`, not `idalib`.** `import idalib` fails; `import idapro` works.
- **`ida-pro-mcp --config` emits the WRONG interpreter.** It puts whatever `python3` is
  first on PATH as `command` (e.g. a project venv 3.11), but the deps live in the
  **3.14** venv. Always point `command` at `~/.local/share/ida-pro-mcp-venv/bin/python`.
- **`hermes mcp add` needs an interactive "Enable all N tools? [Y/n]" confirm.** In a
  non-interactive pipe it validates + connects but does NOT save. Run under a pty or
  pipe `y`. Verify with `hermes mcp list` and check `mcp_servers` in `~/.hermes/config.yaml`.
- **New tools only appear in a NEW Hermes session** (MCP toolset is snapshotted at
  session start).
- **stdout is the MCP transport** in stdio mode — the launcher sends all logging to
  stderr. Don't print to stdout from the launcher.

### Runtime workflow (one server, many binaries)

The server starts empty and loads binaries on demand — no restart per file:
- `idalib_open(input_path=..., run_auto_analysis=true)` — load + analyze a binary/.so
- `func_query(queries=[{"limit":N}])`, `decompile(addr="0x...")`, `disasm(addr=...)`,
  `imports(...)`, `xrefs_to(...)`, `callees(...)`, `analyze_batch(...)` — 67 tools total
- `idalib_list` / `idalib_switch(session_id=...)` / `idalib_close(session_id=...)` — juggle multiple DBs
- Tool arg for an address is **`addr`** (hex string), not `address`.

Typical Android chain: frida-dump a `.so` → `idalib_open` it → `decompile`/`xrefs_to`\nfrom the JNI offsets in `output/jni-trace.jsonl`.

### Fallback: headless `idat -A -S` batch-decompile when MCP isn't in this session

The MCP toolset is snapshotted at session start, so if `ida-pro` wasn't loaded this\nsession you can't `idalib_open`. Rather than force a new session, drive IDA's own\nbundled interpreter headlessly against an **already-built `.i64`** (auto-analysis\ndone once, reused). Write a small script that decompiles a list of addresses to JSON\nand run it with:

```bash
"/Applications/IDA Professional 9.3.app/Contents/MacOS/idat" -A -S"/abs/path/dump.py" /abs/path/libX.so.i64
```

Script skeleton that WORKS (matches the `-A -S` runner contract):

```python
import ida_hexrays, ida_funcs, idaapi, ida_auto
import json, os
OUT = os.path.join(os.path.dirname(__file__), "out.json")
TARGETS = [0x20111C, 0x20C70C]        # addresses to decompile
def main():
    ida_auto.auto_wait()
    if not ida_hexrays.init_hexrays_plugin():
        open(OUT,"w").write(json.dumps({"error":"no hexrays"})); return
    res = {}
    for ea in TARGETS:
        f = ida_funcs.get_func(ea)
        res[hex(ea)] = ({"c": str(ida_hexrays.decompile(f.start_ea))}
                        if f else {"error":"no func"})
    open(OUT,"w").write(json.dumps(res))
main()
idaapi.qexit(0)          # <-- MANDATORY, see pitfall
```

Also useful in the same runner: `ida_bytes.get_dword(ea)` / `get_bytes(ea,n)` to read\nglobal constants (TLV tag bytes, embedded key material offsets) without decompiling.

**Pitfall that cost real time:** under `idat -A -S` the module is **`idaapi`**, and\nyou MUST end with `idaapi.qexit(0)`. A script written for the *idalib* entrypoint\n(`import idapro` + no `qexit`) **fails silently** — no output file, no traceback,\nexit 0 — because that import/exit contract is for the standalone `idalib` runner,\nnot the `idat -A -S` batch runner. When a batch script produces no file and no\nerror, this mismatch is the first thing to check. Copy the skeleton above verbatim\nrather than re-deriving it. (Bundled IDA python is 3.14; a `sys.prefix` RuntimeWarning\nabout your project venv is harmless noise, not the failure.)
