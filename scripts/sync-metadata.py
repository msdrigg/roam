#!/usr/bin/env python3

import argparse
from dataclasses import dataclass
from datetime import datetime, timedelta
import enum
import gzip
import hashlib
import json
import os
import shutil
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
            screenshot_display_type (str): The display type (e.g., "APP_IPHONE_65", "APP_IPAD_PRO_3GEN_129")

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

            # Upload the chunk
            upload_command = ["curl", "-X", method, url]
            for header_name, header_value in headers_dict.items():
                upload_command.extend(["-H", f"{header_name}: {header_value}"])

            upload_command.extend(["--data-binary", f"@{temp_path}"])

            # Execute the upload command
            result = os.system(" ".join(upload_command))

            # Remove the temporary file
            os.unlink(temp_path)

            if result != 0:
                raise APIError(f"Failed to upload screenshot chunk: {result}")

        # Commit the screenshot
        commit_url = f"{BASE_API}/v1/appScreenshots/{screenshot_id}"
        commit_json = {
            "data": {
                "type": "appScreenshots",
                "id": screenshot_id,
                "attributes": {"sourceFileChecksum": md5_hash, "isUploaded": True},
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
        self, localization: str
    ) -> dict[Platform, list[ScreenshotExport]]:
        """
        Get screenshots for all devices for the given localization.

        Args:
            localization (str): The localization code (e.g., "en-US")

        Returns:
            dict: Dictionary mapping platforms to lists of ScreenshotExport objects
        """
        devices = {
            Platform.iOS: [
                ScreenshotSource(device="iPhone 16 Plus", size="6.9"),
                ScreenshotSource(device="iPad Pro 13-inch (M4)", size="13"),
                ScreenshotSource(device="AppleWatchUltra2", size="Ultra"),
            ],
            Platform.macOS: [
                ScreenshotSource(device="MacBookPro_16", size="16"),
                ScreenshotSource(device="MacBookPro", size="2560_1600"),
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
                    device.device, localization
                )
                if screenshot_path:  # Only include if path exists
                    platform_exports.append(
                        ScreenshotExport(
                            size=device.size,
                            path=screenshot_path,
                        )
                    )

            if (
                platform_exports
            ):  # Only include platforms with at least one valid export
                result[platform] = platform_exports

        return result

    def _get_device_screenshots(self, device_name: str, localization: str) -> str:
        """
        Run UI tests for a specific device and language to capture screenshots.
        Then extract them using xcparse.

        Args:
            device_name (str): The name of the simulator/device to use
            localization (str): The locale identifier (e.g., "en-US")

        Returns:
            str: Path to the directory containing the extracted screenshots
        """
        # Create in root/tmp dir/auto-screenshots/{device_name}/{localization}
        tmp = tempfile.gettempdir()
        screenshots_dir = os.path.join(
            tmp, "auto-screenshots", device_name, f"{localization}.xcresult"
        )
        screenshots_dir_export = os.path.join(
            tmp, "auto-screenshots", device_name, f"{localization}.export"
        )
        screenshots_dir_parent = os.path.join(tmp, "auto-screenshots", device_name)

        # Clean up existing directories if they exist
        if os.path.exists(screenshots_dir):
            shutil.rmtree(screenshots_dir)

        if os.path.exists(screenshots_dir_export):
            shutil.rmtree(screenshots_dir_export)

        os.makedirs(screenshots_dir_parent, exist_ok=True)

        # Determine the appropriate test scheme based on device type
        test_scheme = "RoamUITests"
        test_class = "RoamUITestsScreenshotTests"
        platform = "iOS Simulator"

        if "Watch" in device_name:
            test_scheme = "RoamWatchUITests"
            test_class = "RoamWatchUITestsScreenshotTests"
            platform = "watchOS Simulator"
        elif "MacBook" in device_name or "Mac" in device_name:
            platform = "macOS"
        elif "Vision" in device_name:
            platform = "visionOS Simulator"

        # Run the UI tests to capture screenshots
        command = (
            f"xcodebuild test -scheme {test_scheme} "
            f"-destination 'platform={platform},name={device_name}' "
            f"-testLanguage {localization} "
            f"-resultBundlePath {screenshots_dir} "
            f"-only-testing '{test_scheme}/{test_class}/testCaptureScreenshots'"
        )

        print(f"Running UI tests for {device_name} in {localization}...")
        result = os.system(command)

        if result != 0:
            print(
                f"Warning: UI tests for {device_name} in {localization} failed with code {result}"
            )
            return None

        # Check if xcparse is installed, and install it if not
        xcparse_check = os.system("which xcparse > /dev/null 2>&1")
        if xcparse_check != 0:
            print(
                "Failed to find xcparse. Please install it using `brew install xcparse` or similar."
            )

        # Extract screenshots from the xcresult bundle
        extract_command = f"xcparse screenshots --os --model {screenshots_dir} {screenshots_dir_export}"
        print(f"Extracting screenshots for {device_name} in {localization}...")
        extract_result = os.system(extract_command)

        if extract_result != 0:
            print(
                f"Warning: Screenshot extraction for {device_name} in {localization} failed with code {extract_result}"
            )
            return None

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
    args = parser.parse_args()

    platforms = [Platform[platform] for platform in args.platform]
    sync_screenshots = args.sync_screenshots

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

        # Mapping between device sizes and App Store Connect display types
        display_type_mapping = {
            # iOS
            "6.9": "APP_IPHONE_65",  # iPhone 16 Plus (6.9")
            "13": "APP_IPAD_PRO_3GEN_129",  # iPad Pro (12.9")
            # watchOS
            "Ultra": "APP_WATCH_ULTRA",  # Apple Watch Ultra
            # visionOS
            "3840_2160": "APP_APPLE_VISION_PRO",  # Apple Vision Pro
            # macOS
            "16": "APP_DESKTOP",  # 16" MacBook Pro
            "2560_1600": "APP_DESKTOP",  # Standard Mac resolution
        }

        for app_version in app_versions:
            if app_version.platform not in platforms:
                continue

            print(f"Processing screenshots for platform: {app_version.platform}")

            for localization in app_version.localizations:
                print(f"  Processing locale: {localization.locale}")

                # Get screenshot sets for this localization
                screenshot_sets = await asc.get_app_screenshot_sets(localization.id)

                # Create a lookup of existing screenshot sets by display type
                existing_sets = {}
                if "data" in screenshot_sets:
                    for set_data in screenshot_sets["data"]:
                        display_type = set_data.get("attributes", {}).get(
                            "screenshotDisplayType"
                        )
                        if display_type:
                            existing_sets[display_type] = set_data["id"]

                # Get screenshots for this platform and locale
                try:
                    screenshots_by_device = metadata_manager.get_screenshots(
                        str(localization.locale)
                    )
                    platform_screenshots = screenshots_by_device.get(
                        app_version.platform, []
                    )

                    for screenshot_export in platform_screenshots:
                        device_size = screenshot_export.size
                        screenshot_path = screenshot_export.path

                        # Skip if we don't have a display type mapping for this device size
                        if device_size not in display_type_mapping:
                            print(
                                f"    No display type mapping for device size {device_size}, skipping"
                            )
                            continue

                        display_type = display_type_mapping[device_size]

                        # Get or create screenshot set
                        if display_type in existing_sets:
                            screenshot_set_id = existing_sets[display_type]
                            print(
                                f"    Using existing screenshot set for {display_type}"
                            )

                            # Clear existing screenshots
                            current_screenshots = await asc.get_app_screenshots(
                                screenshot_set_id
                            )
                            if "data" in current_screenshots:
                                for screenshot in current_screenshots["data"]:
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
                            # Create a new screenshot set
                            print(f"    Creating new screenshot set for {display_type}")
                            set_response = await asc.create_app_screenshot_set(
                                localization.id, display_type
                            )
                            screenshot_set_id = set_response["data"]["id"]
                            existing_sets[display_type] = screenshot_set_id

                        # Find and upload screenshot files
                        if os.path.exists(screenshot_path):
                            print(f"    Uploading screenshots from {screenshot_path}")

                            # Walk through the directory structure to find images
                            for root, _, files in os.walk(screenshot_path):
                                for file in files:
                                    if file.lower().endswith((".png", ".jpg", ".jpeg")):
                                        file_path = os.path.join(root, file)
                                        print(f"      Uploading {file}")

                                        try:
                                            # Upload the screenshot
                                            await asc.create_app_screenshot(
                                                screenshot_set_id, file, file_path
                                            )
                                            print(f"      Successfully uploaded {file}")
                                        except Exception as e:
                                            print(
                                                f"      Error uploading screenshot: {e}"
                                            )
                        else:
                            print(f"    Screenshot path not found: {screenshot_path}")

                except Exception as e:
                    print(
                        f"  Error processing screenshots for {localization.locale}: {e}"
                    )

    print("Sync completed successfully!")


if __name__ == "__main__":
    import asyncio

    asyncio.run(main())
