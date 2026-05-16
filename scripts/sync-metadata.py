#!/usr/bin/env python3

import argparse
from dataclasses import dataclass
from datetime import datetime, timedelta
import enum
import gzip
import hashlib
import json
import os
import re
import shutil
import struct
import subprocess
import tempfile
import time
from httpx import AsyncClient, Response
import httpx
import jwt

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
                "-X", method,
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
    # introduced a 6.9-specific slot — APP_IPHONE_69 is rejected by ASC).
    # Accepts both the iPhone 14/15 Pro Max dims and the iPhone 16/17 Pro Max
    # dims, in portrait or landscape.
    "APP_IPHONE_67": [(1290, 2796), (2796, 1290), (1320, 2868), (2868, 1320)],
    # Legacy 6.5" iPhone slot (XS Max / 11 Pro Max). Apple keeps this slot
    # available even after introducing 6.7"/6.9". A plain iPhone 11 sim
    # produces 828x1792 (6.1" dims) which does NOT match — the matching
    # simulator is "iPhone 11 Pro Max" (1242x2688). The 12-15 Pro Max sims
    # render at 1284x2778, also accepted here.
    "APP_IPHONE_65": [(1242, 2688), (2688, 1242), (1284, 2778), (2778, 1284)],
    # 12.9"/13" iPad Pro slot — Apple accepts both the legacy 12.9" dims and
    # the 13" M4's native render.
    "APP_IPAD_PRO_3GEN_129": [(2048, 2732), (2732, 2048), (2064, 2752), (2752, 2064)],
    # Apple Watch Series 10 / 11 (46mm) — same display
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


