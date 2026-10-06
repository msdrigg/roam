#!/usr/bin/env python3

import argparse
import atexit
import enum
import gzip
import hashlib
import json
import os
import re
import shlex
import shutil
import struct
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from datetime import datetime, timedelta

import httpx
import jwt
from httpx import AsyncClient, Response

# Sibling module - pulled in lazily inside `_get_or_create_tart_vm` so the
# rest of the script still imports cleanly on machines without tart/sshpass
# installed (e.g. when only running metadata sync, no screenshot capture).
_THIS_DIR = os.path.dirname(os.path.abspath(__file__))
if _THIS_DIR not in sys.path:
    sys.path.insert(0, _THIS_DIR)

# The script now supports:
# 2. Running UI tests to capture screenshots and uploading them to App Store Connect
#
# Usage examples:
# - To sync metadata only: python sync-metadata.py --platform iOS macOS visionOS
# - To sync metadata and screenshots: python sync-metadata.py --platform iOS macOS visionOS --sync-screenshots
#
# For screenshots, the script will:
# 1. Run Xcode UI tests for each configured device and locale
# 2. Extract screenshots using xcparse
# 3. Upload the screenshots to App Store Connect


ALGORITHM = "ES256"
BASE_API = "https://api.appstoreconnect.apple.com"


class HttpMethod(enum.IntEnum):
    GET = 1
    POST = 2
    PATCH = 3
    DELETE = 4


class APIError(Exception):
    def __init__(self, error_string, status_code=None):
        try:
            self.status_code = int(status_code)
        except (ValueError, TypeError):
            pass
        super().__init__(error_string)


class TokenManager:
    _token: str | None = None

    key_id: str
    issuer_id: str
    key_file: str

    def __init__(self, key_id: str, issuer_id: str, key_file: str):
        self.key_id = key_id
        self.issuer_id = issuer_id
        self.key_file = key_file

        # generate the first token
        self.token

    @property
    def token(self) -> str:
        # generate a new token every 15 minutes
        if (self._token is None) or (
            self.token_gen_date + timedelta(minutes=15) < datetime.now()
        ):
            self._token = self._generate_token()

        return self._token

    def _generate_token(self) -> str:
        try:
            key = open(self.key_file, "r").read()
        except IOError as e:
            print("Error reading the key file: ", e)
            key = self.key_file
        self.token_gen_date = datetime.now()
        exp = int(
            time.mktime((self.token_gen_date + timedelta(minutes=20)).timetuple())
        )
        return jwt.encode(
            {"iss": self.issuer_id, "exp": exp, "aud": "appstoreconnect-v1"},
            key,
            headers={"kid": self.key_id, "typ": "JWT"},
            algorithm=ALGORITHM,
        )


class AppStoreConnect:
    def __init__(self, token_manager: TokenManager, debug=False):
        self.token_manager = token_manager
        self._debug = debug
        self.timeout = 60

    @property
    def token(self):
        return self.token_manager.token

    async def _api_call(self, url, method=HttpMethod.GET, post_data=None):
        headers = {"Authorization": "Bearer %s" % self.token}
        if self._debug:
            print("%s %s" % (method.value, url))

        try:
            if method == HttpMethod.GET:
                async with AsyncClient() as client:
                    r: Response = await client.get(
                        url, headers=headers, timeout=self.timeout
                    )
            elif method == HttpMethod.POST:
                headers["Content-Type"] = "application/json"
                async with AsyncClient() as client:
                    r: Response = await client.post(
                        url=url,
                        headers=headers,
                        data=json.dumps(post_data),
                        timeout=self.timeout,
                    )
            elif method == HttpMethod.PATCH:
                headers["Content-Type"] = "application/json"
                async with AsyncClient() as client:
                    r: Response = await client.patch(
                        url=url,
                        headers=headers,
                        data=json.dumps(post_data),
                        timeout=self.timeout,
                    )
            elif method == HttpMethod.DELETE:
                async with AsyncClient() as client:
                    r: Response = await client.delete(
                        url=url, headers=headers, timeout=self.timeout
                    )
            else:
                raise APIError("Unknown HTTP method")
        except httpx.TimeoutException:
            raise APIError(f"Read timeout after {self.timeout} seconds")

        if self._debug:
            print(r.status_code)

        content_type = r.headers.get("content-type")

        if content_type in ["application/json", "application/vnd.api+json"]:
            print(r.text)
            payload = r.json()
            if "errors" in payload:
                raise APIError(
                    payload.get("errors", [])[0].get("detail", "Unknown error"),
                    payload.get("errors", [])[0].get("status", None),
                )
            return payload
        elif content_type == "application/a-gzip":
            data = gzip.decompress(r.content)
            return data.decode("utf-8")
        else:
            if not 200 <= r.status_code <= 299:
                raise APIError(
                    "HTTP error [%d][%s]" % (r.status_code, r.content.decode("utf-8"))
                )
            return r

    async def get_upcoming_app_store_versions(
        self, app_id: str
    ) -> list["AppStoreVersion"]:
        url = f"{BASE_API}/v1/apps/{app_id}/appStoreVersions?filter[appStoreState]=PREPARE_FOR_SUBMISSION&include=appStoreVersionLocalizations&fields[apps]=&fields[appStoreVersionLocalizations]=locale&limit[appStoreVersionLocalizations]=50"
        data = await self._api_call(url, method=HttpMethod.GET)

        # Map localization ID to its attributes for easy lookup
        localizations_lookup = {
            loc["id"]: loc["attributes"]["locale"]
            for loc in data.get("included", [])
            if loc["type"] == "appStoreVersionLocalizations"
        }

        app_store_versions = []

        for item in data.get("data", []):
            if item["type"] == "appStoreVersions":
                version_id = item["id"]
                platform = item["attributes"]["platform"]

                # Get localization IDs related to this version
                localization_ids = [
                    loc["id"]
                    for loc in item["relationships"]
                    .get("appStoreVersionLocalizations", {})
                    .get("data", [])
                ]

                # Create AppVersionLocalization objects
                localizations = [
                    AppVersionLocalization(
                        locale=Language.from_locale(localizations_lookup[loc_id]),
                        id=loc_id,
                    )
                    for loc_id in localization_ids
                    if loc_id in localizations_lookup
                ]

                # Add AppStoreVersion object to the list
                app_store_versions.append(
                    AppStoreVersion(
                        platform=Platform.from_app_store_platform(platform),
                        id=version_id,
                        localizations=localizations,
                    )
                )

        return app_store_versions

    async def update_localization(self, localization_id: str, data: dict):
        """
        Data should be in the format:
        {
            "whatsNew": "Localized whats new"
        }
        """
        url = f"{BASE_API}/v1/appStoreVersionLocalizations/{localization_id}"
        request_json = {
            "data": {
                "type": "appStoreVersionLocalizations",
                "id": localization_id,
                "attributes": data,
            }
        }

        response = await self._api_call(
            url, method=HttpMethod.PATCH, post_data=request_json
        )
        return response

    async def get_app_screenshot_sets(self, localization_id: str):
        """
        Get the screenshot sets for a specific localization.
        """
        url = f"{BASE_API}/v1/appStoreVersionLocalizations/{localization_id}/appScreenshotSets"
        response = await self._api_call(url, method=HttpMethod.GET)
        return response

    async def create_app_screenshot_set(
        self, localization_id: str, screenshot_display_type: str
    ):
        """
        Create a new screenshot set for a specific localization and display type.

        Args:
            localization_id (str): The ID of the app store version localization
            screenshot_display_type (str): The display type (e.g., "APP_IPHONE_69", "APP_IPAD_PRO_3GEN_129")

        Returns:
            dict: The created screenshot set
        """
        url = f"{BASE_API}/v1/appScreenshotSets"
        request_json = {
            "data": {
                "type": "appScreenshotSets",
                "attributes": {"screenshotDisplayType": screenshot_display_type},
                "relationships": {
                    "appStoreVersionLocalization": {
                        "data": {
                            "type": "appStoreVersionLocalizations",
                            "id": localization_id,
                        }
                    }
                },
            }
        }

        response = await self._api_call(
            url, method=HttpMethod.POST, post_data=request_json
        )
        return response

    async def delete_app_screenshot_set(self, screenshot_set_id: str):
        """
        Delete a screenshot set.

        Args:
            screenshot_set_id (str): The ID of the screenshot set to delete
        """
        url = f"{BASE_API}/v1/appScreenshotSets/{screenshot_set_id}"
        response = await self._api_call(url, method=HttpMethod.DELETE)
        return response

    async def get_app_screenshots(self, screenshot_set_id: str):
        """
        Get all screenshots in a screenshot set.

        Args:
            screenshot_set_id (str): The ID of the screenshot set

        Returns:
            dict: The screenshots in the set
        """
        url = f"{BASE_API}/v1/appScreenshotSets/{screenshot_set_id}/appScreenshots"
        response = await self._api_call(url, method=HttpMethod.GET)
        return response

    async def create_app_screenshot(
        self, screenshot_set_id: str, filename: str, file_path: str
    ):
        """
        Create a new screenshot and upload the file to App Store Connect.

        Args:
            screenshot_set_id (str): The ID of the screenshot set
            filename (str): The name of the screenshot file
            file_path (str): The path to the screenshot file

        Returns:
            dict: The created screenshot
        """
        # Get file size
        file_size = os.path.getsize(file_path)

        # Reserve the screenshot
        reserve_url = f"{BASE_API}/v1/appScreenshots"
        request_json = {
            "data": {
                "type": "appScreenshots",
                "attributes": {"fileName": filename, "fileSize": file_size},
                "relationships": {
                    "appScreenshotSet": {
                        "data": {"type": "appScreenshotSets", "id": screenshot_set_id}
                    }
                },
            }
        }

        reserve_response = await self._api_call(
            reserve_url, method=HttpMethod.POST, post_data=request_json
        )

        # Extract upload operations and reservation ID
        upload_operations = (
            reserve_response.get("data", {})
            .get("attributes", {})
            .get("uploadOperations", [])
        )
        screenshot_id = reserve_response.get("data", {}).get("id")

        if not upload_operations or not screenshot_id:
            raise APIError("Failed to reserve screenshot upload")

        # Upload the screenshot chunks
        with open(file_path, "rb") as f:
            file_data = f.read()

        # Calculate MD5 checksum for the entire file
        md5_hash = hashlib.md5(file_data).hexdigest()

        # Upload each chunk
        for operation in upload_operations:
            url = operation.get("url")
            method = operation.get("method")
            headers = operation.get("requestHeaders", [])
            offset = operation.get("offset", 0)
            length = operation.get("length", 0)

            # Extract chunk data
            chunk_data = file_data[offset : offset + length]

            # Convert headers list to dictionary
            headers_dict = {
                header.get("name"): header.get("value") for header in headers
            }

            # Create a temporary file for the chunk
            with tempfile.NamedTemporaryFile(delete=False) as temp_file:
                temp_file.write(chunk_data)
                temp_path = temp_file.name

            upload_command = [
                "curl",
                "-X",
                method,
                "--fail-with-body",
                "--silent",
                "--show-error",
            ]
            for header_name, header_value in headers_dict.items():
                upload_command.extend(["-H", f"{header_name}: {header_value}"])
            upload_command.extend(["--data-binary", f"@{temp_path}", url])

            try:
                result = subprocess.run(upload_command, capture_output=True)
            finally:
                os.unlink(temp_path)

            if result.returncode != 0:
                stderr = result.stderr.decode("utf-8", errors="replace")
                stdout = result.stdout.decode("utf-8", errors="replace")
                raise APIError(
                    f"Failed to upload screenshot chunk (exit {result.returncode}): {stderr or stdout}"
                )

        # Commit the screenshot
        commit_url = f"{BASE_API}/v1/appScreenshots/{screenshot_id}"
        commit_json = {
            "data": {
                "type": "appScreenshots",
                "id": screenshot_id,
                "attributes": {"sourceFileChecksum": md5_hash, "uploaded": True},
            }
        }

        commit_response = await self._api_call(
            commit_url, method=HttpMethod.PATCH, post_data=commit_json
        )
        return commit_response


