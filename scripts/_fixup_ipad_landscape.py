#!/usr/bin/env python3
"""Recapture + re-upload iPad LandscapePrimary screenshots for locales whose
landscape capture failed during the main `sync-metadata.py --sync-screenshots`
run. Uses the improved `_boot_sim_and_open_window` (which now quits
Simulator + shuts down all sims + polls the Device → Orientation menu) so
the osascript menu click is reliable.

Reads the main sync log to find locales that need the fix, runs the iPad
landscape capture for each, then PATCHes the single LandscapePrimary
screenshot into the existing iPad set without touching any other
screenshots.

Usage:
    python3 scripts/_fixup_ipad_landscape.py --log <path-to-main-sync.log>
    python3 scripts/_fixup_ipad_landscape.py --locales en-US fr-FR ...
"""

import argparse
import asyncio
import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SPEC = importlib.util.spec_from_file_location(
    "sync_metadata", os.path.join(HERE, "sync-metadata.py")
)
sync_metadata = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(sync_metadata)


def _failing_locales_from_log(log_path: str) -> list[str]:
    """Scan the main sync log for iPad landscape failures and return the
    list of locale IDs (as the script writes them: 'en-US', 'fr-FR', ...).
    """
    fail_pat = re.compile(r"Capturing iPad landscape via menu rotation for (\S+)")
    ok_pat = re.compile(
        r"Captured iPad landscape \(pre-rotation\) for (\S+)"
    )
    timeout_pat = re.compile(
        r"UI tests for iPad Pro 13-inch \(M4\) in (\S+) were killed"
    )

    attempted: list[str] = []
    successful: set[str] = set()
    timed_out: set[str] = set()
    with open(log_path) as f:
        for line in f:
            m = fail_pat.search(line)
            if m:
                attempted.append(m.group(1))
                continue
            m = ok_pat.search(line)
            if m:
                successful.add(m.group(1))
                continue
            m = timeout_pat.search(line)
            if m:
                timed_out.add(m.group(1))

    failed = [
        loc for loc in attempted
        if loc not in successful and loc not in timed_out
    ]
    # XCTest timeouts also need a retry — for those we'll just rebuild the
    # iPad set from scratch.
    failed.extend(loc for loc in timed_out)
    seen = set()
    deduped = []
    for loc in failed:
        if loc not in seen:
            seen.add(loc)
            deduped.append(loc)
    return deduped


async def _patch_ipad_landscape(asc, app_versions, locale_id: str, png_path: str):
    """Upload `png_path` as the LandscapePrimary into the iOS app version's
    iPad screenshot set for `locale_id`. Leaves all other iPad screenshots
    in place — we only delete + re-upload the existing LandscapePrimary
    entries (matched by filename containing 'LandscapePrimary')."""
    for app_version in app_versions:
        if app_version.platform != sync_metadata.Platform.iOS:
            continue
        for loc in app_version.localizations:
            mapped = sync_metadata.LANGUAGE_TO_IDENTIFIER.get(loc.locale)
            if mapped != locale_id:
                continue
            sets = await asc.get_app_screenshot_sets(loc.id)
            ipad_set_id = None
            for s in sets.get("data", []):
                if s.get("attributes", {}).get(
                    "screenshotDisplayType"
                ) == "APP_IPAD_PRO_3GEN_129":
                    ipad_set_id = s["id"]
                    break
            if ipad_set_id is None:
                print(f"  {locale_id}: no APP_IPAD_PRO_3GEN_129 set; skipping")
                return
            existing = await asc.get_app_screenshots(ipad_set_id)
            for shot in existing.get("data", []):
                fname = shot.get("attributes", {}).get("fileName", "")
                if "LandscapePrimary" not in fname:
                    continue
                sid = shot["id"]
                print(f"  {locale_id}: deleting old landscape {sid} ({fname})")
                try:
                    await asc._api_call(
                        f"{sync_metadata.BASE_API}/v1/appScreenshots/{sid}",
                        method=sync_metadata.HttpMethod.DELETE,
                    )
                except Exception as e:
                    print(f"    error deleting: {e}")
            print(f"  {locale_id}: uploading {os.path.basename(png_path)}")
            try:
                await asc.create_app_screenshot(
                    ipad_set_id, os.path.basename(png_path), png_path
                )
                print(f"  {locale_id}: upload OK")
            except Exception as e:
                print(f"  {locale_id}: upload failed: {e}")
            return


