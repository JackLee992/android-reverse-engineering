---
name: android-reverse-engineering
description: Use when the user wants to decompile an Android APK, XAPK, JAR, or AAR, inspect obfuscated Android code, extract HTTP APIs, reproduce app behavior offline, dump runtime DEX files with Frida, trace native library or JNI activity, or hand off Android `.so` analysis into IDA Pro through MCP.
---

# Android Reverse Engineering

Decompile Android APK, XAPK, JAR, and AAR files using jadx and Fernflower/Vineflower, trace call flows through application code and libraries, and produce structured documentation of extracted APIs. Two decompiler engines are supported: jadx for broad Android coverage and Fernflower/Vineflower for higher-quality output on complex Java code. They can also be used together for comparison.

## Installation Path

This Codex packaging assumes the skill is installed at:

```bash
$HOME/.codex/skills/android-reverse-engineering
```

That is the default destination used by the bundled Codex skill installer. Use the commands below as written unless you intentionally installed the skill somewhere else.

## Prerequisites

This skill requires **Java JDK 17+** and **jadx** to be installed for the static pipeline. **Fernflower/Vineflower** and **dex2jar** are optional but recommended for better decompilation quality. Run the dependency checker to verify:

```bash
bash "$HOME/.codex/skills/android-reverse-engineering/scripts/check-deps.sh"
```

If anything is missing, follow the installation instructions in:

```text
$HOME/.codex/skills/android-reverse-engineering/references/setup-guide.md
```

For dynamic runtime analysis, also verify the Frida/ADB host environment:

```bash
bash "$HOME/.codex/skills/android-reverse-engineering/scripts/check-dynamic-deps.sh"
```

See:

```text
$HOME/.codex/skills/android-reverse-engineering/references/frida-setup.md
```

For native `.so` handoff to IDA Pro, verify local IDA and MCP readiness:

```bash
bash "$HOME/.codex/skills/android-reverse-engineering/scripts/check-ida-mcp.sh"
```

This check reports the IDA app path, `idat` readiness, `ida-pro-mcp` installation, plugin links, Codex MCP config, and whether `http://127.0.0.1:13337/mcp` is reachable.

## Workflow

### Static vs Dynamic Strategy

Default to **static first, dynamic to prove**:

- Static analysis is usually fastest for the first working map: entry points, class names, call graph, native exports, constants, catalogs, templates, and payload layouts.
- Dynamic analysis is more accurate for executed behavior: real call order, actual arguments/returns, library scanner semantics, JNI bridge effects, and whether a Python replacement already performs part of the Android transformation.
- If static and dynamic disagree, treat dynamic evidence as authoritative for the triggered input and current app build; then return to static/IDA to explain the mismatch and cover untriggered branches.

For offline reproductions such as QR/card parsers, use this closure pattern:

1. Build a static-route implementation from jadx/IDA evidence.
2. Hook the smallest meaningful runtime stages, not only final UI output. Capture function name, argument lengths, return lengths, short hex heads, and SHA-256 hashes for each stage.
3. Write a dynamic-evidence implementation independently from the static script. It may share extracted constants or catalogs when those constants come from native/static analysis, but the flow should be justified by Frida/ADB evidence.
4. Compare both implementations on the same sample with JSON field checks and byte-for-byte artifact hashes for intermediate payloads and final files.
5. Keep the dynamic trace summary and comparison test with the deliverable so future maintainers can distinguish "inferred from code" from "observed at runtime."

### Phase 1: Verify and Install Dependencies

Before decompiling, confirm that the required tools are available and install any that are missing.

**Action**: Run the dependency check script.

```bash
bash "$HOME/.codex/skills/android-reverse-engineering/scripts/check-deps.sh"
```

The output contains machine-readable lines:
- `INSTALL_REQUIRED:<dep>`: must be installed before proceeding
- `INSTALL_OPTIONAL:<dep>`: recommended but not blocking

**If required dependencies are missing** (exit code 1), install them automatically:

```bash
bash "$HOME/.codex/skills/android-reverse-engineering/scripts/install-dep.sh" <dep>
```

