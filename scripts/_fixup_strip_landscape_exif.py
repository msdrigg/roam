#!/usr/bin/env python3
"""Strip the eXIf chunk from every LandscapePrimary PNG in the local
screenshot cache, then re-upload to App Store Connect. Apple's CDN
honors the EXIF orientation tag that `sips --rotate` injects, which is
what made iPhone (and probably iPad too) landscapes display as portrait.

Targets the iPhone 6.9", iPhone 6.5", and iPad Pro 13" sets across every
configured locale.
"""

import asyncio
import importlib.util
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SPEC = importlib.util.spec_from_file_location(
    "sync_metadata", os.path.join(HERE, "sync-metadata.py")
)
sync_metadata = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(sync_metadata)


DEVICE_TO_DISPLAY_TYPE = {
    "iPhone 17 Pro Max": "APP_IPHONE_67",
    "iPhone 11": "APP_IPHONE_65",
    "iPad Pro 13-inch (M4)": "APP_IPAD_PRO_3GEN_129",
}


async def _patch_landscape(asc, app_versions, locale_id, display_type, png_path):
    for v in app_versions:
        if v.platform != sync_metadata.Platform.iOS:
            continue
        for loc in v.localizations:
            if sync_metadata.LANGUAGE_TO_IDENTIFIER.get(loc.locale) != locale_id:
                continue
            sets = await asc.get_app_screenshot_sets(loc.id)
            target_set_id = None
            for s in sets.get("data", []):
                if s.get("attributes", {}).get(
                    "screenshotDisplayType"
                ) == display_type:
                    target_set_id = s["id"]
                    break
            if not target_set_id:
                print(f"  {locale_id} {display_type}: no set")
                return
            existing = await asc.get_app_screenshots(target_set_id)
            for shot in existing.get("data", []):
                fname = shot.get("attributes", {}).get("fileName", "")
                if "LandscapePrimary" not in fname:
                    continue
                print(
                    f"  {locale_id} {display_type}: deleting old "
                    f"{shot['id']} ({fname})"
                )
                try:
                    await asc._api_call(
                        f"{sync_metadata.BASE_API}/v1/appScreenshots/{shot['id']}",
                        method=sync_metadata.HttpMethod.DELETE,
                    )
                except Exception as e:
                    print(f"    delete error: {e}")
            print(
                f"  {locale_id} {display_type}: uploading "
                f"{os.path.basename(png_path)}"
            )
            try:
                await asc.create_app_screenshot(
                    target_set_id, os.path.basename(png_path), png_path
                )
                print(f"  {locale_id} {display_type}: upload OK")
            except Exception as e:
                print(f"  {locale_id} {display_type}: upload failed: {e}")
            return


async def amain():
    key_id = os.environ["APPSTORECONNECT_API_KEY"]
    issuer_id = os.environ["APPSTORECONNECT_API_ISSUER"]
    key_file = os.path.expanduser(f"~/.private_keys/AuthKey_{key_id}.p8")
    tm = sync_metadata.TokenManager(key_id, issuer_id, key_file)
    asc = sync_metadata.AppStoreConnect(tm, debug=False)
    app_versions = await asc.get_upcoming_app_store_versions("6469834197")

    cache_root = os.path.join(tempfile.gettempdir(), "auto-screenshots")
    for device_name, display_type in DEVICE_TO_DISPLAY_TYPE.items():
        device_root = os.path.join(cache_root, device_name)
        if not os.path.isdir(device_root):
            print(f"Skipping {device_name}: no cache dir")
            continue
        for entry in sorted(os.listdir(device_root)):
            if not entry.endswith(".export"):
                continue
            locale_id = entry[:-len(".export")]
            export_dir = os.path.join(device_root, entry)
            landscape_pngs = []
            for root, _, files in os.walk(export_dir):
                for fn in files:
                    if "LandscapePrimary" in fn and fn.lower().endswith(".png"):
                        landscape_pngs.append(os.path.join(root, fn))
            if not landscape_pngs:
                continue
            # Pick newest (most recently captured)
            png = max(landscape_pngs, key=os.path.getmtime)
            dims = sync_metadata._read_png_dimensions(png)
            if dims is None:
                print(f"  {locale_id} {device_name}: can't read dims for {png}")
                continue
            stripped = sync_metadata._strip_png_exif(png)
            tag = "[stripped eXIf]" if stripped else "[no eXIf to strip]"
            print(f"\n=== {locale_id} {device_name} {dims[0]}x{dims[1]} {tag} ===")
            await _patch_landscape(
                asc, app_versions, locale_id, display_type, png
            )


if __name__ == "__main__":
    asyncio.run(amain())
