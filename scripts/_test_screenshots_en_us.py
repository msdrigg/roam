#!/usr/bin/env python3
"""One-shot helper to regenerate en-US screenshots for the iOS and visionOS
matrix WITHOUT touching App Store Connect. Use to validate local changes
before kicking off the full multi-locale `sync-metadata.py --sync-screenshots`
run.

Usage:
    python3 scripts/_test_screenshots_en_us.py [--platforms ios visionos]
"""

import argparse
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SPEC = importlib.util.spec_from_file_location(
    "sync_metadata", os.path.join(HERE, "sync-metadata.py")
)
sync_metadata = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(sync_metadata)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--platforms",
        nargs="+",
        default=["iOS", "visionOS"],
        choices=["iOS", "visionOS", "macOS"],
    )
    parser.add_argument(
        "--only-devices",
        nargs="*",
        default=None,
        help="If set, only run devices whose name contains one of these substrings",
    )
    args = parser.parse_args()

    platforms = [sync_metadata.Platform(p) for p in args.platforms]
    mm = sync_metadata.MetadataManager(
        workspace_path=".", screenshot_update_platforms=platforms
    )

    if args.only_devices:
        ScreenshotSource = sync_metadata.ScreenshotSource
        ScreenshotExport = sync_metadata.ScreenshotExport
        # Monkeypatch the device list to filter for the requested device(s).
        def _filtered_get_screenshots(self, locale_id):
            devices = {
                sync_metadata.Platform.iOS: [
                    ScreenshotSource(device="iPhone 17 Pro Max", size="6.9"),
                    ScreenshotSource(device="iPhone 11", size="6.5"),
                    ScreenshotSource(device="iPad Pro 13-inch (M4)", size="13"),
                ],
                sync_metadata.Platform.macOS: [
                    ScreenshotSource(device="Mac", size="desktop"),
                ],
                sync_metadata.Platform.visionOS: [
                    ScreenshotSource(device="Apple Vision Pro", size="3840_2160"),
                ],
            }
            result = {}
            for platform in self.screenshot_update_platforms:
                platform_exports = []
                for device in devices[platform]:
                    if not any(s in device.device for s in args.only_devices):
                        continue
                    screenshot_path = self._get_device_screenshots(device.device, locale_id)
                    if screenshot_path:
                        platform_exports.append(
                            ScreenshotExport(size=device.size, path=screenshot_path)
                        )
                if platform_exports:
                    result[platform] = platform_exports
            return result
        import types
        mm.get_screenshots = types.MethodType(_filtered_get_screenshots, mm)

    result = mm.get_screenshots("en-US")
    print("\n=== Results ===")
    for platform, exports in result.items():
        print(f"\n{platform}:")
        for export in exports:
            print(f"  {export.size}: {export.path}")
            if os.path.isdir(export.path):
                for root, _, files in os.walk(export.path):
                    for fn in sorted(files):
                        if fn.lower().endswith((".png", ".jpg", ".jpeg")):
                            full = os.path.join(root, fn)
                            size = os.path.getsize(full)
                            print(f"    {fn} ({size} bytes)")


if __name__ == "__main__":
    main()
