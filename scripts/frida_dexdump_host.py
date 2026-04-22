#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import re
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
        description="Dump runtime dex files from an Android app using Frida."
    )
    parser.add_argument("--package", help="Android package name")
    parser.add_argument("--pid", type=int, help="Attach to an existing process ID")
    parser.add_argument(
        "--mode",
        choices=("spawn", "attach"),
        default="spawn",
        help="How to connect to the target app",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        help="Local output directory for dumped dex files",
    )
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
    if args.output_dir is None:
      timestamp = time.strftime("%Y%m%d-%H%M%S")
      args.output_dir = Path.cwd() / "output" / f"runtime-dex-{timestamp}"

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
    output_dir = args.output_dir
    output_dir.mkdir(parents=True, exist_ok=True)
    index_path = output_dir / "dex-dump-index.jsonl"
    script_path = Path(__file__).with_name("frida_dump_dex.js")
    source = script_path.read_text(encoding="utf-8")

    device, session, spawned_pid, target_desc = connect_and_attach(args)
    print(f"[INFO] Connected to {target_desc}")
    print(f"[INFO] Dump directory: {output_dir}")

    seen_hashes: set[str] = set()
    keep_running = True

    def write_index(payload: dict, filename: str) -> None:
        record = dict(payload)
        record["filename"] = filename
        with index_path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(record, ensure_ascii=True) + "\n")

    def on_message(message, data) -> None:
        nonlocal keep_running
        msg_type = message.get("type")
        if msg_type == "send":
            payload = message.get("payload") or {}
            event = payload.get("event")

            if event in {"status", "hook", "warn"}:
                prefix = {
                    "status": "[INFO]",
                    "hook": "[HOOK]",
                    "warn": "[WARN]",
                }[event]
                print(f"{prefix} {payload.get('message', '')}")
                return

            if event == "dex_dump":
                if not data:
                    print("[WARN] Received dex dump metadata without bytes")
                    return

                sha1 = hashlib.sha1(data).hexdigest()
                if sha1 in seen_hashes:
                    print(f"[INFO] Skipping duplicate DEX ({sha1[:12]})")
                    return
                seen_hashes.add(sha1)

                source_label = payload.get("source", "dex")
                source_label = re.sub(r"[^A-Za-z0-9_.-]+", "_", source_label).strip("_")
                source_label = source_label or "dex"
                target_name = f"{source_label}-{len(data)}-{sha1[:12]}.dex"
                target_path = output_dir / target_name
                target_path.write_bytes(data)

                write_index(payload, target_name)
                print(f"[DEX] Saved {target_path}")
                return

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

    print("[INFO] Press Ctrl+C when enough DEX files have been dumped")
    try:
        while keep_running:
            time.sleep(0.25)
    finally:
        session.detach()

    print(f"[INFO] Wrote index: {index_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
