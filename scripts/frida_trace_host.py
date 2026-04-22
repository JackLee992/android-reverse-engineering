#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import signal
import sys
import time
from pathlib import Path

try:
    import frida
except ImportError as exc:  # pragma: no cover - exercised in runtime environments
    raise SystemExit(
        "The `frida` Python module is required. Install it with "
        "`python3 -m pip install --user frida frida-tools`."
    ) from exc


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run a Frida tracing script against an Android app."
    )
    parser.add_argument("--script", type=Path, required=True, help="Frida JavaScript file")
    parser.add_argument("--package", help="Android package name")
    parser.add_argument("--pid", type=int, help="Attach to an existing process ID")
    parser.add_argument(
        "--mode",
        choices=("spawn", "attach"),
        default="spawn",
        help="How to connect to the target app",
    )
    parser.add_argument("--output", type=Path, help="Optional JSONL output file")
    parser.add_argument(
        "--usb-timeout-ms",
        type=int,
        default=5000,
        help="USB device lookup timeout in milliseconds",
    )
    args = parser.parse_args()

    if args.mode == "spawn" and not args.package:
        parser.error("--package is required when --mode spawn is used")
    if args.mode == "attach" and not (args.package or args.pid):
        parser.error("--package or --pid is required when --mode attach is used")
    return args


def connect_and_attach(args: argparse.Namespace):
    device = frida.get_usb_device(timeout=args.usb_timeout_ms)
    spawned_pid = None

    if args.mode == "spawn":
        spawned_pid = device.spawn([args.package])
        session = device.attach(spawned_pid)
        target_desc = f"{args.package} (spawned pid {spawned_pid})"
    elif args.pid is not None:
        session = device.attach(args.pid)
        target_desc = f"pid {args.pid}"
    else:
        session = device.attach(args.package)
        target_desc = f"{args.package} (attached)"

    return device, session, spawned_pid, target_desc


def main() -> int:
    args = parse_args()
    source = args.script.read_text(encoding="utf-8")
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)

    device, session, spawned_pid, target_desc = connect_and_attach(args)
    print(f"[INFO] Connected to {target_desc}")
    if args.output:
      print(f"[INFO] Writing JSONL trace to {args.output}")

    keep_running = True

    def write_record(payload: dict) -> None:
        if args.output is None:
            return
        with args.output.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(payload, ensure_ascii=True) + "\n")

    def on_message(message, data) -> None:
        nonlocal keep_running
        msg_type = message.get("type")
        if msg_type == "send":
            payload = message.get("payload") or {}
            event = payload.get("event", "event")
            write_record(payload)

            if event == "load":
                print(f"[LOAD] {payload.get('api')} -> {payload.get('path')}")
            elif event == "jni":
                module = payload.get("module") or "unknown"
                offset = payload.get("offset") or payload.get("fnPtr")
                print(f"[JNI] {module}!{offset} {payload.get('name')} {payload.get('signature')}")
            elif event == "hook":
                print(f"[HOOK] {payload.get('message')}")
            elif event == "warn":
                print(f"[WARN] {payload.get('message')}")
            else:
                print(f"[INFO] {json.dumps(payload, ensure_ascii=True)}")
            return

        if msg_type == "error":
            print("[ERROR] Frida script error:", file=sys.stderr)
            print(message.get("stack") or message, file=sys.stderr)
            keep_running = False

    script = session.create_script(source)
    script.on("message", on_message)
    script.load()

    if spawned_pid is not None:
        device.resume(spawned_pid)
        print("[INFO] Resumed spawned process")

    def handle_interrupt(signum, frame) -> None:  # pragma: no cover - signal path
        nonlocal keep_running
        keep_running = False

    signal.signal(signal.SIGINT, handle_interrupt)
    signal.signal(signal.SIGTERM, handle_interrupt)

    print("[INFO] Press Ctrl+C to stop tracing")
    try:
        while keep_running:
            time.sleep(0.25)
    finally:
        session.detach()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
