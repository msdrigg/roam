#!/usr/bin/env python3
"""One-off: re-capture iPad Pro 13" ar-SA portrait + landscape after RTL
NavigationSplitView fix in DeviceSplitRoot.swift. Writes to the standard
auto-screenshots cache so we can inspect with Read.

Wipes the ar-SA cache first to force a fresh capture (the schema-version
guard only invalidates on bump, but RTL Swift code changes the rendered
output without invalidating the cache).
"""

import importlib.util
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SPEC = importlib.util.spec_from_file_location(
    "sync_metadata", os.path.join(HERE, "sync-metadata.py")
)
sync_metadata = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(sync_metadata)


def main():
    device_name = "iPad Pro 13-inch (M4)"
    locale_id = "ar-SA"
    cache_root = os.path.join(tempfile.gettempdir(), "auto-screenshots")
    export_dir = os.path.join(cache_root, device_name, f"{locale_id}.export")

    # Wipe so we recapture
    if os.path.isdir(export_dir):
        print(f"Wiping {export_dir}")
        shutil.rmtree(export_dir)
    os.makedirs(export_dir, exist_ok=True)

    ScreenshotSource = sync_metadata.ScreenshotSource
    ScreenshotExport = sync_metadata.ScreenshotExport

    mm = sync_metadata.MetadataManager(
        workspace_path=".",
        screenshot_update_platforms=[sync_metadata.Platform.iOS],
    )

    # Only run iPad Pro 13"
    import types
    def _filtered(self, lid):
        device = ScreenshotSource(device=device_name, size="13")
        path = self._get_device_screenshots(device.device, lid)
        if path:
            return {sync_metadata.Platform.iOS: [ScreenshotExport(size=device.size, path=path)]}
        return {}
    mm.get_screenshots = types.MethodType(_filtered, mm)

    result = mm.get_screenshots(locale_id)
    print("\n=== Results ===")
    for platform, exports in result.items():
        for export in exports:
            print(f"  {export.path}")
            for root, _, files in os.walk(export.path):
                for fn in sorted(files):
                    if fn.lower().endswith(".png"):
                        print(f"    {os.path.join(root, fn)}")


if __name__ == "__main__":
    main()
