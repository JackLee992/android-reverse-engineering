# Native `.so` Tracing

## Library load tracing

Use this to see when runtime libraries are loaded:

```bash
bash "$HOME/.codex/skills/android-reverse-engineering/scripts/run-frida-trace-loads.sh" \
  --package com.example.app \
  --output output/native-loads.jsonl
```

This hooks:

- `dlopen`
- `android_dlopen_ext`

Use the trace to identify:

- packer or anti-tamper native libraries
- business-logic `.so` files that only load after login or feature entry
- the right target library to open in IDA or match against JNI registrations

## JNI tracing

Use this to map Java method signatures to native function pointers:

```bash
bash "$HOME/.codex/skills/android-reverse-engineering/scripts/run-frida-trace-jni.sh" \
  --package com.example.app \
  --output output/jni-trace.jsonl
```

The output records:

- Java native method name
- JNI signature
- native function pointer
- module name
- module-relative offset

This is especially useful for:

- mapping obfuscated Java stubs to real native code
- identifying which `.so` contains a target native method
- creating the first list of entrypoints to inspect in IDA

## Suggested workflow

1. Trace loads to identify the interesting `.so` files.
2. Trace JNI registrations while exercising the app feature you care about.
3. Open the matching `.so` in IDA.
4. Use `ida-pro-mcp` to rename, comment, and analyze the offsets that appeared in the JNI trace.
