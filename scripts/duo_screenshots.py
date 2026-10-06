#!/usr/bin/env python3
"""Capture iPhone Duo App Store screenshots with `simctl`.

The Duo has two displays (outer 1398x2034, inner 2853x2007) and `simctl`
cannot fold the device, so capture is two passes. Fold the simulator in
Device Hub, run with `--display outer`, unfold it, run with `--display inner`.
The posture buttons are the three on the right of Device Hub's bottom toolbar.

Captures land in the cache `sync-metadata.py` reads, so the upload is:

    python scripts/sync-metadata.py --platform iOS --sync-screenshots --only-devices Duo
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import struct
import subprocess
import sys
import tempfile
import time
import uuid

BUNDLE_ID = "com.msdrigg.roam"
DEVICE_NAME = "iPhone Duo"
DISPLAY_SIZES = {"outer": (1398, 2034), "inner": (2007, 2853)}

# Every locale the iOS listing ships in, matching LANGUAGE_TO_IDENTIFIER in
# sync-metadata.py.
ALL_LOCALES = [
    "en-US", "ar-SA", "fr-FR", "fr-CA", "de-DE", "it", "es-ES", "es-MX",
    "pt-PT", "pt-BR", "vi", "zh-Hans",
]

# A web link on the simulator clipboard brings up the copied-video offer and
# its tip over the remote. Settings shows the toggle, so it keeps the default.
NO_PASTE_OFFER = ["-disablePastedUrlSuggestions", "YES"]

# (index, name, launch args, captured). Indices match RoamScreenshotTests so
# the shots sort the same way as the other devices. The split view's loaders
# race the launch-time seed, so one pane renders stale data; the seed launch
# is not captured and the others reopen the seeded database with
# -ScreenshotTesting alone. There is no ScreenScanning shot: a Duo launch is
# slow enough that discovery finds whatever real TVs share the Mac's network
# before the first frame.
STATES = [
    (0, "Seed", ["-DataTesting", "-DataLoadTestingData", "-ScreenshotTesting"], False),
    (1, "Primary", ["-ScreenshotTesting", *NO_PASTE_OFFER], True),
    (5, "KeyboardOpen", ["-ScreenshotTesting", "-OpenKeyboard", *NO_PASTE_OFFER], True),
    (7, "Settings", ["-ScreenshotTesting", "-OpenSettings"], True),
]

# Launches on the Duo simulator take anywhere from a few seconds to a minute
# before the first frame, so wait for content and then let animations settle.
FIRST_FRAME_TIMEOUT = 150
SETTLE_SECONDS = 6


def simctl(*args: str, check: bool = True, timeout: float = 60) -> str:
    proc = subprocess.run(
        ["xcrun", "simctl", *args], capture_output=True, text=True, timeout=timeout
    )
    if check and proc.returncode != 0:
        raise RuntimeError(f"simctl {' '.join(args)} failed: {proc.stderr.strip()}")
    return proc.stdout


def find_udid(name: str) -> str:
    devices = json.loads(simctl("list", "devices", "available", "-j"))["devices"]
    for runtime_devices in devices.values():
        for device in runtime_devices:
            if device["name"] == name:
                return device["udid"]
    raise SystemExit(
        f"No simulator named {name!r}. Create one with:\n"
        f"  xcrun simctl create {name!r} com.apple.CoreSimulator.SimDeviceType.iPhone-Duo "
        "com.apple.CoreSimulator.SimRuntime.iOS-27-1"
    )


def display_uuid(udid: str, display: str) -> str:
    """UUIDs change on every boot, so look the framebuffer up by size."""
    width, height = DISPLAY_SIZES[display]
    output = simctl("io", udid, "enumerate")
    for block in re.split(r"\n(?=\s*UUID:)", output):
        if f"Default width: {width}" in block and f"Default height: {height}" in block:
            match = re.search(r"UUID: (\S+)", block)
            if match:
                return match.group(1)
    raise SystemExit(f"No {width}x{height} {display} display on {udid}")


def find_app() -> str:
    derived_data = os.path.expanduser("~/Library/Developer/Xcode/DerivedData")
    candidates = [
        os.path.join(derived_data, entry, "Build/Products/Debug-iphonesimulator/Roam.app")
        for entry in os.listdir(derived_data)
        if entry.startswith("Roam-")
    ]
    candidates = [c for c in candidates if os.path.isdir(c)]
    if not candidates:
        raise SystemExit("No Debug-iphonesimulator Roam.app found; run with --build")
    return max(candidates, key=os.path.getmtime)


def build_app() -> None:
    subprocess.run(
        [
            "xcodebuild", "build", "-project", "Roam.xcodeproj", "-scheme", "Roam",
            "-configuration", "Debug",
            "-destination", f"platform=iOS Simulator,name={DEVICE_NAME}",
            "-quiet",
        ],
        check=True,
    )


def frame_stats(png_path: str) -> tuple[float, float, str]:
    """Mean and spread of a 32px thumbnail, plus a digest to spot repeats.

    `sips` is the only image tool guaranteed on a Mac; a 24-bit BMP keeps the
    pixel read trivial.
    """
    with tempfile.TemporaryDirectory() as tmp:
        bmp = os.path.join(tmp, "thumb.bmp")
        subprocess.run(
            ["sips", "-s", "format", "bmp", "-z", "32", "32", png_path, "--out", bmp],
            capture_output=True,
            check=True,
        )
        data = open(bmp, "rb").read()
    offset = struct.unpack_from("<I", data, 10)[0]
    bits = struct.unpack_from("<H", data, 28)[0]
    stride = bits // 8
    pixels = data[offset:]
    values = [
        sum(pixels[i : i + 3]) / 3 for i in range(0, len(pixels) - stride + 1, stride)
    ]
    mean = sum(values) / len(values)
    spread = (sum((v - mean) ** 2 for v in values) / len(values)) ** 0.5
    return mean, spread, hashlib.sha1(pixels).hexdigest()


def is_blank(png_path: str) -> bool:
    _, spread, _ = frame_stats(png_path)
    return spread < 4


def screenshot(udid: str, display_id: str, out_path: str) -> None:
    simctl("io", udid, "screenshot", f"--display={display_id}", out_path)


def wait_for_content(udid: str, display_id: str, scratch: str) -> None:
    probe = os.path.join(scratch, "probe.png")
    deadline = time.monotonic() + FIRST_FRAME_TIMEOUT
    while time.monotonic() < deadline:
        time.sleep(3)
        screenshot(udid, display_id, probe)
        if not is_blank(probe):
            time.sleep(SETTLE_SECONDS)
            return
    print(f"  Warning: no content after {FIRST_FRAME_TIMEOUT}s, capturing anyway")


def export_dir(locale: str) -> str:
    return os.path.join(
        tempfile.gettempdir(), "auto-screenshots", DEVICE_NAME, f"{locale}.export", DEVICE_NAME
    )


def prepare_device(udid: str, app_path: str) -> None:
    state = simctl("list", "devices", "-j")
    if f'"udid" : "{udid}"' in state and '"state" : "Booted"' not in state:
        simctl("boot", udid, check=False)
    simctl("bootstatus", udid, "-b", timeout=300)
    simctl("ui", udid, "appearance", "dark")
    simctl(
        "status_bar", udid, "override", "--time", "9:41", "--batteryState", "charged",
        "--batteryLevel", "100", "--wifiBars", "3", "--cellularBars", "4",
    )
    simctl("install", udid, app_path, timeout=300)


def capture_locale(udid: str, display: str, display_id: str, locale: str) -> int:
    out_dir = export_dir(locale)
    os.makedirs(out_dir, exist_ok=True)
    suffix = display.capitalize()
    for existing in os.listdir(out_dir):
        if existing.startswith(locale) and f"{suffix}_" in existing:
            os.remove(os.path.join(out_dir, existing))

    locale_args = ["-AppleLanguages", f"({locale})", "-AppleLocale", locale.replace("-", "_")]
    captured = 0
    with tempfile.TemporaryDirectory() as scratch:
        for index, name, args, keep in STATES:
            simctl("terminate", udid, BUNDLE_ID, check=False)
            time.sleep(1)
            simctl("launch", udid, BUNDLE_ID, *locale_args, *args)
            wait_for_content(udid, display_id, scratch)
            if not keep:
                continue
            path = os.path.join(
                out_dir, f"{locale}{index}{name}{suffix}_0_{uuid.uuid4().hex.upper()}.png"
            )
            screenshot(udid, display_id, path)
            if is_blank(path):
                os.remove(path)
                print(f"  {locale} {name}: blank frame, skipped")
                continue
            captured += 1
            print(f"  {locale} {name}: {os.path.basename(path)}")
    simctl("terminate", udid, BUNDLE_ID, check=False)
    return captured


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument(
        "--display", choices=sorted(DISPLAY_SIZES), required=True,
        help="outer with the simulator folded, inner with it open",
    )
    parser.add_argument(
        "--locales", default="en-US",
        help="comma-separated BCP-47 ids, or 'all' (default: en-US)",
    )
    parser.add_argument(
        "--build", action="store_true", help="build the Debug simulator app first"
    )
    args = parser.parse_args()

    os.chdir(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    locales = ALL_LOCALES if args.locales == "all" else [
        x.strip() for x in args.locales.split(",") if x.strip()
    ]

    if args.build:
        build_app()
    udid = find_udid(DEVICE_NAME)
    prepare_device(udid, find_app())
    display_id = display_uuid(udid, args.display)

    # The inactive display stays black, which is how a wrong posture shows.
    with tempfile.TemporaryDirectory() as scratch:
        simctl("launch", udid, BUNDLE_ID, "-DataTesting", *NO_PASTE_OFFER)
        wait_for_content(udid, display_id, scratch)
        probe = os.path.join(scratch, "posture.png")
        screenshot(udid, display_id, probe)
        if is_blank(probe):
            other = "open" if args.display == "inner" else "folded"
            raise SystemExit(
                f"The {args.display} display is dark. Set the {other} posture in "
                "Device Hub and run again."
            )

    total = 0
    for locale in locales:
        print(f"Capturing {args.display} display for {locale}")
        total += capture_locale(udid, args.display, display_id, locale)
    print(f"Captured {total} {args.display} screenshot(s) for {len(locales)} locale(s)")
    if total == 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
