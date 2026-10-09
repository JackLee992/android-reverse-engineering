# android-reverse-engineering

A portable **skill** for end-to-end Android reverse engineering that works in
**Codex, Claude Code, and [Hermes Agent](https://hermes-agent.nousresearch.com)**:
decompile an APK, trace call flows, extract APIs, dump runtime DEX, trace
native/JNI activity, hand `.so` files to IDA Pro, and reverse + re-implement the
crypto/parse chains hiding in native libs — with an evidence discipline for
proving your port matches the real app.

> This repo is the standalone, version-controlled copy of the skill. It is a
> self-contained `SKILL.md` directory: all commands reference `$SKILL_DIR` (the
> folder holding this `SKILL.md`), so it resolves correctly wherever each harness
> installs it. Clone it into your harness's skills dir (see below), then
> `git pull` to update across machines.

## What it does

- **Static decompilation** — jadx (broad Android coverage) and
  Fernflower/Vineflower (higher-quality Java), usable together for comparison.
- **Structure & call-flow analysis** — map packages, trace UI → network paths,
  especially auth and main features.
- **API extraction** — sweep for endpoints (Retrofit, URLs, auth headers) and
  emit structured per-endpoint docs anchored to source locations.
- **Dynamic runtime analysis** — Frida-driven DEX dumping (unpack packed apps),
  native library load tracing, and JNI registration tracing.
- **Native handoff** — push `.so` analysis into IDA Pro via MCP, or decompile
  headlessly from an existing `.i64` with idalib when no GUI/MCP is available.
- **Crypto/parse recovery** — reverse embedded/obfuscated key-derivation chains,
  re-implement them offline (Python), benchmark the port on real data, and
  validate it against the official app used as a **decryption oracle**.

## Workflow (8 phases)

1. **Verify & install dependencies** — `scripts/check-deps.sh`.
2. **Decompile** — jadx and/or Fernflower via `scripts/decompile.sh`.
3. **Analyze structure** — packages, entry points, obfuscation patterns.
4. **Trace call flows** — UI → ViewModel → repository → network.
5. **Extract & document APIs** — `scripts/find-api-calls.sh` + per-endpoint docs.
   - **5b. Proprietary payload formats & extracted-key stewardship** — reverse
     a vendor's packed binary container, and safely seal any key you extract.
6. **Dynamic runtime analysis** *(optional)* — Frida DEX dump / load / JNI trace.
7. **IDA Pro MCP handoff** *(optional)* — native `.so` deep dive.
8. **Re-implement logic + on-device benchmark** *(optional)* — port the logic,
   measure it honestly against the app's real behavior.

Phases 6–8 are optional and only kick in when the target warrants dynamic or
native work.

## Prerequisites

- **Java JDK 17+** and **jadx** (static pipeline) — required.
- **Fernflower/Vineflower** and **dex2jar** — optional, recommended.
- For dynamic work: **Frida** + **ADB** host environment (see
  `references/frida-setup.md`), and a rooted/emulator device.
- For native work: **IDA Pro** (+ optional IDA MCP server).

```bash
# verify static deps
bash scripts/check-deps.sh
# verify dynamic (Frida/ADB) deps
bash scripts/check-dynamic-deps.sh
```

Install guidance: `references/setup-guide.md`.

## Install

Clone into your harness's skills directory. The skill is a self-contained
`SKILL.md` dir and autoloads in all three:

```bash
# Hermes (categorized tree)
git clone https://github.com/JackLee992/android-reverse-engineering.git \
    ~/.hermes/skills/android/android-reverse-engineering

# Codex
git clone https://github.com/JackLee992/android-reverse-engineering.git \
    ~/.codex/skills/android-reverse-engineering

# Claude Code
git clone https://github.com/JackLee992/android-reverse-engineering.git \
    ~/.claude/skills/android-reverse-engineering
```

All in-skill paths use `$SKILL_DIR` (the folder holding `SKILL.md`), so they
resolve wherever you clone it. Update anytime with `git pull` from that dir.

## Optional REA integration and cross-device updates

REA adds structured APK queries and analysis of other application formats. This
skill remains the Android workflow for full decompilation, Frida/ADB runtime
evidence, native handoffs, and reconstruction validation. See
[the integration guide](references/rea-integration.md).

The companion, customized REA skill is maintained in
[JackLee992/reverse-engineer-anything](https://github.com/JackLee992/reverse-engineer-anything)
(private; access with the owner's GitHub account). Its README covers first-time
runtime/JADX/MCP setup; cloning skill files alone does not install those tools.

For existing Codex clones on another machine:

```bash
git -C "${CODEX_HOME:-$HOME/.codex}/skills/android-reverse-engineering" pull --ff-only
git -C "$HOME/.agents/skills/reverse-engineer-anything" pull --ff-only
```

Use that harness's actual skill directories for Claude Code or Hermes. If a
directory was installed without Git, preserve local edits and install the Git
clone before using `git pull`. Machine-specific MCP paths are configured on each
device; do not copy the whole Codex configuration between machines.

## References

| File | Topic |
|---|---|
| `setup-guide.md` | Installing jadx / Fernflower / dex2jar / Frida |
| `jadx-usage.md` | jadx decompilation patterns |
| `fernflower-usage.md` | Fernflower/Vineflower usage |
| `call-flow-analysis.md` | Tracing UI → network call chains |
| `api-extraction-patterns.md` | Finding & documenting HTTP APIs |
| `frida-setup.md` | Frida/ADB host + device setup |
| `dynamic-dex-unpack.md` | Dumping runtime DEX from packed apps |
| `native-so-tracing.md` | Native library load + JNI tracing |
| `ida-pro-mcp.md` | Driving IDA Pro through MCP |
| `ida-pro-mcp-hermes-headless.md` | Headless idalib decompile (no GUI/MCP) |
| `recover-embedded-crypto-keys.md` | Reversing embedded/obfuscated key chains |
| `reimplement-and-benchmark.md` | Porting logic + honest benchmarking |
| `native-oracle-validation.md` | App-as-oracle validation of a ported chain |
| `reverse-columnar-binary-format.md` | Reversing a vendor's packed/columnar binary |
| `sealing-extracted-secrets.md` | Safely stewarding a key extracted from an APK |
| `scan-decode-pipeline-analysis.md` | Analyzing scan/decode pipelines |
| `rea-integration.md` | REA routing, compatibility, evidence, and cross-device setup |

## Scripts

`check-deps.sh`, `check-dynamic-deps.sh`, `install-dep.sh`, `decompile.sh`,
`find-api-calls.sh`, Frida helpers (`frida_dump_dex.js`, `frida_trace_jni.js`,
`frida_trace_loads.js`, `frida_dexdump_host.py`, `frida_trace_host.py`, and their
`run-*.sh` wrappers), and `idalib_stdio_launcher.py` for headless IDA.

## Ethics & scope

For authorized reverse engineering only — your own apps, security research with
permission, interoperability, and education. Respect the target's license and
your local laws. Extracted secrets are handled under a strict no-plaintext-in-git
discipline (see `sealing-extracted-secrets.md`): ciphertext in the repo, master
key out-of-band, never commit a plaintext key.
