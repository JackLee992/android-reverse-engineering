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
bash "$HOME/.codex/skills/android-reverse-engineering/scripts/check-dynamic-deps.sh"
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
- Frida version mismatches between host and device are a common source of errors.
- The dynamic skill scripts fail clearly when the Frida host environment is missing; fix the host first, then the device.
