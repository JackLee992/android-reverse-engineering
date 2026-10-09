# REA alongside the Android workflow

REA supplies structured inspection tools. The parent Android skill remains responsible for investigation strategy, runtime tracing, native handoffs, and validation of reconstructed behavior. Resolve `$SKILL_DIR` to the directory containing the parent `SKILL.md`; never assume a particular username or operating system.

## Installation and cross-device sync

The companion skill is [JackLee992/reverse-engineer-anything](https://github.com/JackLee992/reverse-engineer-anything). Its README contains first-time setup, the pinned package/engine versions, and the Git update commands. The snapshot paired with this integration is REA 6.0.0, skill version 33, and JADX headless MCP 0.7.1. Tool counts and availability must come from the connected server, not this version note.

Keep runtime and MCP configuration local to each device. A Git pull updates instructions and helper scripts; it does not install Node, Java, analysis engines, or reconnect an already-running agent.

Choose the CLI in this order:

1. Use the machine's working `rea` launcher. If `$HOME/.local/bin/rea` exists from the dedicated installation, prefer it; it selects its own supported Node runtime and Android engine.
2. Otherwise use a globally installed `rea` with a supported Node version, or `npx -y rea-agents@6.0.0` for this pinned snapshot.

The dedicated installation convention uses `$HOME/.local/share/rea` for its runtime/package/engine and `$HOME/.local/bin/rea` for its launcher. These are optional local paths, not prerequisites on other machines. `CODEX_HOME` may override the default `$HOME/.codex` skill/config directory.

REA 6.0.0 supports Node 22.19+ in the 22.x line, 24.11+ in the 24.x line, and 26+. Node 23 and 25 are unsupported. Static APK inspection needs a full JDK 17+ and `REA_JADX_MCP_JAR` pointing to the headless engine JAR. The Android provider is supported on macOS/Linux; use a supported Linux environment such as WSL for Android work on Windows. Copying the skill does not make a Windows-native Android provider available.

## Choose the appropriate route

| Question | Route |
| --- | --- |
| APK manifest, one class, one method, incoming static references | REA Android tools |
| Full source tree, broad API extraction, XAPK, JAR/AAR, alternate Java decompiler | Existing scripts in the parent Android skill |
| Runtime DEX loading, actual arguments/returns, JNI registration or native loads | Existing Frida/ADB workflow |
| Native `.so` implementation, renaming/comments, detailed native analysis | Existing direct IDA MCP or headless workflow |
| Electron/JavaScript, managed assemblies, other packaged targets | REA's companion skill and available providers |

REA's Android provider does not establish executed behavior, split-package support, signature validity, or native call relationships. For XAPK, first use the existing extraction/decompilation workflow and supply an individual APK when a focused REA query helps. Keep exact APK/library hashes when correlating REA results with Frida or IDA.

Keep a working direct IDA installation available. In REA 6.0.0, the documented attached profile targets legacy 1.4 tools, and its modern headless profile requires a database supervisor. Do not assume an `ida-pro-mcp` 2.0.0 GUI server is interchangeable with either profile. Configure and validate REA's IDA adapter separately only when needed.

## Query and verify

When MCP tools are available, use `inspect_android_package`, `search_android_classes`, `inspect_android_class`, `inspect_android_method`, and `trace_android_references` according to their advertised schemas. No native-provider session is required for these target-free tools. Inspect class metadata before selecting an ambiguous method overload.

CLI equivalents, replacing the example target and command with the machine's real paths:

```bash
rea inspect-android-package /absolute/path/app.apk --json
rea search-android-classes /absolute/path/app.apk MainActivity --json
rea inspect-android-method /absolute/path/app.apk example.MainActivity onCreate --json
```

Preserve the complete Evidence record, including artifact digest, producer, raw and normalized results, confidence, and limitations. An `observed` static result observes the decompiler's output; it does not prove runtime execution. Corroborate behavior with the parent skill's runtime workflow and byte/hash comparisons.

## Connection and maintenance

Reconnect the agent's MCP servers after first registration or configuration changes. An already-running session can use the CLI immediately. Diagnose only when needed; substitute the selected client for `codex`:

```bash
rea doctor --client codex --skill --json
```

For this Git-managed companion skill, use `--skill=false` with REA setup so it does not replace customized instructions or the skill checkout. Keep the CLI package and skill metadata aligned when intentionally upgrading REA.

In Codex's `mcp_servers.rea` entry, use the machine's supported Node executable and installed REA entry point, absolute Java/JADX paths, and a `tool_timeout_sec` of 180 for Android operations. A setup refresh may regenerate this entry; preserve unrelated MCP configuration. Missing optional Hopper/Ghidra/IDA providers do not invalidate APK or static JavaScript analysis.

The original integration was validated on macOS arm64 using a public Appium ApiDemos APK through CLI and MCP, plus a small generated native library through direct IDA. A new device still needs its own smoke check. Keep APKs, binaries, runtime traces, credentials, and complete machine configuration outside the skill repositories.