The install script detects the OS and package manager, then:
- Installs without sudo when possible by downloading to `~/.local/share/` and symlinking in `~/.local/bin/`
- Uses sudo and the system package manager when necessary (`apt`, `dnf`, `pacman`)
- If sudo is needed but unavailable or declined, prints the exact manual command and exits with code 2. Show those instructions to the user.

**For optional dependencies**, ask the user if they want to install them. Vineflower and dex2jar are recommended for best results.

After installation, re-run `check-deps.sh` to confirm everything is in place. Do not proceed to Phase 2 until all required dependencies are OK.

### Phase 2: Decompile

Use the decompile wrapper script to process the target file. The script supports three engines: `jadx`, `fernflower`, and `both`.

**Action**: Choose the engine and run the decompile script. The script handles APK, XAPK, JAR, and AAR files.

```bash
bash "$HOME/.codex/skills/android-reverse-engineering/scripts/decompile.sh" [OPTIONS] <file>
```

For **XAPK** files, the script automatically extracts the archive, identifies all APK files inside, and decompiles each one into a separate subdirectory. The XAPK manifest is copied to the output for reference.

Options:
- `-o <dir>`: custom output directory (default: `<filename>-decompiled`)
- `--deobf`: enable deobfuscation, recommended for obfuscated apps
- `--no-res`: skip resources and decompile code only
- `--engine ENGINE`: `jadx` (default), `fernflower`, or `both`

**Engine selection strategy**:

| Situation | Engine |
|---|---|
| First pass on any APK | `jadx` |
| JAR/AAR library analysis | `fernflower` |
| jadx output has warnings or broken code | `both` |
| Complex lambdas, generics, or streams | `fernflower` |
| Quick overview of a large APK | `jadx --no-res` |

When using `--engine both`, the outputs go into `<output>/jadx/` and `<output>/fernflower/`, with a comparison summary at the end showing file counts and jadx warning counts. Review classes with jadx warnings in the Fernflower output for better code.

For APK files with Fernflower, the script automatically uses dex2jar as an intermediate step. dex2jar must be installed for this to work.

See these local references for more detail:

```text
$HOME/.codex/skills/android-reverse-engineering/references/jadx-usage.md
$HOME/.codex/skills/android-reverse-engineering/references/fernflower-usage.md
```

### Phase 3: Analyze Structure

Navigate the decompiled output to understand the app's architecture.

**Actions**:

1. Read `AndroidManifest.xml` from `<output>/resources/AndroidManifest.xml`:
   - Identify the main launcher Activity
   - List all Activities, Services, BroadcastReceivers, and ContentProviders
   - Note permissions, especially `INTERNET` and `ACCESS_NETWORK_STATE`
   - Find the application class from `android:name` on `<application>`

2. Survey the package structure under `<output>/sources/`:
   - Identify the main app package and sub-packages
   - Distinguish app code from third-party libraries
   - Look for packages named `api`, `network`, `data`, `repository`, `service`, `retrofit`, or `http`

3. Identify the architecture pattern:
   - MVP: look for `Presenter` classes
   - MVVM: look for `ViewModel` classes and `LiveData` or `StateFlow`
   - Clean Architecture: look for `domain`, `data`, and `presentation` packages

### Phase 4: Trace Call Flows

Follow execution paths from user-facing entry points down to network calls.

**Actions**:

1. Start from entry points: read the main Activity or Application class identified in Phase 3.
2. Follow the initialization chain: `Application.onCreate()` often sets up the HTTP client, base URL, and dependency injection.
3. Trace user actions:
   - `onCreate()` -> view setup -> click listeners
   - click handler -> ViewModel or Presenter method
   - ViewModel -> Repository -> API service interface
   - API service -> actual HTTP call
4. Map DI bindings if Dagger or Hilt is used by finding `@Module` classes.
5. Handle obfuscated code by using string literals and library API calls as anchors. Retrofit annotations and URL strings are typically not obfuscated.

See:

