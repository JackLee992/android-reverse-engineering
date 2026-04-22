# Dynamic DEX Unpack

This workflow is inspired by the `dstmath/frida-unpack` approach, but the Codex skill writes dumped DEX files directly to the host machine instead of relying on app-private files under `/data/data/<pkg>/`.

## When to use it

Use runtime DEX dumping when:

- static APK extraction shows only loader stubs
- the app unpacks protected DEX files after startup
- you need the decrypted code that only exists in memory

## Basic flow

1. Check host and device prerequisites:

```bash
bash "$HOME/.codex/skills/android-reverse-engineering/scripts/check-dynamic-deps.sh"
```

2. Spawn the app and dump any DEX files seen by ART:

```bash
bash "$HOME/.codex/skills/android-reverse-engineering/scripts/run-frida-dexdump.sh" \
  --package com.example.app \
  --output-dir output/runtime-dex
```

3. Wait for the app to load its protected code, then press `Ctrl+C`.

4. Review the index:

```text
output/runtime-dex/dex-dump-index.jsonl
```

5. Feed the dumped DEX files back into `jadx` or `Fernflower/Vineflower`.

## Hook points

The script probes common ART DEX loader paths:

- `art::DexFile::OpenMemory`
- `art::DexFileLoader::OpenCommon`

If these hooks do not trigger on your target, inspect the target Android version and expand the symbol list.