async def _amain(locales: list[str]):
    key_id = os.environ["APPSTORECONNECT_API_KEY"]
    issuer_id = os.environ["APPSTORECONNECT_API_ISSUER"]
    key_file = os.path.expanduser(f"~/.private_keys/AuthKey_{key_id}.p8")
    tm = sync_metadata.TokenManager(key_id, issuer_id, key_file)
    asc = sync_metadata.AppStoreConnect(tm, debug=False)
    app_versions = await asc.get_upcoming_app_store_versions("6469834197")

    import tempfile
    cache_root = os.path.join(tempfile.gettempdir(), "auto-screenshots")
    device_name = "iPad Pro 13-inch (M4)"

    for locale_id in locales:
        print(f"\n=== {locale_id} ===")
        export_dir = os.path.join(cache_root, device_name, f"{locale_id}.export")
        os.makedirs(export_dir, exist_ok=True)

        # Wipe any previously-captured landscape file so the fresh
        # capture is the only one the post-rotation pass picks up.
        for root, _, files in os.walk(export_dir):
            for fn in files:
                if "LandscapePrimary" in fn and fn.lower().endswith(".png"):
                    try:
                        os.remove(os.path.join(root, fn))
                    except OSError:
                        pass

        # Recapture iPad landscape using the improved boot logic.
        ok = sync_metadata._capture_ipad_landscape_via_simctl(
            device_name=device_name,
            locale_id=locale_id,
            export_dir=export_dir,
        )
        if not ok:
            print(f"  {locale_id}: capture still failed — skipping upload")
            continue

        # Find the captured PNG and run the sips rotation that the main
        # script would have done.
        landscape_pngs = []
        for root, _, files in os.walk(export_dir):
            for fn in files:
                if "LandscapePrimary" in fn and fn.lower().endswith(".png"):
                    landscape_pngs.append(os.path.join(root, fn))
        if not landscape_pngs:
            print(f"  {locale_id}: no LandscapePrimary file after capture")
            continue
        png = max(landscape_pngs, key=os.path.getmtime)
        dims = sync_metadata._read_png_dimensions(png)
        if dims is None:
            print(f"  {locale_id}: can't read dims for {png}")
            continue
        if dims[0] < dims[1]:
            import subprocess
            rot = subprocess.run(
                ["sips", "--rotate", "270", png, "--out", png],
                capture_output=True,
            )
            if rot.returncode != 0:
                print(f"  {locale_id}: sips rotate failed")
                continue
            dims = sync_metadata._read_png_dimensions(png)
        if dims is None or not sync_metadata._dimensions_match(
            dims, "APP_IPAD_PRO_3GEN_129"
        ):
            print(f"  {locale_id}: rotated dims {dims} don't match iPad slot")
            continue

        await _patch_ipad_landscape(asc, app_versions, locale_id, png)


_ALL_IOS_LOCALES = [
    "en-US", "ar-SA", "fr-FR", "fr-CA", "de-DE", "it",
    "es-ES", "es-MX", "pt-PT", "pt-BR", "vi", "zh-Hans",
]


def main():
    parser = argparse.ArgumentParser()
    g = parser.add_mutually_exclusive_group(required=True)
    g.add_argument("--log", help="Parse this main-sync log for failing locales")
    g.add_argument("--locales", nargs="+", help="Explicit list of locale IDs")
    g.add_argument("--all", action="store_true", help="Re-do all 12 iOS locales")
    args = parser.parse_args()

    if args.all:
        locales = _ALL_IOS_LOCALES
        print(f"Re-running iPad landscape for all locales: {locales}")
    elif args.log:
        locales = _failing_locales_from_log(args.log)
        if not locales:
            print(f"No failing iPad locales found in {args.log}")
            sys.exit(0)
        print(f"Failing locales from log: {locales}")
    else:
        locales = args.locales

    asyncio.run(_amain(locales))


if __name__ == "__main__":
    main()