```text
$HOME/.codex/skills/android-reverse-engineering/references/call-flow-analysis.md
```

### Phase 5: Extract and Document APIs

Find all API endpoints and produce structured documentation.

**Action**: Run the API search script for a broad sweep.

```bash
bash "$HOME/.codex/skills/android-reverse-engineering/scripts/find-api-calls.sh" <output>/sources/
```

Targeted searches:

```bash
bash "$HOME/.codex/skills/android-reverse-engineering/scripts/find-api-calls.sh" <output>/sources/ --retrofit
bash "$HOME/.codex/skills/android-reverse-engineering/scripts/find-api-calls.sh" <output>/sources/ --urls
bash "$HOME/.codex/skills/android-reverse-engineering/scripts/find-api-calls.sh" <output>/sources/ --auth
```

Then, for each discovered endpoint, read the surrounding source code to extract:
- HTTP method and path
- Base URL
- Path parameters, query parameters, and request body
- Headers, especially authentication
- Response type
- Where it is called from in the Phase 4 call chain

Document each endpoint using this format:

```markdown
### `METHOD /path`

- **Source**: `com.example.api.ApiService` (`ApiService.java:42`)
- **Base URL**: `https://api.example.com/v1`
- **Path params**: `id` (`String`)
- **Query params**: `page` (`int`), `limit` (`int`)
- **Headers**: `Authorization: Bearer <token>`
- **Request body**: `{ "email": "string", "password": "string" }`
- **Response**: `ApiResponse<User>`
- **Called from**: `LoginActivity -> LoginViewModel -> UserRepository -> ApiService`
```

See:

```text
$HOME/.codex/skills/android-reverse-engineering/references/api-extraction-patterns.md
```

### Phase 6: Dynamic Runtime Analysis (optional)

Use this branch when the app uses packers, runtime DEX loading, heavy JNI bridges, or important native `.so` logic that is not obvious from the static output.

**Runtime DEX dump**:

```bash
bash "$HOME/.codex/skills/android-reverse-engineering/scripts/run-frida-dexdump.sh" \
  --package com.example.app \
  --output-dir output/runtime-dex
```

**Trace native library loads**:

```bash
bash "$HOME/.codex/skills/android-reverse-engineering/scripts/run-frida-trace-loads.sh" \
  --package com.example.app \
  --output output/native-loads.jsonl
```

**Trace JNI registrations**:

```bash
bash "$HOME/.codex/skills/android-reverse-engineering/scripts/run-frida-trace-jni.sh" \
  --package com.example.app \
  --output output/jni-trace.jsonl
