#!/usr/bin/env python3
"""Download the currently-uploaded App Store Connect screenshots so we can
visually inspect what Apple actually has on file (vs what we generated
locally). Saves to ~/Desktop/asc-screenshots/<platform>/<locale>/<displayType>/.

Filenames keep the ASC-side fileName so it's obvious which capture is which.

Usage:
    python3 scripts/_download_uploaded_screenshots.py [--locales en-US fr-FR]
"""

import argparse
import asyncio
import importlib.util
import os
import sys
from urllib.parse import urlparse

HERE = os.path.dirname(os.path.abspath(__file__))
SPEC = importlib.util.spec_from_file_location(
    "sync_metadata", os.path.join(HERE, "sync-metadata.py")
)
sync_metadata = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(sync_metadata)


async def _download(client, url: str, dest: str):
    r = await client.get(url, timeout=60, follow_redirects=True)
    r.raise_for_status()
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    with open(dest, "wb") as f:
        f.write(r.content)


async def _amain(locale_filter: list[str] | None):
    import httpx

    key_id = os.environ["APPSTORECONNECT_API_KEY"]
    issuer_id = os.environ["APPSTORECONNECT_API_ISSUER"]
    key_file = os.path.expanduser(f"~/.private_keys/AuthKey_{key_id}.p8")
    tm = sync_metadata.TokenManager(key_id, issuer_id, key_file)
    asc = sync_metadata.AppStoreConnect(tm, debug=False)
    app_versions = await asc.get_upcoming_app_store_versions("6469834197")

    desktop_root = os.path.expanduser("~/Desktop/asc-screenshots")
    os.makedirs(desktop_root, exist_ok=True)

    async with httpx.AsyncClient() as client:
        for v in app_versions:
            for loc in v.localizations:
                locale_id = sync_metadata.LANGUAGE_TO_IDENTIFIER.get(loc.locale)
                if locale_filter and locale_id not in locale_filter:
                    continue
                print(f"\n{v.platform} / {locale_id}")
                sets = await asc.get_app_screenshot_sets(loc.id)
                for s in sets.get("data", []):
                    dt = s.get("attributes", {}).get(
                        "screenshotDisplayType", "unknown"
                    )
                    sid = s["id"]
                    shots = await asc.get_app_screenshots(sid)
                    for shot in shots.get("data", []):
                        attrs = shot.get("attributes", {})
                        fn = attrs.get("fileName", f"{shot['id']}.png")
                        urls = (attrs.get("imageAsset") or {}).get(
                            "templateUrl"
                        )
                        if not urls:
                            print(f"    {dt}/{fn}: no templateUrl")
                            continue
                        # templateUrl uses {w}x{h}{f} substitutions — request
                        # the full-res source by asking for huge dims; ASC
                        # returns the original asset when w/h exceed it.
                        full_url = urls.replace("{w}", "10000") \
                            .replace("{h}", "10000") \
                            .replace("{f}", "png")
                        dest = os.path.join(
                            desktop_root,
                            str(v.platform),
                            locale_id,
                            dt,
                            fn,
                        )
                        if os.path.exists(dest):
                            continue
                        try:
                            await _download(client, full_url, dest)
                            print(f"    {dt}/{fn}")
                        except Exception as e:
                            print(f"    {dt}/{fn}: download failed: {e}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--locales", nargs="*",
        help="Locale IDs to download (default: all)",
    )
    args = parser.parse_args()
    asyncio.run(_amain(args.locales))


if __name__ == "__main__":
    main()
