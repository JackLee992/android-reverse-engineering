# Frida Setup

## What you need

Host side:

- `adb`
- a working Python interpreter with the `frida` module
- ideally `frida` CLI from `frida-tools`

Device side:

- Android device or emulator visible through `adb`
- a matching `frida-server` running on the device

## Host installation

Install the Frida Python package and CLI into a user-local environment:

```bash
python3 -m pip install --user frida frida-tools
```

If your working interpreter is not `python3`, set:

```bash
export FRIDA_PYTHON=/absolute/path/to/python-with-frida
```

Then verify:

```bash
bash "$HOME/.hermes/skills/android/android-reverse-engineering/scripts/check-dynamic-deps.sh"
```

## Device setup

1. Download a `frida-server` build that matches your device ABI and host Frida version.
2. Push it to the device:

```bash
adb push frida-server /data/local/tmp/frida-server
adb shell chmod 755 /data/local/tmp/frida-server
```

3. Start it on the device:

```bash
adb shell /data/local/tmp/frida-server &
```

Rooted workflows often use:

```bash
adb shell su -c /data/local/tmp/frida-server
```

## Notes

- For many protected apps you will need root or another supported injection path.
- Frida version mismatches between host and device are a common source of errors. Host `frida` pip version MUST match the device `frida-server` version exactly.
- The dynamic skill scripts fail clearly when the Frida host environment is missing; fix the host first, then the device.

## Frida 17+ removed the bundled Java/ObjC bridge (important)

Starting with Frida 17, the `Java` and `ObjC` globals are NO LONGER in the core runtime — they were split into separate `frida-java-bridge` / `frida-objc-bridge` npm packages. A bare `session.create_script("Java.perform(...)")` throws `ReferenceError: 'Java' is not defined`. Symptoms: hooks that only touch native code work fine, but any Java-layer hook errors out immediately.

Three ways around it, cheapest first:
1. **Native-only hooking** — if the values you care about are C strings / byte buffers at the JNI boundary (very common for obfuscated crypto apps), skip Java entirely. Resolve `Module.findBaseAddress("libX.so")`, add IDA file offsets, and `Interceptor.attach`. Read `jstring` args through the JNIEnv vtable (see `native-oracle-validation.md`). No download, no bridge.
2. **Bundle the bridge with frida-compile** — `npm i frida-java-bridge`, `import Java from "frida-java-bridge"`, compile with `frida-compile`. Needs npm network access.
3. **Downgrade host+server to 16.x** — `pip install frida==16.x` plus a matching 16.x `frida-server` binary on device. Needs a GitHub-release download (often blocked on China networks; keep a local copy).

## Getting frida-server / connecting (field-tested)

- Check the device first — a prior session may have already pushed it: `adb shell su -c 'ls -la /data/local/tmp/ | grep frida'`. Reusing an existing `frida-server-<ver>` avoids a slow GitHub download entirely.
- GitHub release assets for frida-server are often unreachable/truncated on China networks (gh-proxy mirrors return 0 bytes or partial `.xz`). Verify with `xz -t` before trusting; prefer an on-device copy.
- Start rooted: `adb shell su -c '/data/local/tmp/frida-server-<ver> &'`.
- **Attach by process LABEL, not package id.** `dev.attach("com.pkg.id")` fails with `unable to find process`; the process name Frida sees is the app's display label (e.g. `"Valida INE-QR"`). Enumerate with `dev.enumerate_processes()` and match on `p.name`.
- `dev.spawn(["pkg.id"])` can fail with `NotSupportedError: unable to find application` on MIUI when the launch intent isn't resolvable — launch via `adb shell monkey -p pkg -c android.intent.category.LAUNCHER 1` then attach to the running pid.

## MIUI / HyperOS install bypass (INSTALL_FAILED_USER_RESTRICTED)

Sideloading a split APK / XAPK on MIUI often fails with `INSTALL_FAILED_USER_RESTRICTED: Install canceled by user`. Two fixes that work with root:
- Disguise the install source as Play Store: `pm install -i com.android.vending --user 0 ...`.
- For multi-split XAPK, push all splits to `/data/local/tmp` and use a root `pm install-create` / `install-multi-package` session. Install ALL required splits (base + `config.arm64_v8a` + a language split + a density split); a base-only install "succeeds" but the launcher activity silently won't exist (`Activity class ... does not exist` on launch). Verify with `pm path <pkg>` showing base + splits before launching.