class Platform(enum.StrEnum):
    iOS = "iOS"
    macOS = "macOS"
    visionOS = "visionOS"

    @classmethod
    def from_app_store_platform(cls, platform: str) -> "Platform":
        mapping = {
            "IOS": cls.iOS,
            "MAC_OS": cls.macOS,
            "VISION_OS": cls.visionOS,
        }

        if platform in mapping:
            return mapping[platform]

        raise ValueError(f"Unknown platform: {platform}")


class Language(enum.StrEnum):
    en = "en"
    ar = "ar"
    fr = "fr"
    fr_CA = "fr-CA"
    de = "de"
    it = "it"
    es = "es"
    es_419 = "es-419"
    pt_PT = "pt-PT"
    pt_BR = "pt-BR"
    vi = "vi"
    zh_Hans = "zh-Hans"

    @classmethod
    def from_locale(cls, locale: str) -> "Language":
        mapping = {
            "en": cls.en,
            "en-US": cls.en,
            "ar": cls.ar,
            "ar-SA": cls.ar,
            "fr": cls.fr,
            "fr-FR": cls.fr,
            "fr-CA": cls.fr_CA,
            "de": cls.de,
            "de-DE": cls.de,
            "it": cls.it,
            "es": cls.es,
            "es-ES": cls.es,
            "es-419": cls.es_419,
            "es-MX": cls.es_419,
            "pt-PT": cls.pt_PT,
            "pt-BR": cls.pt_BR,
            "vi": cls.vi,
            "zh-Hans": cls.zh_Hans,
        }

        if locale in mapping:
            return mapping[locale]

        raise ValueError(f"Unknown locale: {locale}")


# Maps internal Language enum values to the full BCP-47 identifiers expected by
# both `xcodebuild -testLanguage` and the Swift test bundle (which constructs
# Locale(identifier:) from these strings).
LANGUAGE_TO_IDENTIFIER: dict[Language, str] = {
    Language.en: "en-US",
    Language.ar: "ar-SA",
    Language.fr: "fr-FR",
    Language.fr_CA: "fr-CA",
    Language.de: "de-DE",
    Language.it: "it",
    Language.es: "es-ES",
    Language.es_419: "es-MX",
    Language.pt_PT: "pt-PT",
    Language.pt_BR: "pt-BR",
    Language.vi: "vi",
    Language.zh_Hans: "zh-Hans",
}


# Apple's accepted screenshot dimensions per `screenshotDisplayType`. These are
# the canonical sizes the App Store Connect API will accept; uploads of other
# sizes are rejected. Each entry lists every accepted (width, height) tuple.
DISPLAY_TYPE_DIMENSIONS: dict[str, list[tuple[int, int]]] = {
    # 6.5"/6.7"/6.9" iPhones all upload to APP_IPHONE_67 (Apple has not
    # introduced a 6.9-specific slot - APP_IPHONE_69 is rejected by ASC).
    # Accepts both the iPhone 14/15 Pro Max dims and the iPhone 16/17 Pro Max
    # dims, in portrait or landscape.
    "APP_IPHONE_67": [(1290, 2796), (2796, 1290), (1320, 2868), (2868, 1320)],
    # Legacy 6.5" iPhone slot (XS Max / 11 Pro Max). Apple keeps this slot
    # available even after introducing 6.7"/6.9". A plain iPhone 11 sim
    # produces 828x1792 (6.1" dims) which does NOT match - the matching
    # simulator is "iPhone 11 Pro Max" (1242x2688). The 12-15 Pro Max sims
    # render at 1284x2778, also accepted here.
    "APP_IPHONE_65": [(1242, 2688), (2688, 1242), (1284, 2778), (2778, 1284)],
    # 12.9"/13" iPad Pro slot - Apple accepts both the legacy 12.9" dims and
    # the 13" M4's native render.
    "APP_IPAD_PRO_3GEN_129": [(2048, 2732), (2732, 2048), (2064, 2752), (2752, 2064)],
    # One iPhone Duo slot takes both the outer (1398x2034) and the inner
    # (2007x2853) display sizes.
    "APP_IPHONE_DUO": [(1398, 2034), (2034, 1398), (2007, 2853), (2853, 2007)],
    # Apple Watch Series 10 / 11 (46mm) - same display
    "APP_WATCH_SERIES_10": [(416, 496), (496, 416)],
    "APP_WATCH_ULTRA": [(410, 502), (502, 410)],
    "APP_APPLE_VISION_PRO": [(3840, 2160)],
    "APP_DESKTOP": [
        (1280, 800),
        (1440, 900),
        (2560, 1600),
        (2880, 1800),
    ],
}


@dataclass
class AppVersionLocalization:
    locale: Language
    id: str


@dataclass
class AppStoreVersion:
    platform: Platform
    id: str
    localizations: list[AppVersionLocalization]


@dataclass
class LocalizedField:
    ios: dict[Language, str]
    vision_os: dict[Language, str]
    mac_os: dict[Language, str]

    def get_value(self, locale: Language, platform: Platform) -> str | None:
        if platform == Platform.iOS:
            return self.ios[locale]
        elif platform == Platform.visionOS:
            return self.vision_os[locale]
        elif platform == Platform.macOS:
            return self.mac_os[locale]
        else:
            return None


@dataclass
class LocalizedMetadata:
    whats_new: LocalizedField
    description: LocalizedField

    def get_update(self, locale: Language, platform: Platform) -> dict[str, str]:
        if not self.whats_new.get_value(locale, platform):
            raise ValueError(f"Missing localized whats new for {platform} and {locale}")
        if not self.description.get_value(locale, platform):
            raise ValueError(
                f"Missing localized description for {platform} and {locale}"
            )

        return {
            "whatsNew": self.whats_new.get_value(locale, platform),
            "description": self.description.get_value(locale, platform),
        }


# Bump whenever the set of captured states, the launch arg shape, or the
# capture pipeline changes in a way that makes a cached export from a
# prior run invalid. The cache directory writes this stamp; on each run
# the cache is wiped if it doesn't match. Prevents the cache hit at
# `_get_*_screenshots` from returning stale files when the pipeline has
# moved on (e.g. switching macOS from xcresult-recovery to direct app
# launch, or adding new visionOS Keyboard/Settings states).
SCREENSHOT_SCHEMA_VERSION = "2026-05-28-v6-tart"


def _ensure_cache_schema(cache_root: str) -> None:
    """Wipe `cache_root` if its schema-version stamp doesn't match the
    current `SCREENSHOT_SCHEMA_VERSION`. Writes the stamp after wiping
    (or creating) the directory."""
    stamp_path = os.path.join(cache_root, ".schema-version")
    existing = None
    if os.path.isfile(stamp_path):
        try:
            with open(stamp_path) as f:
                existing = f.read().strip()
        except OSError:
            existing = None
    if existing == SCREENSHOT_SCHEMA_VERSION:
        return
    if os.path.isdir(cache_root):
        print(
            f"Wiping screenshot cache at {cache_root} (schema "
            f"{existing!r} → {SCREENSHOT_SCHEMA_VERSION!r})"
        )
        shutil.rmtree(cache_root)
    os.makedirs(cache_root, exist_ok=True)
    with open(stamp_path, "w") as f:
        f.write(SCREENSHOT_SCHEMA_VERSION)


@dataclass
class ScreenshotSource:
    device: str
    size: str


@dataclass
class ScreenshotExport:
    size: str
    path: str


def _read_png_dimensions(path: str) -> tuple[int, int] | None:
    """Read width and height from a PNG file's IHDR chunk without external deps."""
    try:
        with open(path, "rb") as f:
            signature = f.read(8)
            if signature != b"\x89PNG\r\n\x1a\n":
                return None
            f.read(4)  # IHDR length
            chunk_type = f.read(4)
            if chunk_type != b"IHDR":
                return None
            width, height = struct.unpack(">II", f.read(8))
            return (width, height)
    except (OSError, struct.error):
        return None


def _dimensions_match(dims: tuple[int, int], display_type: str) -> bool:
    accepted = DISPLAY_TYPE_DIMENSIONS.get(display_type, [])
    return dims in accepted


def _strip_png_exif(path: str) -> bool:
    """Strip any `eXIf` chunk from a PNG so downstream consumers
    (Finder/Preview/App Store Connect's CDN) use only the IHDR pixel
    dimensions for display, not the embedded EXIF orientation flag.

    `sips --rotate` rotates the actual pixel data AND inserts an EXIF
    orientation tag that compensates (rotating LandscapeLeft pixels 90°
    CW writes Orientation=6, "rotate 90° CW for display"). The compensation
    means EXIF-aware viewers re-rotate back to the original portrait
    layout, defeating the purpose of the sips rotation entirely. Apple's
    ASC CDN does the same, which is why our landscape iPhone uploads were
    being served as 1320x2868 portrait with sideways content.

    Returns True if a chunk was stripped, False if no eXIf chunk existed.
    """
    with open(path, "rb") as fh:
        data = fh.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        return False
    out = bytearray(data[:8])
    i = 8
    stripped = False
    while i + 8 <= len(data):
        length = int.from_bytes(data[i : i + 4], "big")
        ctype = data[i + 4 : i + 8]
        chunk_total = 12 + length  # length + type + data + crc
        if ctype == b"eXIf":
            stripped = True
        else:
            out.extend(data[i : i + chunk_total])
        i += chunk_total
        if ctype == b"IEND":
            break
    if stripped:
        with open(path, "wb") as fh:
            fh.write(out)
    return stripped


