---
name: android-reverse-engineering
description: Use when the user wants to decompile an Android APK, XAPK, JAR, or AAR, inspect obfuscated Android code, extract HTTP APIs, dump runtime DEX files with Frida, trace native library or JNI activity, or hand off Android `.so` analysis into IDA Pro through MCP.
---

# Android Reverse Engineering

Decompile Android APK, XAPK, JAR, and AAR files using jadx and Fernflower/Vineflower, trace call flows through application code and libraries, and produce structured documentation of extracted APIs. Two decompiler engines are supported: jadx for broad Android coverage and Fernflower/Vineflower for higher-quality output on complex Java code. They can also be used together for comparison.

## Installation Path

This Codex packaging assumes the skill is installed at:

```bash
$HOME/.hermes/skills/android/android-reverse-engineering
```

That is the default destination used by the bundled Codex skill installer. Use the commands below as written unless you intentionally installed the skill somewhere else.

## Prerequisites

This skill requires **Java JDK 17+** and **jadx** to be installed for the static pipeline. **Fernflower/Vineflower** and **dex2jar** are optional but recommended for better decompilation quality. Run the dependency checker to verify:

```bash
bash "$HOME/.hermes/skills/android/android-reverse-engineering/scripts/check-deps.sh"
```

If anything is missing, follow the installation instructions in:

```text
$HOME/.hermes/skills/android/android-reverse-engineering/references/setup-guide.md
```

For dynamic runtime analysis, also verify the Frida/ADB host environment:

```bash
bash "$HOME/.hermes/skills/android/android-reverse-engineering/scripts/check-dynamic-deps.sh"
```

See:

```text
$HOME/.hermes/skills/android/android-reverse-engineering/references/frida-setup.md
```

## Workflow

### Phase 1: Verify and Install Dependencies

Before decompiling, confirm that the required tools are available and install any that are missing.

**Action**: Run the dependency check script.

```bash
bash "$HOME/.hermes/skills/android/android-reverse-engineering/scripts/check-deps.sh"
```

The output contains machine-readable lines:
- `INSTALL_REQUIRED:<dep>`: must be installed before proceeding
- `INSTALL_OPTIONAL:<dep>`: recommended but not blocking

**If required dependencies are missing** (exit code 1), install them automatically:

```bash
bash "$HOME/.hermes/skills/android/android-reverse-engineering/scripts/install-dep.sh" <dep>
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
bash "$HOME/.hermes/skills/android/android-reverse-engineering/scripts/decompile.sh" [OPTIONS] <file>
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
$HOME/.hermes/skills/android/android-reverse-engineering/references/jadx-usage.md
$HOME/.hermes/skills/android/android-reverse-engineering/references/fernflower-usage.md
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
$HOME/.hermes/skills/android/android-reverse-engineering/references/call-flow-analysis.md
```

### Phase 5: Extract and Document APIs

Find all API endpoints and produce structured documentation.

**Action**: Run the API search script for a broad sweep.

```bash
bash "$HOME/.hermes/skills/android/android-reverse-engineering/scripts/find-api-calls.sh" <output>/sources/
```

Targeted searches:

```bash
bash "$HOME/.hermes/skills/android/android-reverse-engineering/scripts/find-api-calls.sh" <output>/sources/ --retrofit
bash "$HOME/.hermes/skills/android/android-reverse-engineering/scripts/find-api-calls.sh" <output>/sources/ --urls
bash "$HOME/.hermes/skills/android/android-reverse-engineering/scripts/find-api-calls.sh" <output>/sources/ --auth
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
$HOME/.hermes/skills/android/android-reverse-engineering/references/api-extraction-patterns.md
```

### Phase 6: Dynamic Runtime Analysis (optional)

Use this branch when the app uses packers, runtime DEX loading, heavy JNI bridges, or important native `.so` logic that is not obvious from the static output.

**Runtime DEX dump**:

```bash
bash "$HOME/.hermes/skills/android/android-reverse-engineering/scripts/run-frida-dexdump.sh" \
  --package com.example.app \
  --output-dir output/runtime-dex
```

**Trace native library loads**:

```bash
bash "$HOME/.hermes/skills/android/android-reverse-engineering/scripts/run-frida-trace-loads.sh" \
  --package com.example.app \
  --output output/native-loads.jsonl
```

**Trace JNI registrations**:

```bash
bash "$HOME/.hermes/skills/android/android-reverse-engineering/scripts/run-frida-trace-jni.sh" \
  --package com.example.app \
  --output output/jni-trace.jsonl
```

Use the resulting artifacts to answer questions such as:

- Which DEX files only exist in memory after startup?
- Which `.so` files load when a specific feature is exercised?
- Which native function offsets back a given Java `native` method?

See:

```text
$HOME/.hermes/skills/android/android-reverse-engineering/references/dynamic-dex-unpack.md
$HOME/.hermes/skills/android/android-reverse-engineering/references/native-so-tracing.md
```

### Phase 7: IDA Pro MCP Handoff (optional)

Use this branch when the native trace identifies a specific `.so` and you want to analyze it inside IDA Pro through MCP.

