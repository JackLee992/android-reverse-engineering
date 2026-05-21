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

## Local readiness check

Before asking Codex to use IDA MCP, run:

```bash
bash "$HOME/.codex/skills/android-reverse-engineering/scripts/check-ida-mcp.sh"
```

The checker verifies:

- IDA app discovery under `/Applications` and `~/Applications`
- `ida` and `idat` executables
- `ida-pro-mcp` CLI availability
- `~/.idapro/plugins/ida_mcp.py` and `~/.idapro/plugins/ida_mcp`
- Codex `~/.codex/config.toml` MCP entry
- TCP and MCP JSON-RPC reachability at `http://127.0.0.1:13337/mcp`

Machine-readable markers:

- `IDA_APP:<path>`
- `IDA_IDAT:<path>`
- `IDA_MCP_PLUGIN:<path>`
- `IDA_MCP_REACHABLE:0|1`
- `IDA_MCP_READY:0|1`
- `IDA_IDB_OPEN:0|1`
- `IDA_MODULE:<name>`
- `IDA_IMAGEBASE:<hex-address>`
- `IDA_HEXRAYS_READY:0|1`

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

Codex config can use the IDA-side HTTP endpoint:

```toml
[mcp_servers.ida-pro-mcp]
url = "http://127.0.0.1:13337/mcp"
```

This endpoint only exists while IDA is running and the MCP plugin has been started.

## Starting the IDA-side MCP server

Normal path:

1. Open the target `.so` in IDA Pro.
2. Wait for auto-analysis to settle.
3. Start `Edit -> Plugins -> MCP`, or press `Ctrl+Option+M` on macOS.
4. Confirm the output window prints a streamable HTTP URL such as `http://127.0.0.1:13337/mcp`.
5. Re-run `check-ida-mcp.sh`; continue only when `IDA_MCP_READY:1` appears. If `IDA_IDB_OPEN:0` appears, open the target binary or use the MCP `open_file` tool from a running IDA instance.

If IDA is open but Codex reports connection refused, run `check-ida-mcp.sh`. On some macOS installs, plugin symlinks exist in `~/.idapro/plugins` but IDA does not discover the Python plugin by name. In that case, paste the checker's absolute-path bootstrap into IDA's Python console. The expected success output includes:

```text
[MCP] Server started:
  Streamable HTTP: http://127.0.0.1:13337/mcp
```

## Recommended MCP workflow

Use the smallest useful IDA calls first:

1. `server_health` to verify the active IDB, image base, Hex-Rays availability, and auto-analysis readiness.
2. `survey_binary` for a compact overview of metadata, segments, imports, strings, functions, and call graph hints.
3. `lookup_funcs` or `entity_query` to resolve Frida offsets, JNI names, exports, string anchors, or suspicious imports.
4. `analyze_function` for compact per-function context; use `decompile` or `disasm` when the full body is needed.
5. `trace_data_flow`, xrefs, callers, and callees to follow values from strings, globals, JNI registration tables, and crypto/network APIs.
6. `rename`, `set_type`, and `set_comments` only after verifying the target address and intended meaning.

For Android native traces:

- Convert module-relative offsets from Frida to IDA addresses by adding the IDA image base when needed.
- Confirm the loaded ABI (`arm64-v8a`, `armeabi-v7a`, etc.) matches the `.so` opened in IDA.
- Prefer JNI registration evidence over guessed Java native names when both are available.

## How this skill uses it

After collecting:

- runtime DEX dumps
- `.so` load traces
- JNI registration traces

you should:

1. open the target `.so` in IDA
2. run `check-ida-mcp.sh` and make sure `IDA_MCP_READY:1` appears
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