def _recover_pngs_from_xcresult_data(
    xcresult_path: str, export_path: str, locale_id: str
) -> int:
    """
    Scan an xcresult bundle's Data directory for files starting with the
    PNG magic signature and copy them into export_path with names that
    `_collect_locale_screenshots` recognizes. Used on macOS where xcodebuild
    reliably hangs post-test, leaving the bundle's Info.plist unwritten so
    xcparse refuses to read it - but the screenshot attachments themselves
    are written to Data/ as raw blobs by the test.

    Files are sorted by mtime (capture order), then assigned the same
    `{locale}{index}{name}_0_{UUID}` naming the test would have used:
      - 1st captured → ScreenScanning (index 4)
      - 2nd captured → Primary        (index 1)
      - 3rd captured → LandscapePrimary (index 3)

    The index values match the convention in RoamScreenshotTests.swift so
    the collector returns Primary > LandscapePrimary > ScreenScanning in
    display order.

    Returns the number of PNGs recovered.
    """
    import uuid as _uuid

    data_dir = os.path.join(xcresult_path, "Data")
    if not os.path.isdir(data_dir):
        return 0

    png_magic = b"\x89PNG\r\n\x1a\n"
    pngs: list[tuple[float, str]] = []
    for entry in os.listdir(data_dir):
        full = os.path.join(data_dir, entry)
        if not os.path.isfile(full):
            continue
        try:
            with open(full, "rb") as f:
                if f.read(8) != png_magic:
                    continue
        except OSError:
            continue
        pngs.append((os.path.getmtime(full), full))

    if not pngs:
        return 0

    pngs.sort(key=lambda t: t[0])

    # (index, name) for each captured-in-order PNG. Mirrors the order in
    # RoamScreenshotTests.swift's macOS branch. Extras (if any) are
    # appended with sequential high indices so they're still uploadable.
    name_plan: list[tuple[int, str]] = [
        (4, "ScreenScanning"),
        (1, "Primary"),
        (3, "LandscapePrimary"),
    ]
    while len(name_plan) < len(pngs):
        name_plan.append((10 + len(name_plan), f"Extra{len(name_plan)}"))

    os.makedirs(export_path, exist_ok=True)
    out_subdir = os.path.join(export_path, "Mac")
    os.makedirs(out_subdir, exist_ok=True)
    for (idx, name), (_, src) in zip(name_plan, pngs):
        uid = _uuid.uuid4().hex.upper()
        dst = os.path.join(out_subdir, f"{locale_id}{idx}{name}_0_{uid}.png")
        shutil.copyfile(src, dst)

    return len(pngs)


def _rotate_simulator_via_menu(orientation: str) -> bool:
    """Click Simulator.app's Device → Orientation → <orientation> menu via
    osascript to rotate the booted device. Unlike Cmd+→ which only flips
    the host window, the menu click sends a true device-level orientation
    change that the iOS/iPadOS scene actually responds to (the iPad scene
    re-lays out in landscape proportions).

    `orientation` must be one of: "Portrait", "Landscape Left",
    "Landscape Right", "Portrait Upside Down".

    Requires Accessibility permission for the process driving osascript.
    """
    if orientation not in {
        "Portrait",
        "Landscape Left",
        "Landscape Right",
        "Portrait Upside Down",
    }:
        raise ValueError(f"Unknown orientation: {orientation}")
    script = (
        'tell application "Simulator" to activate\n'
        "delay 0.5\n"
        'tell application "System Events"\n'
        '    tell process "Simulator"\n'
        f'        click menu item "{orientation}" of menu "Orientation"'
        ' of menu item "Orientation" of menu "Device" of menu bar 1\n'
        "    end tell\n"
        "end tell\n"
    )
    proc = subprocess.run(["osascript", "-e", script], capture_output=True)
    if proc.returncode != 0:
        stderr = proc.stderr.decode("utf-8", errors="replace")
        print(f"  Warning: simulator rotate ({orientation!r}) failed: {stderr}")
        return False
    return True