**Hermes can be the MCP client itself** (`hermes mcp add` / `list` / `test`) — you do NOT need Codex/Claude. Two modes:
- **Headless idalib (no GUI)** — runs IDA's engine + Hex-Rays without opening the GUI. Best for automated `.so` batch analysis from the Frida pipeline; this is the verified path. Register it for **stdio auto-spawn** (Hermes launches the server on demand, no manually-started long-lived process) using the bundled launcher — upstream `idalib_server.py` only exposes streamable-HTTP on `:8745`, so `scripts/idalib_stdio_launcher.py` reuses its init but drives `MCP_SERVER.stdio()`:
  ```bash
  hermes mcp add ida-pro \
    --command "$HOME/.local/share/ida-pro-mcp-venv/bin/python" \
    --args   "$HOME/.hermes/skills/android/android-reverse-engineering/scripts/idalib_stdio_launcher.py"
  # answer "Y" to "Enable all N tools?" (interactive confirm required to save) → then START A NEW SESSION
  ```
  At runtime, one server loads any binary on demand via `idalib_open(input_path=...)` — no restart per file; the address arg for `decompile`/`disasm`/`xrefs_to` is `addr` (hex string), not `address`.
- **GUI bridge** — user opens the target in IDA, plugin serves on `:13337`, Hermes connects via the stdio `server.py` bridge. Best for interactive digging.

Key gotchas (full verified recipe in the reference below): the idalib Python module is `idapro`, not `idalib`; run `py-activate-idalib.py` once to bind idalib to the bridge venv; and **do NOT copy `ida-pro-mcp --config` verbatim** — it emits whatever `python3` is on PATH, often the wrong venv. Point the client at `~/.local/share/ida-pro-mcp-venv/bin/python`.

See:

```text
$HOME/.hermes/skills/android/android-reverse-engineering/references/ida-pro-mcp.md
$HOME/.hermes/skills/android/android-reverse-engineering/references/ida-pro-mcp-hermes-headless.md
```

### Phase 8: Re-implement Logic + On-Device Benchmark (optional)

Use this branch when the goal is not just documentation but **rebuilding the
app's logic in a fresh app** (possibly fused with a second source such as a
server codebase) and **quantifying a real on-device metric** (pass rate,
per-frame latency). Key discipline: de-risk with a **byte-parity spike on the
desktop JVM before scaffolding the app** (port pure-logic classes, compare
per-item hashes against an authoritative reference), keep the ported `.java`
literally identical between the JVM harness and the app so the fast desktop
full-set run cross-validates the phone, replicate the decompiled decode config
EXACTLY for the "app-faithful" baseline (don't chase a different engine's rate),
and drive an `androidTest` harness via `am instrument -e ...`. Covers the
Android 12+ scoped-storage gotchas (MANAGE_EXTERNAL_STORAGE grant, `run-as` to
read internal results), a pure-Java preprocessing cascade with an OOM upscale
cap, China-network Gradle build notes, PII-stripping of result CSVs, and how to
compare your rate against a reference's headline honestly by aligning the exact
filtered "qualified" denominator (search sibling `backend/`/`ref_repo/` dirs for
its id list first; note the torch/qrdet-on-new-Python install pitfall).

See:

```text
$HOME/.hermes/skills/android/android-reverse-engineering/references/reimplement-and-benchmark.md
```

## Output

At the end of the workflow, deliver:

1. Decompiled source in the output directory
2. An architecture summary covering app structure, main packages, and pattern used
3. API documentation for all discovered endpoints
4. A call-flow map for key paths from UI to network, especially authentication and main features
5. Optional runtime artifacts such as dumped DEX files, native load traces, and JNI registration traces

## References

- `$HOME/.hermes/skills/android/android-reverse-engineering/references/setup-guide.md`
- `$HOME/.hermes/skills/android/android-reverse-engineering/references/jadx-usage.md`
- `$HOME/.hermes/skills/android/android-reverse-engineering/references/fernflower-usage.md`
- `$HOME/.hermes/skills/android/android-reverse-engineering/references/api-extraction-patterns.md`
- `$HOME/.hermes/skills/android/android-reverse-engineering/references/call-flow-analysis.md`
- `$HOME/.hermes/skills/android/android-reverse-engineering/references/frida-setup.md`
- `$HOME/.hermes/skills/android/android-reverse-engineering/references/dynamic-dex-unpack.md`
- `$HOME/.hermes/skills/android/android-reverse-engineering/references/native-so-tracing.md`
- `$HOME/.hermes/skills/android/android-reverse-engineering/references/ida-pro-mcp.md`
- `$HOME/.hermes/skills/android/android-reverse-engineering/references/ida-pro-mcp-hermes-headless.md`
- `$HOME/.hermes/skills/android/android-reverse-engineering/references/recover-embedded-crypto-keys.md` — reverse a native lib's key-derivation chain (embedded/obfuscated keys, Chilkat orchestrators, NEON deobfuscation, two-layer "latch" RSA) and replicate it offline in Python; evidence discipline for real-vs-synthetic verification; plus **reverse-validation via the official app as a decryption oracle** (public-key swap by Frida hook vs APK repackage) to prove the assembly+decrypt+parse chain when you lack real private keys / signed samples.
- `$HOME/.hermes/skills/android/android-reverse-engineering/references/reimplement-and-benchmark.md`
- `$HOME/.hermes/skills/android/android-reverse-engineering/references/native-oracle-validation.md` — validate a reversed decrypt/parse chain by using the official app as a decryption oracle. Covers: (1b) driving REAL inputs through the app with NO key-swap when keys are app-embedded — invoke the private native decode method via the Java bridge (`Azf.$new().pc(activity, ArrayList<byte[]>, z)`, grab Activity from ActivityThread, reproduce the Java caller's post-processing), then field-for-field diff your port vs the app to catch fidelity bugs (e.g. trailing padding-space); (2) public-key swap + sig-verify bypass via Frida native hooks; the self-consistency round-trip fallback; native-only jstring reading through the JNIEnv vtable; Frida 16-vs-17 Java-bridge parity; MIUI attach-by-label; and the recon green-lights to check before committing.