```

Use the resulting artifacts to answer questions such as:

- Which DEX files only exist in memory after startup?
- Which `.so` files load when a specific feature is exercised?
- Which native function offsets back a given Java `native` method?
- Which scanner/parser APIs return raw transport bytes versus already-normalized payload bytes?
- Which native or Java bridge function transforms the data between external input and final app-visible output?

For behavior reproduction tasks, prefer hooks that bracket semantic boundaries:

- Scanner output: e.g. ZXing `decode*` results, raw bytes, text bytes, barcode format.
- Native bridge input/output: e.g. `byte[]` lengths, fragment headers, return codes, callback emissions.
- Final artifacts: text emitted to UI/model methods, image bytes, files, network bodies, or database writes.
- Cross-checks: save small binary artifacts and hashes; avoid relying only on printed strings or UI screenshots.

See:

```text
$HOME/.codex/skills/android-reverse-engineering/references/dynamic-dex-unpack.md
$HOME/.codex/skills/android-reverse-engineering/references/native-so-tracing.md
```

### Phase 7: IDA Pro MCP Handoff (optional)

Use this branch when the native trace identifies a specific `.so` and you want Codex to analyze it inside IDA Pro through MCP.

**Action**: Run the IDA/MCP checker before attempting handoff.

```bash
bash "$HOME/.codex/skills/android-reverse-engineering/scripts/check-ida-mcp.sh"
```

If `IDA_MCP_READY:1` appears, check `IDA_IDB_OPEN`. When it is `0`, open the target `.so` first, then re-run the check. When it is `1`, use IDA MCP directly. Start with `server_health`, then `survey_binary`, then inspect offsets from Frida with `lookup_funcs`, `analyze_function`, `decompile`, `disasm`, `trace_data_flow`, and apply names or comments with `rename` and `set_comments`.

If IDA is installed but `IDA_MCP_REACHABLE:0` appears:

1. Open IDA Pro and open the target `.so`, or choose "Go" from the Quick start screen.
2. Start the plugin with `Edit -> Plugins -> MCP` or `Ctrl+Option+M` on macOS.
3. If the plugin is installed but IDA does not discover it, use the absolute-path Python console bootstrap printed by `check-ida-mcp.sh`.

When the MCP server is reachable, correlate Frida output with IDA:

- For `jni-trace.jsonl`, normalize offsets against the loaded module image base before jumping to IDA addresses.
- For `native-loads.jsonl`, confirm the exact `.so` path and ABI before opening in IDA.
- Prefer a first `survey_binary` pass over broad `list_funcs`/`imports` calls, then narrow by strings, exports, JNI names, and trace offsets.

If IDA is installed but the MCP tools are not exposed in the current Codex turn, do not block on the GUI. Use `idat` in headless mode with a focused IDAPython script:

```bash
idat -A -S/path/to/script.py /path/to/libtarget.so
```

The script should export a compact JSON report with only the needed facts: JNI/exported function names, imports, strings near the target, xrefs to constants and data blobs, decompiled text when Hex-Rays is available, and file offsets for native byte arrays. This is often enough to recover native key material, JNI bridge behavior, or payload layouts without requiring an interactive IDB.

For JNI-backed QR or card parsers:

- Compare Java scanner APIs against Python replacements before porting byte transforms. Android code may use ZXing `Result.getRawBytes()`, while Python libraries such as `zxing-cpp` may already return the decoded QR payload.
- Trace `GetByteArrayElements`, `NewByteArray`, `SetByteArrayRegion`, Java callbacks, and constants such as `1024` to understand fragment packing and RSA block boundaries.
- When a native helper reads data from another `.so`, follow imported C++ helpers into the dependency library and map VMA to file offsets with the binary's program headers before copying bytes.
- If dynamic tracing proves that Python scanner output equals a post-native-transform buffer, skip reimplementing the skipped Android transform and document that evidence in the offline script.
- Validate reconstructed output against runtime evidence: QR fragment payloads, decrypted card text, rebuilt images, and final structured fields should match by SHA-256 where possible.

See:

```text
$HOME/.codex/skills/android-reverse-engineering/references/ida-pro-mcp.md
```

## Output

At the end of the workflow, deliver:

1. Decompiled source in the output directory
2. An architecture summary covering app structure, main packages, and pattern used
3. API documentation for all discovered endpoints
4. A call-flow map for key paths from UI to network, especially authentication and main features
5. Optional runtime artifacts such as dumped DEX files, native load traces, and JNI registration traces
6. For offline reproduction tasks, a standalone script, sample input, README usage notes, and a smoke/comparison test
7. When both static and dynamic routes were used, a concise reconciliation note explaining which facts came from static code and which were observed at runtime

## References

- `$HOME/.codex/skills/android-reverse-engineering/references/setup-guide.md`
- `$HOME/.codex/skills/android-reverse-engineering/references/jadx-usage.md`
- `$HOME/.codex/skills/android-reverse-engineering/references/fernflower-usage.md`
- `$HOME/.codex/skills/android-reverse-engineering/references/api-extraction-patterns.md`
- `$HOME/.codex/skills/android-reverse-engineering/references/call-flow-analysis.md`
- `$HOME/.codex/skills/android-reverse-engineering/references/frida-setup.md`
- `$HOME/.codex/skills/android-reverse-engineering/references/dynamic-dex-unpack.md`
- `$HOME/.codex/skills/android-reverse-engineering/references/native-so-tracing.md`
- `$HOME/.codex/skills/android-reverse-engineering/references/ida-pro-mcp.md`