def _resolve_device_udid_by_name(device_name: str) -> str | None:
    """Look up the UDID of an available simulator matching `device_name`
    regardless of boot state. Picks the newest-runtime entry on a tie."""
    proc = subprocess.run(
        ["xcrun", "simctl", "list", "devices", "available", "--json"],
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        return None
    try:
        data = json.loads(proc.stdout)
    except (json.JSONDecodeError, ValueError):
        return None
    matches: list[tuple[str, str]] = []
    for runtime_key, devices in data.get("devices", {}).items():
        for device in devices:
            if device.get("name") == device_name and device.get("isAvailable"):
                matches.append((runtime_key, device.get("udid")))
    if not matches:
        return None
    matches.sort(reverse=True)
    return matches[0][1]


def _boot_sim_and_open_window(udid: str) -> bool:
    """Quit Simulator.app, shutdown all other booted sims, boot the target
    device, open Simulator focused on it, and wait for the Device menu's
    Orientation submenu to be reachable via System Events. Without the full
    teardown the Simulator app frequently ends up in a state where its
    `menu bar 1 → Device → Orientation` menu item can't be found by
    osascript (-1728), even though Simulator is visibly open - typically
    after xcodebuild's cloned sim is torn down."""
    # Quit Simulator.app to clear any stale menu state from cloned devices
    # left over by `xcodebuild test`.
    subprocess.run(
        ["osascript", "-e", 'tell application "Simulator" to quit'],
        capture_output=True,
    )
    time.sleep(1.0)

    # Shutdown anything still booted so the next boot is the only one,
    # and Simulator's CurrentDevice argument resolves unambiguously.
    subprocess.run(
        ["xcrun", "simctl", "shutdown", "all"],
        capture_output=True,
    )
    time.sleep(1.0)

    boot_proc = subprocess.run(
        ["xcrun", "simctl", "boot", udid],
        capture_output=True,
    )
    if boot_proc.returncode != 0:
        stderr = boot_proc.stderr.decode("utf-8", errors="replace")
        if "Booted" not in stderr:
            print(f"  Warning: simctl boot failed for {udid}: {stderr}")
            return False

    subprocess.run(
        ["open", "-a", "Simulator", "--args", "-CurrentDeviceUDID", udid],
        capture_output=True,
    )
    subprocess.run(
        ["xcrun", "simctl", "bootstatus", udid, "-b"],
        capture_output=True,
        timeout=180,
    )

    # Poll for the Device → Orientation menu to be reachable. Without
    # this the very first menu click after Simulator's window appears
    # races with menubar population and fails with -1728.
    probe_script = (
        'tell application "System Events" to tell process "Simulator" to '
        'exists menu item "Orientation" of menu "Device" of menu bar 1'
    )
    deadline = time.time() + 30.0
    while time.time() < deadline:
        proc = subprocess.run(
            ["osascript", "-e", probe_script],
            capture_output=True,
            text=True,
        )
        if proc.returncode == 0 and proc.stdout.strip() == "true":
            time.sleep(0.5)  # one extra beat for the submenu to be clickable
            return True
        time.sleep(1.0)
    print(
        f"  Warning: Simulator's Device → Orientation menu never appeared "
        f"for {udid} after 30s - proceeding anyway"
    )
    return True


def _capture_ipad_landscape_via_simctl(
    device_name: str,
    locale_id: str,
    export_dir: str,
    bundle_id: str = "com.msdrigg.roam",
) -> bool:
    """
    iPad-specific landscape capture. iPad apps that aren't
    UIRequiresFullScreen can't force their own orientation
    (`requestGeometryUpdate(.landscapeLeft)` silently no-ops), so we drive
    the orientation system-side: rotate the booted sim via
    Simulator.app's Device → Orientation → Landscape Left menu, let the
    iPad scene re-lay out in real landscape proportions, then capture via
    `simctl io booted screenshot`.

    The captured framebuffer is still portrait pixel dims (the sim
    framebuffer doesn't follow device orientation), so the caller must
    sips-rotate the file 270° to produce landscape pixel dims with the
    content right-side-up. Returns True if a file was successfully written.
    """
    import uuid as _uuid

    udid = _resolve_device_udid_by_name(device_name)
    if udid is None:
        print(
            f"  Skipping landscape for {device_name}/{locale_id}: "
            f"no simulator named {device_name!r} available"
        )
        return False

    if not _boot_sim_and_open_window(udid):
        return False

    derived_data = os.path.expanduser("~/Library/Developer/Xcode/DerivedData")
    candidates: list[str] = []
    if os.path.isdir(derived_data):
        for entry in os.listdir(derived_data):
            if entry.startswith("Roam-"):
                candidate = os.path.join(
                    derived_data,
                    entry,
                    "Build",
                    "Products",
                    "Debug-iphonesimulator",
                    "Roam.app",
                )
                if os.path.isdir(candidate):
                    candidates.append(candidate)
    if not candidates:
        print(f"  No Debug-iphonesimulator Roam.app for {device_name} landscape")
        return False
    app_path = max(candidates, key=os.path.getmtime)

    landscape_subdir = os.path.join(export_dir, f"{device_name} (landscape)")
    os.makedirs(landscape_subdir, exist_ok=True)

    underscore_locale = locale_id.replace("-", "_")
    common_args = [
        "-AppleLanguages",
        f"({locale_id})",
        "-AppleLocale",
        underscore_locale,
    ]

    # Ensure we start from portrait so the rotation menu actually triggers
    # a transition (clicking Landscape Left from Landscape Left is a no-op).
    _rotate_simulator_via_menu("Portrait")
    time.sleep(1.0)

    subprocess.run(
        ["xcrun", "simctl", "terminate", udid, bundle_id],
        capture_output=True,
    )
    time.sleep(0.5)
    install_proc = subprocess.run(
        ["xcrun", "simctl", "install", udid, app_path],
        capture_output=True,
    )
    if install_proc.returncode != 0:
        stderr = install_proc.stderr.decode("utf-8", errors="replace")
        print(f"  Warning: simctl install failed for iPad landscape ({stderr})")
        return False

    try:
        launch_proc = subprocess.run(
            [
                "xcrun",
                "simctl",
                "launch",
                udid,
                bundle_id,
                *common_args,
                "-DataTesting",
                "-DataLoadTestingData",
                "-ScreenshotTesting",
            ],
            capture_output=True,
        )
        if launch_proc.returncode != 0:
            stderr = launch_proc.stderr.decode("utf-8", errors="replace")
            print(f"  Warning: simctl launch failed for iPad landscape: {stderr}")
            return False

        # Wait for the app to render its initial portrait scene fully -
        # blocking data load (~1s) + PhoneHomeView -> DeviceSplitRoot
        # appear + DeviceLoader populate + initial layout. RTL locales
        # (Arabic) take noticeably longer for the SwiftUI layout pass to
        # finish. A short wait here means the rotation transition collides
        # with the still-in-flight initial-layout pass and the captured
        # frame is half portrait-rotated-90°, half landscape.
        time.sleep(10.0)

        if not _rotate_simulator_via_menu("Landscape Left"):
            return False

        # Pixel-stability poll: take screenshots ~1s apart until THREE in
        # a row match byte-for-byte, then use that frame. iPad split-view's
        # landscape transition runs ~0.3s after the orientation change but
        # the SwiftUI re-layout (sidebar slides in, detail expands, app
        # links re-flow) keeps re-rendering for another 2-4s; RTL locales
        # add another second or two. Requiring 3 consecutive identical
        # frames (=2s stable) before accepting cuts down on the "we
        # caught two duplicate transient frames" false-positive that 1
        # stable frame produced under ar-SA.
        import hashlib as _hashlib

        fn = f"{locale_id}3LandscapePrimary_0_{_uuid.uuid4().hex.upper()}.png"
        out_path = os.path.join(landscape_subdir, fn)
        prev_hash = None
        stable_count = 0
        max_attempts = 25  # 25s budget post-rotation
        for attempt in range(max_attempts):
            time.sleep(1.0)
            shot_proc = subprocess.run(
                ["xcrun", "simctl", "io", udid, "screenshot", out_path],
                capture_output=True,
            )
            if shot_proc.returncode != 0 or not os.path.exists(out_path):
                continue
            with open(out_path, "rb") as f:
                cur_hash = _hashlib.md5(f.read()).hexdigest()
            if cur_hash == prev_hash:
                stable_count += 1
                if stable_count >= 2:
                    break
            else:
                stable_count = 0
            prev_hash = cur_hash
        if not os.path.exists(out_path):
            print(
                f"  Warning: simctl screenshot failed for iPad landscape "
                f"({device_name}/{locale_id})"
            )
            return False
        print(
            f"  Captured iPad landscape (pre-rotation) for {locale_id} "
            f"({fn}) after {attempt + 1} stability polls"
        )
        subprocess.run(
            ["xcrun", "simctl", "terminate", udid, bundle_id],
            capture_output=True,
        )
        time.sleep(0.5)
        return True
    finally:
        # Restore portrait so the next test/run starts from a known state.
        _rotate_simulator_via_menu("Portrait")
        time.sleep(0.5)


def _collect_locale_screenshots(
    export_path: str, locale_id: str, max_count: int = 10
) -> list[str]:
    """
    Walk an xcparse export tree and return image paths matching a given locale.

    `xcparse screenshots --os --model` flattens attachment names: the test
    attaches a screenshot named "en-US/3/LandscapePrimary" and xcparse writes
    it as `<os>/<model>/en-US3LandscapePrimary_0_<UUID>.png` - the slashes are
    *deleted*, not turned into directories. We match by the locale prefix +
    numeric index encoded into the basename, and sort by that index.

    Returns up to `max_count` paths.
    """
    pattern = re.compile(
        rf"^{re.escape(locale_id)}(\d+)(.+?)_\d+_[0-9A-Fa-f-]+\.(?:png|jpg|jpeg)$"
    )
    found: list[tuple[int, str, str]] = []
    for root, _, files in os.walk(export_path):
        for filename in files:
            match = pattern.match(filename)
            if not match:
                continue
            order = int(match.group(1))
            name = match.group(2)
            full = os.path.join(root, filename)
            found.append((order, name, full))
    found.sort(key=lambda t: (t[0], t[1]))
    return [path for _, _, path in found[:max_count]]


# ---------- Tart-backed macOS capture helpers ----------

# Cached across all (locale, state) calls inside one script run. The VM
# boot and Roam build are expensive (~minutes) so we reuse them.
_TART_VM = None
_TART_OUTPUT_DIR: str | None = None


def _get_or_create_tart_vm():
    """Return the cached TartVM, booting + provisioning it on first call.

    Honors `TART_BASE_IMAGE` and `TART_VM_NAME` env vars (overrides for
    the defaults in tart_screenshots.py).
    """
    global _TART_VM, _TART_OUTPUT_DIR
    if _TART_VM is not None:
        return _TART_VM

    from tart_screenshots import (
        BASE_IMAGE_DEFAULT,
        DISPLAY_DEFAULT,
        VM_NAME_DEFAULT,
        TartVM,
        build_roam_app,
        ensure_dependencies,
    )

    ensure_dependencies()

    app_path = build_roam_app()
    host_app_dir = os.path.dirname(app_path)

    _TART_OUTPUT_DIR = tempfile.mkdtemp(prefix="roam-tart-out-")
    base_image = os.environ.get("TART_BASE_IMAGE", BASE_IMAGE_DEFAULT)
    vm_name = os.environ.get("TART_VM_NAME", VM_NAME_DEFAULT)

    vm = TartVM(
        name=vm_name,
        base_image=base_image,
        display=DISPLAY_DEFAULT,
        host_app_dir=host_app_dir,
        host_output_dir=_TART_OUTPUT_DIR,
    )
    vm.bring_up()
    vm.install_roam_app()

    atexit.register(_teardown_tart_vm)
    _TART_VM = vm
    return vm


def _teardown_tart_vm() -> None:
    global _TART_VM, _TART_OUTPUT_DIR
    vm = _TART_VM
    if vm is not None:
        try:
            vm.kill_roam()
        except Exception as e:
            print(f"  Warning: kill_roam during teardown failed: {e}")
        try:
            vm.stop()
        except Exception as e:
            print(f"  Warning: stopping Tart VM failed: {e}")
    if _TART_OUTPUT_DIR and os.path.isdir(_TART_OUTPUT_DIR):
        shutil.rmtree(_TART_OUTPUT_DIR, ignore_errors=True)
    _TART_VM = None
    _TART_OUTPUT_DIR = None


def _wait_for_menubar_report(
    host_report_path: str, timeout: float = 12.0
) -> dict | None:
    """Poll a host-side path for the JSON report the app writes after it
    opens the MenuBarExtra popover. Returns parsed JSON or None on
    timeout / parse error."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        if os.path.isfile(host_report_path) and os.path.getsize(host_report_path) > 0:
            try:
                with open(host_report_path) as fh:
                    return json.load(fh)
            except (OSError, json.JSONDecodeError):
                pass
        time.sleep(0.25)
    return None


def _zoom_menubar_to_app_desktop(png_path: str, report: dict) -> bool:
    """Crop+zoom a *full-display* MenuBarExtra capture into the top-right -
    so the real menu bar and the open popover fill most of the frame - then
    resize to the exact 2880x1800 APP_DESKTOP slot, in place.

    Why this and not the old crop-then-upscale path: the previous approach
    `screencapture -R`'d only the tiny icon+popover region (a few hundred
    native px) and then sips-upscaled it ~2–4x to fill 2880x1800, which
    pixelated badly. Here every output pixel comes from the native-res
    full-display screenshot, and the crop is sized so the upscale stays
    mild (≤ MAX_UPSCALE), keeping the menu-bar UI crisp while still
    showing it large against the real macOS desktop.

    Coordinates come from the app's `-MenuBarExtraReportPath` report
    (`iconFrame`/`popoverFrame`/`displayFrame`, AppKit bottom-origin screen
    *points*). We map them to top-origin *pixels* using the screenshot's
    own width vs. the reported logical width, so it stays correct
    regardless of the guest's backing scale factor.

    Returns True if the zoom was applied. Returns False (leaving the
    un-zoomed full-display PNG, itself a valid crisp 2880x1800 desktop
    shot) when the report lacks the frames needed to frame the popover, or
    no image tool is available.
    """
    target_w, target_h = 2880, 1800
    aspect = target_w / target_h  # 1.6 (the APP_DESKTOP slot ratio)
    MAX_UPSCALE = 2.0  # never blow native pixels up by more than this

    icon = report.get("iconFrame")
    popover = report.get("popoverFrame")
    display = report.get("displayFrame")
    if icon is None or display is None:
        print(
            "  Warning: MenuBarExtra report missing iconFrame/displayFrame "
            f"(error: {report.get('error')!r}); keeping full-display capture"
        )
        return False
    if popover is None:
        # Without the popover frame we can't frame the open remote; the
        # full-display shot (menu bar icon in real context) is the safe,
        # already-crisp fallback.
        print(
            "  Warning: MenuBarExtra popover frame not reported "
            f"(error: {report.get('error')!r}); keeping full-display capture"
        )
        return False

    png_dims = _read_png_dimensions(png_path)
    if png_dims is None:
        print(
            f"  Warning: could not read dims of {png_path}; keeping full-display capture"
        )
        return False
    png_w, png_h = png_dims

    disp_w_pt = display.get("width", 0)
    disp_h_pt = display.get("height", 0)
    if disp_w_pt <= 0 or disp_h_pt <= 0:
        return False
    # points -> screenshot pixels (derive from the screenshot itself so it's
    # right even if the captured framebuffer differs from the logical size).
    scale = png_w / disp_w_pt

    # Union of icon + popover in bottom-origin points.
    ux0 = min(icon["x"], popover["x"])
    ux1 = max(icon["x"] + icon["width"], popover["x"] + popover["width"])
    u_bottom_pt = min(icon["y"], popover["y"])  # lowest edge (bottom-origin)
    union_cx_px = ((ux0 + ux1) / 2.0) * scale
    # The popover's bottom edge in top-origin pixels (deepest point we need
    # to keep in frame). The crop is anchored at the very top of the screen
    # (y=0) so the menu bar stays visible.
    popover_bottom_px = (disp_h_pt - u_bottom_pt) * scale

    margin_px = 0.06 * png_h  # breathing room below the popover
    crop_bottom = min(popover_bottom_px + margin_px, float(png_h))

    # Width that holds the target aspect for that height, but widened if
    # needed so the upscale never exceeds MAX_UPSCALE (a wider crop = less
    # upscale, popover slightly smaller in frame). Then clamp to the image.
    crop_w = max(crop_bottom * aspect, target_w / MAX_UPSCALE)
    crop_w = min(crop_w, float(png_w))
    crop_h = min(crop_w / aspect, float(png_h))

    # Center horizontally on the popover, anchored at the top, clamped in.
    left = max(0.0, min(union_cx_px - crop_w / 2.0, png_w - crop_w))
    left_i, top_i = int(round(left)), 0
    w_i = min(int(round(crop_w)), png_w - left_i)
    h_i = min(int(round(crop_h)), png_h - top_i)
    if w_i <= 0 or h_i <= 0:
        print(
            f"  Warning: MenuBarExtra crop degenerate ({w_i}x{h_i}); keeping full-display capture"
        )
        return False

    tool = (
        "magick"
        if shutil.which("magick")
        else ("convert" if shutil.which("convert") else None)
    )
    if tool is None:
        print(
            "  Warning: ImageMagick (magick/convert) not found; cannot zoom "
            "the MenuBarExtra capture - keeping full-display shot. "
            "Install with `brew install imagemagick`."
        )
        return False

    proc = subprocess.run(
        [
            tool,
            png_path,
            "-crop",
            f"{w_i}x{h_i}+{left_i}+{top_i}",
            "+repage",
            "-filter",
            "Lanczos",
            "-resize",
            f"{target_w}x{target_h}!",
            png_path,
        ],
        capture_output=True,
    )
    if proc.returncode != 0:
        print(
            "  Warning: ImageMagick zoom of MenuBarExtra failed: "
            f"{proc.stderr.decode('utf-8', errors='replace')}; keeping full-display shot"
        )
        return False
    print(
        f"  Zoomed MenuBarExtra: crop {w_i}x{h_i}+{left_i}+{top_i} "
        f"(upscale {target_w / w_i:.2f}x) -> {target_w}x{target_h}"
    )
    return True


class MetadataManager:
    workspace_path: str
    screenshot_update_platforms: list[Platform]

    def __init__(
        self,
        workspace_path: str,
        screenshot_update_platforms: list[Platform],
        only_devices: set[str] | None = None,
    ):
        self.workspace_path = workspace_path
        self.screenshot_update_platforms = screenshot_update_platforms
        self.only_devices = only_devices

    def _get_primary_doc(self, platform: Platform, doc: str) -> str | None:
        # Read workspace/docs/src/pages/changes/<platform>.md
        file_path = os.path.join(
            self.workspace_path, "docs", "src", "pages", doc, f"{platform}.md"
        )
        if os.path.exists(file_path):
            with open(file_path, "r") as f:
                return f.read().strip()
        else:
            return None

    def _get_localized_doc(
        self, platform: Platform, language: Language, doc: str
    ) -> str | None:
        file_path = os.path.join(
            self.workspace_path,
            "docs",
            "i18n",
            language,
            "docusaurus-plugin-content-pages",
            doc,
            f"{platform}.md",
        )
        if os.path.exists(file_path):
            with open(file_path, "r") as f:
                return f.read().strip()
        else:
            return None

    def _get_localized_field(self, doc: str) -> LocalizedField:
        platforms = dict()
        for platform in Platform:
            en_whats_new = self._get_primary_doc(platform, doc)
            if not en_whats_new:
                raise RuntimeError(f'Missing primary "{doc}" for platform {platform}')
            languages = {
                Language.en: en_whats_new,
            }
            for language in Language:
                if language == Language.en:
                    continue

                localized_whats_new = self._get_localized_doc(platform, language, doc)
                if localized_whats_new:
                    languages[language] = localized_whats_new
                else:
                    raise RuntimeError(
                        f'Missing localized "{doc}" for platform {platform} and language {language}'
                    )

            platforms[platform] = languages

        return LocalizedField(
            ios=platforms[Platform.iOS],
            vision_os=platforms[Platform.visionOS],
            mac_os=platforms[Platform.macOS],
        )

    def get_update_info_localizations(self) -> LocalizedMetadata:
        whats_new = self._get_localized_field("changes")
        description = self._get_localized_field("description")

        return LocalizedMetadata(whats_new=whats_new, description=description)

    def get_screenshots(self, locale_id: str) -> dict[Platform, list[ScreenshotExport]]:
        """
        Run UI tests and extract screenshots for every configured device, in
        the given BCP-47 locale.

        Args:
            locale_id: BCP-47 identifier (e.g. "en-US", "fr-FR")

        Returns:
            Dict mapping platforms to lists of ScreenshotExport objects, only
            for devices whose tests produced an export directory.
        """
        devices = {
            Platform.iOS: [
                ScreenshotSource(device="iPhone 17 Pro Max", size="6.9"),
                ScreenshotSource(device="iPhone 11", size="6.5"),
                ScreenshotSource(device="iPad Pro 13-inch (M4)", size="13"),
                ScreenshotSource(device="iPhone Duo", size="Duo"),
                ScreenshotSource(device="Apple Watch Series 11 (46mm)", size="Watch46"),
            ],
            # macOS tests run on the host Mac itself (no simulator), so a single
            # entry is sufficient - xcodebuild can't pick a "screen size" for
            # the host. The captured screenshot's resolution is whatever the
            # test renders; APP_DESKTOP accepts a few standard sizes which the
            # dimension validator will check against.
            Platform.macOS: [
                ScreenshotSource(device="Mac", size="desktop"),
            ],
            Platform.visionOS: [
                ScreenshotSource(device="Apple Vision Pro", size="3840_2160")
            ],
        }

        result = {}
        for platform in self.screenshot_update_platforms:
            platform_exports = []
            for device in devices[platform]:
                if self.only_devices and device.size not in self.only_devices:
                    continue
                screenshot_path = self._get_device_screenshots(device.device, locale_id)
                if screenshot_path:
                    platform_exports.append(
                        ScreenshotExport(
                            size=device.size,
                            path=screenshot_path,
                        )
                    )

            if platform_exports:
                result[platform] = platform_exports

        return result

    def _get_vision_screenshots_via_simctl(
        self, device_name: str, locale_id: str
    ) -> str | None:
        """
        Capture visionOS screenshots via `simctl io screenshot`. Drives the app
        through 3 launch states (empty / loaded / vertical-window) to satisfy
        Apple's minimum 3 screenshots per display type, since simctl can't
        send UI taps to navigate to Settings/etc. on visionOS.
        """
        import uuid as _uuid

        tmp = tempfile.gettempdir()
        export_dir = os.path.join(
            tmp, "auto-screenshots", device_name, f"{locale_id}.export"
        )
        device_subdir = os.path.join(export_dir, f"{device_name} (visionOS)")

        # Reuse cache if already populated.
        if os.path.isdir(device_subdir):
            for f in os.listdir(device_subdir):
                if f.lower().endswith((".png", ".jpg", ".jpeg")):
                    print(
                        f"Reusing cached visionOS screenshots for {locale_id} ({device_subdir})"
                    )
                    return export_dir

        os.makedirs(device_subdir, exist_ok=True)

        # Find the freshly-built Roam.app for xrsimulator. We rely on a prior
        # `xcodebuild` invocation having compiled the app for this destination.
        derived_data = os.path.expanduser("~/Library/Developer/Xcode/DerivedData")
        candidates = []
        if os.path.isdir(derived_data):
            for entry in os.listdir(derived_data):
                if entry.startswith("Roam-"):
                    candidate = os.path.join(
                        derived_data,
                        entry,
                        "Build",
                        "Products",
                        "Debug-xrsimulator",
                        "Roam.app",
                    )
                    if os.path.isdir(candidate):
                        candidates.append(candidate)
        if not candidates:
            print(
                "Cannot find a Debug-xrsimulator build of Roam.app - run "
                "`xcodebuild build -scheme Roam -destination "
                "'platform=visionOS Simulator,name=Apple Vision Pro'` once first."
            )
            return None
        app_path = max(candidates, key=os.path.getmtime)

        bundle_id = "com.msdrigg.roam"
        underscore_locale = locale_id.replace("-", "_")
        common_args = [
            "-AppleLanguages",
            f"({locale_id})",
            "-AppleLocale",
            underscore_locale,
        ]

        # (state_index, attachment_name, extra_launch_args, settle_seconds,
        #  post_launch_action) - `post_launch_action` runs after the settle
        # delay and before the screenshot. Used by KeyboardOpen to dolly the
        # visionOS camera back so the floating dictation/keyboard pill is
        # inside the captured 3840×2160 framebuffer instead of below it.
        # State indices match the iOS test convention so the existing
        # _collect_locale_screenshots helper sorts them consistently
        # (Primary first, then KeyboardOpen, then Settings, then ScreenScanning).
        # The visionOS app honors -OpenKeyboard / -OpenSettings to pre-set
        # the corresponding view state on launch (see RemoteRoot.swift +
        # RemoteView.swift), so simctl can capture each state without needing
        # to drive UI taps (XCTest's screenshots return 1x1 placeholders on
        # the visionOS sim).
        states = [
            (4, "ScreenScanning", ["-DataTesting"], 6, None),
            (
                1,
                "Primary",
                ["-DataLoadTestingData", "-ScreenshotTesting", "-DataTesting"],
                8,
                None,
            ),
            (
                5,
                "KeyboardOpen",
                [
                    "-DataLoadTestingData",
                    "-ScreenshotTesting",
                    "-DataTesting",
                    "-OpenKeyboard",
                ],
                8,
                "vision_keyboard_camera",
            ),
            (
                7,
                "Settings",
                [
                    "-DataLoadTestingData",
                    "-ScreenshotTesting",
                    "-DataTesting",
                    "-OpenSettings",
                ],
                8,
                None,
            ),
        ]

        # Boot sim if not already.
        boot_proc = subprocess.run(
            ["xcrun", "simctl", "boot", device_name],
            capture_output=True,
        )
        if boot_proc.returncode != 0 and b"Booted" not in boot_proc.stderr:
            # `Unable to boot device in current state: Booted` is fine.
            stderr = boot_proc.stderr.decode("utf-8", errors="replace")
            if "Booted" not in stderr:
                print(f"Warning: simctl boot failed: {stderr}")

        # Install the freshly-built app once.
        install_proc = subprocess.run(
            ["xcrun", "simctl", "install", "booted", app_path],
            capture_output=True,
        )
        if install_proc.returncode != 0:
            print(
                f"simctl install failed: {install_proc.stderr.decode('utf-8', errors='replace')}"
            )
            return None

        captured_any = False
        for state_index, state_name, extra_args, settle, post_action in states:
            # Terminate any prior instance so launch args take effect.
            subprocess.run(
                ["xcrun", "simctl", "terminate", "booted", bundle_id],
                capture_output=True,
            )
            time.sleep(0.5)

            launch_proc = subprocess.run(
                [
                    "xcrun",
                    "simctl",
                    "launch",
                    "booted",
                    bundle_id,
                    *common_args,
                    *extra_args,
                ],
                capture_output=True,
            )
            if launch_proc.returncode != 0:
                print(
                    f"  Warning: simctl launch failed for {locale_id} "
                    f"{state_name}: {launch_proc.stderr.decode('utf-8', errors='replace')}"
                )
                continue

            time.sleep(settle)

            if post_action == "vision_keyboard_camera":
                self._prepare_vision_keyboard_camera()

            # Filename matches the format _collect_locale_screenshots expects.
            fn = (
                f"{locale_id}{state_index}{state_name}_0_"
                f"{_uuid.uuid4().hex.upper()}.png"
            )
            out_path = os.path.join(device_subdir, fn)

            shot_proc = subprocess.run(
                ["xcrun", "simctl", "io", "booted", "screenshot", out_path],
                capture_output=True,
            )
            if shot_proc.returncode != 0 or not os.path.exists(out_path):
                print(
                    f"  Warning: simctl screenshot failed for {locale_id} "
                    f"{state_name}: {shot_proc.stderr.decode('utf-8', errors='replace')}"
                )
                continue
            captured_any = True
            print(f"  Captured visionOS {state_name} for {locale_id} ({fn})")

        # Clean up the running app.
        subprocess.run(
            ["xcrun", "simctl", "terminate", "booted", bundle_id],
            capture_output=True,
        )

        return export_dir if captured_any else None

    def _prepare_vision_keyboard_camera(self) -> None:
        """Position the visionOS sim camera so the system dictation/keyboard
        pill - which floats below the app window in 3D space - lands inside
        the captured 3840×2160 framebuffer instead of below it.

        Sequence:
          1. Disconnect the host hardware keyboard (Shift+Cmd+K toggle). With
             a HW keyboard connected visionOS suppresses the on-screen input
             surface entirely. The shortcut also flips the simulator's input
             mode so subsequent "s" keystrokes drive camera navigation in the
             sim rather than getting typed into the focused text field.
          2. Reset Camera (Ctrl+Cmd+0) to a known starting pose.
          3. Hold "s" for ~5s to dolly the camera back. Holding it (rather
             than tapping) lets the sim's continuous-motion handler move far
             enough back to fit both the app window and the keyboard pill.
          4. Re-Center Open Apps to recompose the scene so the app + keyboard
             pill are both inside the user's POV.

        All steps are best-effort: any AppleScript failure logs a warning
        and the screenshot is taken anyway. Requires Accessibility permission
        for the process driving osascript.
        """
        toggle_script = (
            'tell application "Simulator" to activate\n'
            "delay 0.4\n"
            'tell application "System Events"\n'
            '    tell process "Simulator"\n'
            '        set mark to value of attribute "AXMenuItemMarkChar" '
            'of menu item "Connect Hardware Keyboard" of menu 1 of '
            'menu item "Keyboard" of menu "I/O" of menu bar 1\n'
            "        if mark is not missing value then\n"
            '            keystroke "k" using {shift down, command down}\n'
            "            delay 0.4\n"
            "        end if\n"
            "    end tell\n"
            "end tell\n"
        )
        toggle = subprocess.run(["osascript", "-e", toggle_script], capture_output=True)
        if toggle.returncode != 0:
            print(
                "  Warning: visionOS HW keyboard disable failed: "
                f"{toggle.stderr.decode('utf-8', errors='replace').strip()}"
            )

        camera_script = (
            'tell application "Simulator" to activate\n'
            "delay 0.3\n"
            'tell application "System Events"\n'
            '    keystroke "0" using {command down, control down}\n'
            "    delay 0.5\n"
            '    key down "s"\n'
            "    delay 5\n"
            '    key up "s"\n'
            "    delay 0.5\n"
            '    tell process "Simulator"\n'
            '        click menu item "Re-Center Open Apps" of '
            'menu "Device" of menu bar 1\n'
            "    end tell\n"
            "end tell\n"
            "delay 1\n"
        )
        camera = subprocess.run(["osascript", "-e", camera_script], capture_output=True)
        if camera.returncode != 0:
            print(
                "  Warning: visionOS camera reposition failed: "
                f"{camera.stderr.decode('utf-8', errors='replace').strip()}"
            )

    def _get_mac_screenshots_via_tart(
        self, device_name: str, locale_id: str
    ) -> str | None:
        """
        Capture macOS screenshots inside a Tart-managed macOS guest VM so
        the host display stays free for normal work while screenshots
        run. The host builds Roam.app once (cached across locales),
        the VM mounts it via a read-only shared folder, and each state
        is captured by running `screencapture` over SSH and copying the
        PNG back through a writable shared folder.

        For the MenuBarExtra state we capture the whole native-res desktop
        (with the popover open) and then crop+zoom into the top-right so the
        menu bar and popover fill most of the frame - coordinates come from
        the app's `-MenuBarExtraReportPath` JSON report. Because every output
        pixel comes from the full-res screenshot (only a mild upscale), the
        menu-bar UI stays crisp; see `_zoom_menubar_to_app_desktop`.
        """
        import uuid as _uuid

        tmp = tempfile.gettempdir()
        export_dir = os.path.join(
            tmp, "auto-screenshots", device_name, f"{locale_id}.export"
        )
        device_subdir = os.path.join(export_dir, "Mac")

        if os.path.isdir(device_subdir):
            for f in os.listdir(device_subdir):
                if f.lower().endswith((".png", ".jpg", ".jpeg")):
                    print(
                        f"Reusing cached macOS screenshots for {locale_id} "
                        f"({device_subdir})"
                    )
                    return export_dir
        os.makedirs(device_subdir, exist_ok=True)

        try:
            vm = _get_or_create_tart_vm()
        except Exception as e:
            print(f"  Error bringing up Tart VM: {e}")
            return None

        from tart_screenshots import GUEST_SHARED_ROOT, SHARE_OUT

        # (state_index, attachment_name, extra_launch_args, settle_seconds,
        #  capture_kind). capture_kind is "full" for whole-display captures
        # and "menubar" for the cropped menu-bar capture.
        states = [
            (4, "ScreenScanning", ["-DataTesting"], 8.0, "full"),
            (
                1,
                "Primary",
                [
                    "-DataLoadTestingData",
                    "-ScreenshotTesting",
                    "-DataTesting",
                ],
                9.0,
                "full",
            ),
            (
                7,
                "Settings",
                [
                    "-DataLoadTestingData",
                    "-ScreenshotTesting",
                    "-DataTesting",
                    "-OpenSettings",
                ],
                8.0,
                "full",
            ),
            # `-showMenuBar YES` must be present at launch so the
            # MenuBarExtra scene is inserted at initial scene-graph build.
            # Flipping it at runtime crashes the app (SwiftUI scene-update
            # recursion) - see Roam/ScreenshotCapture.swift.
            (
                6,
                "MenuBarExtra",
                [
                    "-DataLoadTestingData",
                    "-ScreenshotTesting",
                    "-DataTesting",
                    "-showMenuBar",
                    "YES",
                    "-OpenMenuBarExtra",
                ],
                9.0,
                "menubar",
            ),
        ]

        captured_any = False
        for state_index, state_name, extra_args, settle, capture_kind in states:
            uid = _uuid.uuid4().hex.upper()
            fn = f"{locale_id}{state_index}{state_name}_0_{uid}.png"
            dst = os.path.join(device_subdir, fn)

            launch_args = list(extra_args)
            report_guest_path: str | None = None
            report_host_path: str | None = None
            if capture_kind == "menubar":
                report_basename = (
                    f"menubar-report-{int(time.time() * 1000)}-"
                    f"{_uuid.uuid4().hex[:8]}.json"
                )
                report_guest_path = f"{GUEST_SHARED_ROOT}/{SHARE_OUT}/{report_basename}"
                report_host_path = os.path.join(vm.host_output_dir, report_basename)
                launch_args += [
                    "-MenuBarExtraReportPath",
                    report_guest_path,
                ]

            try:
                vm.launch_roam(launch_args, locale=locale_id)
            except Exception as e:
                print(
                    f"  Warning: launch_roam failed for {locale_id} {state_name}: {e}"
                )
                continue

            time.sleep(settle)

            # Center Roam's main window on the 2880x1800 desktop for the
            # main-window states. SwiftUI brings it up at a restored/ideal
            # frame that isn't centered; an AX resize gives a consistent,
            # attractive presentation. Skip for Settings (its sheet sizes
            # itself) and MenuBarExtra (no main window in play).
            if state_name in ("ScreenScanning", "Primary"):
                disp_w, disp_h = vm.display
                win_w, win_h = 1440, 900
                vm.resize_roam_window(
                    x=(disp_w - win_w) // 2,
                    y=(disp_h - win_h) // 2,
                    width=win_w,
                    height=win_h,
                )
                time.sleep(1.0)

            try:
                if capture_kind == "menubar":
                    # The app opens the popover *before* writing the report,
                    # so waiting for the report first guarantees the popover
                    # is on screen when we grab the full native-res desktop.
                    report = _wait_for_menubar_report(report_host_path)
                    vm.screenshot_full_display(dst)
                    if report is None:
                        print(
                            f"  Warning: no MenuBarExtra report appeared at "
                            f"{report_host_path}; keeping full-display capture"
                        )
                    else:
                        # Crop+zoom into the top-right (menu bar + popover);
                        # leaves the full-display shot as-is on failure.
                        if _zoom_menubar_to_app_desktop(dst, report):
                            _strip_png_exif(dst)
                        try:
                            os.remove(report_host_path)
                        except FileNotFoundError:
                            pass
                else:
                    vm.screenshot_full_display(dst)
            except Exception as e:
                print(f"  Warning: capture failed for {locale_id} {state_name}: {e}")
                vm.kill_roam()
                continue

            captured_any = True
            print(f"  Captured macOS {state_name} for {locale_id} ({fn})")
            vm.kill_roam()
            time.sleep(0.5)

        return export_dir if captured_any else None

    def _get_device_screenshots(self, device_name: str, locale_id: str) -> str | None:
        """
        Run UI tests for a specific device and language to capture screenshots.
        Then extract them using xcparse.

        Args:
            device_name: The name of the simulator/device to use
            locale_id: A BCP-47 locale identifier (e.g. "en-US", "fr-FR")

        Returns:
            Path to the directory containing the extracted screenshots, or None
            on failure.
        """
        # Invalidate the cache root if the screenshot pipeline schema has
        # changed since last run. Prevents stale captures (different state
        # set, different launch args, different post-processing) from
        # masquerading as up-to-date.
        _ensure_cache_schema(os.path.join(tempfile.gettempdir(), "auto-screenshots"))

        # visionOS sim's XCTest screenshot capture returns 1x1 placeholders in
        # Xcode 26 - work around it by using `simctl io screenshot` instead,
        # which captures the full sim display (including the AR background)
        # at the 3840x2160 resolution APP_APPLE_VISION_PRO requires. We can't
        # drive UI taps via simctl, so we capture three states by relaunching
        # the app with different launch-argument combinations.
        if "Vision" in device_name:
            return self._get_vision_screenshots_via_simctl(device_name, locale_id)

        # macOS: bypass xcodebuild entirely and run the captures inside a
        # Tart-managed macOS guest VM (see scripts/tart_screenshots.py).
        # The host display stays free; the guest renders at 2880x1800 and
        # we `screencapture` the whole display (full-screen states) or
        # the menu-bar region (MenuBarExtra state) over SSH.
        if device_name == "Mac" or "MacBook" in device_name:
            return self._get_mac_screenshots_via_tart(device_name, locale_id)

        # simctl cannot fold the Duo, so its two displays are captured in
        # separate passes by scripts/duo_screenshots.py ahead of this run.
        if device_name == "iPhone Duo":
            export = os.path.join(
                tempfile.gettempdir(), "auto-screenshots", device_name, f"{locale_id}.export"
            )
            if _collect_locale_screenshots(export, locale_id, max_count=1):
                return export
            print(
                f"No Duo captures for {locale_id}. Run scripts/duo_screenshots.py "
                f"--display outer --locales {locale_id} with the simulator folded, "
                "then --display inner with it open."
            )
            return None

        tmp = tempfile.gettempdir()
        screenshots_dir = os.path.join(
            tmp, "auto-screenshots", device_name, f"{locale_id}.xcresult"
        )
        screenshots_dir_export = os.path.join(
            tmp, "auto-screenshots", device_name, f"{locale_id}.export"
        )
        screenshots_dir_parent = os.path.join(tmp, "auto-screenshots", device_name)

        # Reuse a cached export tree if one already exists with PNGs in it.
        # This lets a generate-only run be followed by an upload-only run
        # without re-executing xcodebuild for ~90 minutes per platform×locale
        # matrix. Delete the export directory by hand to force a fresh run.
        if os.path.isdir(screenshots_dir_export):
            cached_pngs = []
            for root, _, files in os.walk(screenshots_dir_export):
                for f in files:
                    if f.lower().endswith((".png", ".jpg", ".jpeg")):
                        cached_pngs.append(f)
                        if len(cached_pngs) > 0:
                            break
                if cached_pngs:
                    break
            if cached_pngs:
                print(
                    f"Reusing cached screenshots for {device_name} in {locale_id} "
                    f"({screenshots_dir_export})"
                )
                return screenshots_dir_export

        if os.path.exists(screenshots_dir):
            shutil.rmtree(screenshots_dir)
        if os.path.exists(screenshots_dir_export):
            shutil.rmtree(screenshots_dir_export)
        os.makedirs(screenshots_dir_parent, exist_ok=True)

        test_scheme = "RoamUITests"
        test_class = "RoamUITestsScreenshotTests"

        # macOS tests run on the host (no simulator name); every other platform
        # runs in a simulator and needs a `name=` to disambiguate.
        if "Watch" in device_name:
            test_scheme = "RoamWatchUITests"
            test_class = "RoamWatchUITestsScreenshotTests"
            destination = f"platform=watchOS Simulator,name={device_name}"
        elif device_name == "Mac" or "MacBook" in device_name:
            destination = "platform=macOS"
        elif "Vision" in device_name:
            destination = f"platform=visionOS Simulator,name={device_name}"
        else:
            destination = f"platform=iOS Simulator,name={device_name}"

        # Pass the locale to the test bundle via env vars. The TEST_RUNNER_
        # prefixed variant is forwarded by xcodebuild to simulator-side test
        # processes (with the prefix stripped); the unprefixed variant covers
        # macOS where env inherits naturally.
        env = os.environ.copy()
        env["SCREENSHOT_LOCALE"] = locale_id
        env["TEST_RUNNER_SCREENSHOT_LOCALE"] = locale_id

        command = [
            "xcodebuild",
            "test",
            "-scheme",
            test_scheme,
            "-destination",
            destination,
            "-testLanguage",
            locale_id,
            "-resultBundlePath",
            screenshots_dir,
            "-only-testing",
            f"{test_scheme}/{test_class}/testCaptureScreenshots",
        ]

        print(f"Running UI tests for {device_name} in {locale_id}...")
        # xcodebuild on macOS reliably hangs after a successful test run
        # (the test process tears down cleanly but xcodebuild itself never
        # writes the result-bundle path line or exits). Run via Popen and
        # watch the stream for "Test Suite 'Selected tests' passed"; once
        # seen, give it POST_TEST_GRACE seconds to finalize the result
        # bundle, then kill. HARD_TIMEOUT bounds the whole invocation in
        # case the test itself hangs.
        HARD_TIMEOUT = 1200
        # On macOS the test writes PNGs directly to SCREENSHOT_OUTPUT_DIR
        # during execution, so we don't need to wait for xcresult
        # finalization (which never completes due to xcodebuild's post-test
        # hang). 5s grace is enough for any in-flight writes to flush.
        POST_TEST_GRACE = 5
        import sys as _sys
        import threading

        process = subprocess.Popen(
            command,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )
        kill_lock = threading.Lock()
        kill_reason = [None]

        def _kill(msg):
            with kill_lock:
                if kill_reason[0] is None:
                    kill_reason[0] = msg
                    try:
                        process.kill()
                    except ProcessLookupError:
                        pass

        kill_timer = threading.Timer(
            HARD_TIMEOUT, lambda: _kill(f"hard timeout {HARD_TIMEOUT}s")
        )
        kill_timer.daemon = True
        kill_timer.start()
        try:
            for line in process.stdout:
                _sys.stdout.write(line)
                _sys.stdout.flush()
                if "Test Suite 'Selected tests' passed" in line:
                    kill_timer.cancel()
                    kill_timer = threading.Timer(
                        POST_TEST_GRACE,
                        lambda: _kill(f"post-test hang {POST_TEST_GRACE}s"),
                    )
                    kill_timer.daemon = True
                    kill_timer.start()
        finally:
            kill_timer.cancel()
        process.wait()
        returncode = process.returncode
        if kill_reason[0] is not None:
            print(
                f"Warning: UI tests for {device_name} in {locale_id} were "
                f"killed ({kill_reason[0]}); attempting to extract any "
                f"captures already in the result bundle"
            )
            returncode = -1 if returncode == 0 else returncode

        if returncode != 0:
            # The test may have failed AFTER capturing some attachments - try
            # xcparse anyway to salvage what landed in the result bundle.
            print(
                f"Warning: UI tests for {device_name} in {locale_id} exited "
                f"with code {returncode}; attempting to extract any "
                f"captures already in the result bundle"
            )
            if not os.path.isdir(screenshots_dir):
                return None

        if shutil.which("xcparse") is None:
            print(
                "Failed to find xcparse. Please install it using `brew install xcparse` or similar."
            )
            return None

        extract_command = [
            "xcparse",
            "screenshots",
            "--os",
            "--model",
            screenshots_dir,
            screenshots_dir_export,
        ]
        print(f"Extracting screenshots for {device_name} in {locale_id}...")
        extract_result = subprocess.run(extract_command)

        # xcparse fails (and unhelpfully still exits 0) when the xcresult
        # bundle isn't finalized - which is always the case on macOS, since
        # xcodebuild reliably hangs post-test without writing the bundle's
        # Info.plist. Detect this by checking the export dir post-xcparse:
        # if it's missing or empty, fall back to scanning Data/ for raw
        # PNGs (the test attachments are still present as raw blobs there).
        def _export_has_pngs(path: str) -> bool:
            if not os.path.isdir(path):
                return False
            for _, _, files in os.walk(path):
                for fn in files:
                    if fn.lower().endswith((".png", ".jpg", ".jpeg")):
                        return True
            return False

        if not _export_has_pngs(screenshots_dir_export):
            print(
                f"  xcparse produced no PNGs (bundle likely unfinalized) - "
                f"scanning {screenshots_dir}/Data for raw PNGs"
            )
            recovered = _recover_pngs_from_xcresult_data(
                xcresult_path=screenshots_dir,
                export_path=screenshots_dir_export,
                locale_id=locale_id,
            )
            if recovered == 0:
                print(
                    f"Warning: Screenshot extraction for {device_name} in "
                    f"{locale_id} failed and no raw PNGs found in the "
                    f"bundle Data directory"
                )
                return None
            print(f"  Recovered {recovered} PNG(s) from {screenshots_dir}/Data")

        # iPad landscape: the XCTest path skipped LandscapePrimary because
        # iPad apps without UIRequiresFullScreen can't force their own
        # orientation. Capture it now via a separate simctl-driven pass
        # that uses Simulator.app's menu rotation (which DOES propagate
        # to the iPad scene). The captured file lands in
        # `screenshots_dir_export` so the same post-rotation sips step
        # below picks it up like any other LandscapePrimary.
        if "iPad" in device_name:
            print(f"Capturing iPad landscape via menu rotation for {locale_id}")
            _capture_ipad_landscape_via_simctl(
                device_name=device_name,
                locale_id=locale_id,
                export_dir=screenshots_dir_export,
            )

        # iPhone / iPad LandscapePrimary post-rotation.
        #
        # On iPhone the XCTest path uses -ForceLandscapeLeft +
        # `requestGeometryUpdate(.landscapeLeft)`. The app's scene rotates,
        # but XCUIScreen.main.screenshot() returns the device-native
        # portrait framebuffer with the landscape content rendered rotated
        # 90° CW inside that canvas. Rotate 90° CW with sips to get
        # APP_IPHONE_67/_65-acceptable landscape pixel dims.
        #
        # On iPad the simctl-driven capture above produces a portrait
        # framebuffer with the landscape content rendered rotated 90° CCW
        # (opposite of iPhone, because system-driven landscape-left
        # rotates the content the other way). sips --rotate 270 puts it
        # right-side-up.
        if "iPhone" in device_name or "iPad" in device_name:
            for root, _, files in os.walk(screenshots_dir_export):
                for fname in files:
                    if "LandscapePrimary" not in fname or not fname.lower().endswith(
                        ".png"
                    ):
                        continue
                    fpath = os.path.join(root, fname)
                    dims = _read_png_dimensions(fpath)
                    if dims is None or dims[0] >= dims[1]:
                        continue
                    rot_deg = "270" if "iPad" in device_name else "90"
                    rot = subprocess.run(
                        ["sips", "--rotate", rot_deg, fpath, "--out", fpath],
                        capture_output=True,
                    )
                    if rot.returncode == 0:
                        new_dims = _read_png_dimensions(fpath)
                        # Strip the eXIf chunk sips inserts to compensate
                        # for the pixel rotation - without this Finder/
                        # Preview/ASC's CDN re-rotate the image back to
                        # the original orientation for display, defeating
                        # the rotation entirely. See _strip_png_exif.
                        stripped = _strip_png_exif(fpath)
                        print(
                            f"Rotated LandscapePrimary {dims[0]}x{dims[1]} → "
                            f"{new_dims[0]}x{new_dims[1]} "
                            f"({device_name}/{locale_id})"
                            f"{' [stripped eXIf]' if stripped else ''}"
                        )
                    else:
                        stderr = rot.stderr.decode("utf-8", errors="replace")
                        print(f"  Warning: sips rotate failed for {fpath}: {stderr}")

        # iPhone 11 sim renders at 828x1792 (6.1" dims), but we want the
        # captures in the APP_IPHONE_65 (6.5") slot - Apple requires 1242x2688.
        # The aspect ratio is identical (1.5x in both axes), so a uniform sips
        # upscale produces a slightly soft but ASC-acceptable image. If a
        # genuine 6.5" sim (e.g. "iPhone 11 Pro Max") is installed and added
        # below, this branch becomes a no-op since dims already match.
        if device_name == "iPhone 11":
            for root, _, files in os.walk(screenshots_dir_export):
                for fname in files:
                    if not fname.lower().endswith(".png"):
                        continue
                    fpath = os.path.join(root, fname)
                    dims = _read_png_dimensions(fpath)
                    if dims is None:
                        continue
                    target = None
                    if dims == (828, 1792):
                        target = (1242, 2688)
                    elif dims == (1792, 828):
                        target = (2688, 1242)
                    if target is None:
                        continue
                    resample = subprocess.run(
                        [
                            "sips",
                            "--resampleHeightWidth",
                            str(target[1]),
                            str(target[0]),
                            fpath,
                            "--out",
                            fpath,
                        ],
                        capture_output=True,
                    )
                    if resample.returncode == 0:
                        print(
                            f"Upscaled iPhone 11 capture {dims[0]}x{dims[1]} → "
                            f"{target[0]}x{target[1]} ({fname}) for APP_IPHONE_65"
                        )
                    else:
                        print(
                            f"  Warning: sips upscale failed for {fpath}: "
                            f"{resample.stderr.decode('utf-8', errors='replace')}"
                        )

        return screenshots_dir_export


def _clean_screenshot_cache(only_locales: set[str] | None) -> None:
    """Remove the local screenshot capture cache so the next run regenerates
    instead of reusing cached images. Captures live under
    `$TMPDIR/auto-screenshots/<device>/<locale>.export|.xcresult`. With
    `only_locales`, only the matching per-locale dirs are removed; otherwise
    the whole cache is wiped."""
    cache_root = os.path.join(tempfile.gettempdir(), "auto-screenshots")
    if not os.path.isdir(cache_root):
        print(f"--clean: no screenshot cache at {cache_root}")
        return
    if not only_locales:
        shutil.rmtree(cache_root, ignore_errors=True)
        print(f"--clean: removed screenshot cache {cache_root}")
        return
    removed = 0
    for device in os.listdir(cache_root):
        device_dir = os.path.join(cache_root, device)
        if not os.path.isdir(device_dir):
            continue
        for entry in os.listdir(device_dir):
            # entries look like "en-US.export" / "en-US.xcresult"
            locale = entry.rsplit(".", 1)[0]
            if locale in only_locales:
                shutil.rmtree(os.path.join(device_dir, entry), ignore_errors=True)
                removed += 1
    print(
        f"--clean: removed {removed} cached locale dir(s) for "
        f"{sorted(only_locales)} under {cache_root}"
    )


async def main():
    # Parse key id and issuer id from APPSTORECONNECT_API_KEY, APPSTORECONNECT_API_ISSUER env variables
    key_id = os.environ.get("APPSTORECONNECT_API_KEY")
    issuer_id = os.environ.get("APPSTORECONNECT_API_ISSUER")
    if not key_id:
        raise ValueError("Missing APPSTORECONNECT_API_KEY environment variable")
    if not issuer_id:
        raise ValueError("Missing APPSTORECONNECT_API_ISSUER environment variable")

    parser = argparse.ArgumentParser(
        description="Sync metadata with an upcoming release of the app via the App Store Connect API"
    )

    parser.add_argument(
        "--platform",
        help="Platform to build and publish",
        choices=[x.value for x in Platform],
        nargs="+",
        required=True,
    )
    parser.add_argument(
        "--sync-screenshots",
        help="Run UI tests and upload screenshots to App Store Connect",
        action="store_true",
        default=False,
    )
    parser.add_argument(
        "--skip-upload",
        help=(
            "Generate screenshots and update everything locally, but don't "
            "make any write API calls to App Store Connect (metadata or "
            "screenshots). Use to dry-run the matrix and inspect results "
            "before committing to a real upload."
        ),
        action="store_true",
        default=False,
    )
    parser.add_argument(
        "--only-locales",
        help=(
            "Comma-separated BCP-47 locale ids to limit screenshot capture "
            "and metadata updates to (e.g. 'en-US' or 'en-US,fr-FR'). "
            "Useful for smoke-testing the capture pipeline against a "
            "single locale before committing to the full matrix."
        ),
        default=None,
    )
    parser.add_argument(
        "--only-devices",
        help=(
            "Comma-separated device size keys to capture and upload (e.g. "
            "'Duo' or '6.9,13'). Screenshot sets for other display types are "
            "left untouched in App Store Connect."
        ),
        default=None,
    )
    parser.add_argument(
        "--clean",
        help=(
            "Delete previously-captured screenshots (the local "
            "$TMPDIR/auto-screenshots cache) so the next run captures fresh "
            "instead of reusing cached images. Honors --only-locales: with "
            "it, only the matching locales' caches are removed. Used alone "
            "(without --sync-screenshots) it just wipes the cache and exits."
        ),
        action="store_true",
        default=False,
    )
    parser.add_argument(
        "--mac-vm-setup",
        help=(
            "One-time interactive setup for the macOS Tart VM. Boots the VM "
            "with a host window so you can click 'Allow' on the TCC "
            "dialogs (sshd-session screen recording bypass + Roam local "
            "network access). The grants persist on the VM disk and all "
            "subsequent headless runs capture cleanly. Skips metadata + "
            "screenshot upload entirely."
        ),
        action="store_true",
        default=False,
    )
    args = parser.parse_args()
    only_locales: set[str] | None = None
    if args.only_locales:
        only_locales = {x.strip() for x in args.only_locales.split(",") if x.strip()}

    only_devices: set[str] | None = None
    if args.only_devices:
        only_devices = {x.strip() for x in args.only_devices.split(",") if x.strip()}

    platforms = [Platform[platform] for platform in args.platform]
    sync_screenshots = args.sync_screenshots

    # Interactive Tart VM setup short-circuits everything else.
    if args.mac_vm_setup:
        if Platform.macOS not in platforms:
            raise ValueError("--mac-vm-setup requires --platform macOS")
        from tart_screenshots import (
            BASE_IMAGE_DEFAULT,
            DISPLAY_DEFAULT,
            VM_NAME_DEFAULT,
            TartVM,
            build_roam_app,
            ensure_dependencies,
            run_interactive_setup,
        )

        ensure_dependencies()
        app_path = build_roam_app()
        host_app_dir = os.path.dirname(app_path)
        host_output_dir = tempfile.mkdtemp(prefix="roam-tart-setup-")
        vm = TartVM(
            name=os.environ.get("TART_VM_NAME", VM_NAME_DEFAULT),
            base_image=os.environ.get("TART_BASE_IMAGE", BASE_IMAGE_DEFAULT),
            display=DISPLAY_DEFAULT,
            host_app_dir=host_app_dir,
            host_output_dir=host_output_dir,
        )
        try:
            run_interactive_setup(vm)
        finally:
            shutil.rmtree(host_output_dir, ignore_errors=True)
        return

    # Clean the local screenshot cache if requested. Used alone (no
    # --sync-screenshots) this is a pure cache wipe with nothing to upload,
    # so exit before touching App Store Connect.
    if args.clean:
        _clean_screenshot_cache(only_locales)
        if not sync_screenshots:
            return

    skip_upload = args.skip_upload

    user_home = os.path.expanduser("~")
    key_file = os.path.join(user_home, ".private_keys", f"AuthKey_{key_id}.p8")

    if not os.path.exists(key_file):
        raise ValueError(f"Private key file not found: {key_file}")

    token_manager = TokenManager(key_id, issuer_id, key_file)

    asc = AppStoreConnect(token_manager, debug=False)

    app_versions = await asc.get_upcoming_app_store_versions("6469834197")

    metadata_manager = MetadataManager(
        workspace_path=".",
        screenshot_update_platforms=platforms,
        only_devices=only_devices,
    )

    # Update metadata (whats new and description)
    localized_metadata = metadata_manager.get_update_info_localizations()
    for app_version in app_versions:
        if app_version.platform not in platforms:
            continue
        if skip_upload:
            print(
                f"[skip-upload] Would update version {app_version.platform} metadata for "
                f"{len(app_version.localizations)} localizations"
            )
            continue
        print("Updating version: ", app_version.platform)
        for localization in app_version.localizations:
            print("    Updating localization: ", localization.locale)

            update = localized_metadata.get_update(
                localization.locale, app_version.platform
            )

            await asc.update_localization(localization.id, update)

    # Process screenshots if requested
    if sync_screenshots:
        print("Processing screenshots...")

        # Mapping between configured device sizes and App Store Connect
        # screenshotDisplayType values.
        display_type_mapping = {
            # iOS
            "6.9": "APP_IPHONE_67",  # 6.9" Pro Max uploads to ASC's 6.7" slot
            "6.5": "APP_IPHONE_65",  # legacy 6.5" slot (XS Max / 11 Pro Max)
            "13": "APP_IPAD_PRO_3GEN_129",  # iPad Pro 12.9" slot (accepts 13")
            "Duo": "APP_IPHONE_DUO",
            # watchOS
            "Watch46": "APP_WATCH_SERIES_10",  # Series 10/11 (46mm)
            "Ultra": "APP_WATCH_ULTRA",
            # visionOS
            "3840_2160": "APP_APPLE_VISION_PRO",
            # macOS
            "desktop": "APP_DESKTOP",
        }
        max_screenshots_per_set = 10

        for app_version in app_versions:
            if app_version.platform not in platforms:
                continue

            print(f"Processing screenshots for platform: {app_version.platform}")

            for localization in app_version.localizations:
                locale_id = LANGUAGE_TO_IDENTIFIER.get(localization.locale)
                if not locale_id:
                    print(
                        f"  Skipping {localization.locale}: no BCP-47 mapping defined"
                    )
                    continue
                if only_locales and locale_id not in only_locales:
                    continue
                print(f"  Processing locale: {locale_id}")

                # PHASE 1: generate + validate everything for this locale BEFORE
                # any destructive App Store Connect operation. If generation or
                # validation fails for a display type, that set is skipped
                # entirely - the existing screenshots in App Store Connect are
                # left untouched.
                try:
                    screenshots_by_platform = metadata_manager.get_screenshots(
                        locale_id
                    )
                except Exception as e:
                    print(f"  Error generating screenshots for {locale_id}: {e}")
                    continue

                platform_exports = screenshots_by_platform.get(app_version.platform, [])

                grouped: dict[str, list[str]] = {}
                for export in platform_exports:
                    display_type = display_type_mapping.get(export.size)
                    if not display_type:
                        print(
                            f"    No display type mapping for device size {export.size}, skipping"
                        )
                        continue
                    if not os.path.exists(export.path):
                        print(f"    Screenshot path not found: {export.path}")
                        continue

                    candidates = _collect_locale_screenshots(
                        export.path, locale_id, max_count=max_screenshots_per_set * 2
                    )
                    valid_paths: list[str] = []
                    for path in candidates:
                        dims = _read_png_dimensions(path)
                        if dims is None:
                            print(
                                f"    Could not read dimensions for {os.path.basename(path)}, skipping"
                            )
                            continue
                        if not _dimensions_match(dims, display_type):
                            print(
                                f"    Dimensions {dims[0]}x{dims[1]} don't match {display_type} requirements, skipping {os.path.basename(path)}"
                            )
                            continue
                        valid_paths.append(path)

                    if valid_paths:
                        grouped.setdefault(display_type, []).extend(valid_paths)

                # Cap each display type at Apple's per-set maximum (multiple
                # devices may map to the same display type, e.g. APP_DESKTOP).
                for display_type in list(grouped.keys()):
                    grouped[display_type] = grouped[display_type][
                        :max_screenshots_per_set
                    ]

                if not grouped:
                    print(
                        f"  No valid screenshots for {locale_id} on {app_version.platform}, leaving existing sets untouched"
                    )
                    continue

                if skip_upload:
                    summary = ", ".join(
                        f"{dt}={len(paths)}" for dt, paths in grouped.items()
                    )
                    print(
                        f"  [skip-upload] {locale_id} {app_version.platform}: would upload {summary}"
                    )
                    continue

                # PHASE 2: now that generation + validation succeeded, fetch the
                # existing sets and proceed with delete + upload per display
                # type.
                try:
                    screenshot_sets = await asc.get_app_screenshot_sets(localization.id)
                except Exception as e:
                    print(f"  Error fetching existing screenshot sets: {e}")
                    continue

                existing_sets: dict[str, str] = {}
                for set_data in screenshot_sets.get("data", []):
                    dt = set_data.get("attributes", {}).get("screenshotDisplayType")
                    if dt:
                        existing_sets[dt] = set_data["id"]

                for display_type, paths in grouped.items():
                    try:
                        if display_type in existing_sets:
                            screenshot_set_id = existing_sets[display_type]
                            print(
                                f"    Using existing screenshot set for {display_type} ({len(paths)} new)"
                            )
                            current_screenshots = await asc.get_app_screenshots(
                                screenshot_set_id
                            )
                            for screenshot in current_screenshots.get("data", []):
                                screenshot_id = screenshot["id"]
                                print(
                                    f"      Deleting existing screenshot {screenshot_id}"
                                )
                                try:
                                    await asc._api_call(
                                        f"{BASE_API}/v1/appScreenshots/{screenshot_id}",
                                        method=HttpMethod.DELETE,
                                    )
                                except Exception as e:
                                    print(f"      Error deleting screenshot: {e}")
                        else:
                            print(
                                f"    Creating new screenshot set for {display_type} ({len(paths)} new)"
                            )
                            set_response = await asc.create_app_screenshot_set(
                                localization.id, display_type
                            )
                            screenshot_set_id = set_response["data"]["id"]
                            existing_sets[display_type] = screenshot_set_id

                        for path in paths:
                            filename = os.path.basename(path)
                            print(f"      Uploading {filename}")
                            try:
                                await asc.create_app_screenshot(
                                    screenshot_set_id, filename, path
                                )
                                print(f"      Successfully uploaded {filename}")
                            except Exception as e:
                                print(f"      Error uploading {filename}: {e}")
                    except Exception as e:
                        print(f"    Error processing display type {display_type}: {e}")

    print("Sync completed successfully!")


if __name__ == "__main__":
    import asyncio

    asyncio.run(main())
