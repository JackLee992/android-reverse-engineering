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