def _collect_locale_screenshots(
    export_path: str, locale_id: str, max_count: int = 10
) -> list[str]:
    """
    Walk an xcparse export tree and return image paths matching a given locale.

    `xcparse screenshots --os --model` flattens attachment names: the test
    attaches a screenshot named "en-US/3/LandscapePrimary" and xcparse writes
    it as `<os>/<model>/en-US3LandscapePrimary_0_<UUID>.png` — the slashes are
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


class MetadataManager:
    workspace_path: str
    screenshot_update_platforms: list[Platform]

    def __init__(
        self, workspace_path: str, screenshot_update_platforms: list[Platform]
    ):
        self.workspace_path = workspace_path
        self.screenshot_update_platforms = screenshot_update_platforms

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

    def get_screenshots(
        self, locale_id: str
    ) -> dict[Platform, list[ScreenshotExport]]:
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
                ScreenshotSource(device="Apple Watch Series 11 (46mm)", size="Watch46"),
            ],
            # macOS tests run on the host Mac itself (no simulator), so a single
            # entry is sufficient — xcodebuild can't pick a "screen size" for
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
                screenshot_path = self._get_device_screenshots(
                    device.device, locale_id
                )
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
                "Cannot find a Debug-xrsimulator build of Roam.app — run "
                "`xcodebuild build -scheme Roam -destination "
                "'platform=visionOS Simulator,name=Apple Vision Pro'` once first."
            )
            return None
        app_path = max(candidates, key=os.path.getmtime)

        bundle_id = "com.msdrigg.roam"
        underscore_locale = locale_id.replace("-", "_")
        common_args = [
            "-AppleLanguages", f"({locale_id})",
            "-AppleLocale", underscore_locale,
        ]

        # (state_index, attachment_name, extra_launch_args, settle_seconds)
        # State indices match the iOS test convention so the existing
        # _collect_locale_screenshots helper sorts them consistently.
        states = [
            (4, "ScreenScanning", ["-DataTesting"], 6),
            (1, "Primary", ["-DataLoadTestingData", "-ScreenshotTesting", "-DataTesting"], 8),
            (3, "LandscapePrimary", [
                "-DataLoadTestingData",
                "-ScreenshotTesting",
                "-DataTesting",
                "-WindowStyleVertical",
            ], 8),
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
        for state_index, state_name, extra_args, settle in states:
            # Terminate any prior instance so launch args take effect.
            subprocess.run(
                ["xcrun", "simctl", "terminate", "booted", bundle_id],
                capture_output=True,
            )
            time.sleep(0.5)

            launch_proc = subprocess.run(
                [
                    "xcrun", "simctl", "launch", "booted", bundle_id,
                    *common_args, *extra_args,
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
        # visionOS sim's XCTest screenshot capture returns 1x1 placeholders in
        # Xcode 26 — work around it by using `simctl io screenshot` instead,
        # which captures the full sim display (including the AR background)
        # at the 3840x2160 resolution APP_APPLE_VISION_PRO requires. We can't
        # drive UI taps via simctl, so we capture three states by relaunching
        # the app with different launch-argument combinations.
        if "Vision" in device_name:
            return self._get_vision_screenshots_via_simctl(device_name, locale_id)

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
            "-scheme", test_scheme,
            "-destination", destination,
            "-testLanguage", locale_id,
            "-resultBundlePath", screenshots_dir,
            "-only-testing", f"{test_scheme}/{test_class}/testCaptureScreenshots",
        ]

        print(f"Running UI tests for {device_name} in {locale_id}...")
        result = subprocess.run(command, env=env)

        if result.returncode != 0:
            # The test may have failed AFTER capturing some attachments — try
            # xcparse anyway to salvage what landed in the result bundle.
            print(
                f"Warning: UI tests for {device_name} in {locale_id} exited "
                f"with code {result.returncode}; attempting to extract any "
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

        if extract_result.returncode != 0:
            print(
                f"Warning: Screenshot extraction for {device_name} in {locale_id} failed with code {extract_result.returncode}"
            )
            return None

        # iPadOS 26 simulator silently ignores XCUIDevice.orientation changes —
        # the screen stays portrait but XCTest tags the capture with landscape
        # dimensions, so LandscapePrimary comes out as sideways content in a
        # landscape canvas. Rotate 270° (counter-clockwise) so the content
        # reads correctly. The result is 2064x2752 (portrait pixel dims), which
        # APP_IPAD_PRO_3GEN_129 accepts.
        if "iPad" in device_name:
            for root, _, files in os.walk(screenshots_dir_export):
                for fname in files:
                    if "LandscapePrimary" in fname and fname.lower().endswith(".png"):
                        fpath = os.path.join(root, fname)
                        dims = _read_png_dimensions(fpath)
                        if dims == (2752, 2064):
                            rot = subprocess.run(
                                ["sips", "--rotate", "270", fpath, "--out", fpath],
                                capture_output=True,
                            )
                            if rot.returncode == 0:
                                print(
                                    f"Rotated iPad LandscapePrimary 270° "
                                    f"({device_name}/{locale_id}) to fix iPadOS "
                                    f"sim rotation bug"
                                )

        # iPhone test uses -ForceLandscapeLeft + UIWindowScene.requestGeometryUpdate
        # to render the app in landscape, then captures via XCUIScreen.main
        # .screenshot() which writes the device-native framebuffer (always
        # portrait pixel dims, e.g. 1320x2868). The landscape-rendered content
        # appears rotated 90° within that portrait frame. Rotate 90° CW to
        # produce a properly oriented 2868x1320 landscape image that
        # APP_IPHONE_69 accepts.
        if "iPhone" in device_name:
            for root, _, files in os.walk(screenshots_dir_export):
                for fname in files:
                    if "LandscapePrimary" in fname and fname.lower().endswith(".png"):
                        fpath = os.path.join(root, fname)
                        dims = _read_png_dimensions(fpath)
                        if dims is not None and dims[1] > dims[0]:
                            rot = subprocess.run(
                                ["sips", "--rotate", "90", fpath, "--out", fpath],
                                capture_output=True,
                            )
                            if rot.returncode == 0:
                                print(
                                    f"Rotated iPhone LandscapePrimary 90° "
                                    f"({device_name}/{locale_id}) to fix iOS "
                                    f"sim rotation bug"
                                )

        # iPhone 11 sim renders at 828x1792 (6.1" dims), but we want the
        # captures in the APP_IPHONE_65 (6.5") slot — Apple requires 1242x2688.
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
                            "--resampleHeightWidth", str(target[1]), str(target[0]),
                            fpath, "--out", fpath,
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
    args = parser.parse_args()

    platforms = [Platform[platform] for platform in args.platform]
    sync_screenshots = args.sync_screenshots
    skip_upload = args.skip_upload

    user_home = os.path.expanduser("~")
    key_file = os.path.join(user_home, ".private_keys", f"AuthKey_{key_id}.p8")

    if not os.path.exists(key_file):
        raise ValueError(f"Private key file not found: {key_file}")

    token_manager = TokenManager(key_id, issuer_id, key_file)

    asc = AppStoreConnect(token_manager, debug=False)

    app_versions = await asc.get_upcoming_app_store_versions("6469834197")

    metadata_manager = MetadataManager(
        workspace_path=".", screenshot_update_platforms=platforms
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
                print(f"  Processing locale: {locale_id}")

                # PHASE 1: generate + validate everything for this locale BEFORE
                # any destructive App Store Connect operation. If generation or
                # validation fails for a display type, that set is skipped
                # entirely — the existing screenshots in App Store Connect are
                # left untouched.
                try:
                    screenshots_by_platform = metadata_manager.get_screenshots(
                        locale_id
                    )
                except Exception as e:
                    print(f"  Error generating screenshots for {locale_id}: {e}")
                    continue

                platform_exports = screenshots_by_platform.get(
                    app_version.platform, []
                )

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
                    screenshot_sets = await asc.get_app_screenshot_sets(
                        localization.id
                    )
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
                        print(
                            f"    Error processing display type {display_type}: {e}"
                        )

    print("Sync completed successfully!")


if __name__ == "__main__":
    import asyncio

    asyncio.run(main())
