#!/usr/bin/env python3

from dataclasses import dataclass
from datetime import datetime, timedelta
import enum
import gzip
import json
import os
import shutil
import tempfile
import time
from httpx import AsyncClient, Response
import httpx
import jwt

# TODO:
#     - Finish the commands to parse the screenshots and run the tests
#     - Finish the test screenshot capabilities to take some screenshots in light mode, dark mode, settings, keyboard shortcuts, etc...
#     - Ensure each platform has it's own custom screenshots
#     - LATER: Come back and figure out how to clear + reupload localized screenshots for a specific appStoreVersionLocalizations (https://developer.apple.com/documentation/appstoreconnectapi/app-screenshots)


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
class LocalizedWhatsNew:
    ios_whats_new: dict[Language, str]
    visionos_whats_new: dict[Language, str]
    macos_whats_new: dict[Language, str]

    def get_whats_new(self, locale: Language, platform: Platform) -> str | None:
        if platform == Platform.iOS:
            return self.ios_whats_new[locale]
        elif platform == Platform.visionOS:
            return self.visionos_whats_new[locale]
        elif platform == Platform.macOS:
            return self.macos_whats_new[locale]
        else:
            return None


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

    def _get_primary_whats_new(self, platform: Platform) -> str | None:
        # Read workspace/docs/src/pages/changes/<platform>.md
        file_path = os.path.join(
            self.workspace_path, "docs", "src", "pages", "changes", f"{platform}.md"
        )
        if os.path.exists(file_path):
            with open(file_path, "r") as f:
                return f.read().strip()
        else:
            return None

    def _get_localized_whats_new(
        self, platform: Platform, language: Language
    ) -> str | None:
        # Read workspace/docs/i18n/<language>/docusaurus-plugin-content-pages/changes/platform.md
        file_path = os.path.join(
            self.workspace_path,
            "docs",
            "i18n",
            language,
            "docusaurus-plugin-content-pages",
            "changes",
            f"{platform}.md",
        )
        if os.path.exists(file_path):
            with open(file_path, "r") as f:
                return f.read().strip()
        else:
            return None

    def get_update_info_localizations(self) -> LocalizedWhatsNew:
        platforms = dict()
        for platform in Platform:
            en_whats_new = self._get_primary_whats_new(platform)
            if not en_whats_new:
                raise RuntimeError(f"Missing primary whats new for platform {platform}")
            languages = {
                Language.en: en_whats_new,
            }
            for language in Language:
                if language == Language.en:
                    continue

                localized_whats_new = self._get_localized_whats_new(platform, language)
                if localized_whats_new:
                    languages[language] = localized_whats_new
                else:
                    raise RuntimeError(
                        f"Missing localized whats new for platform {platform} and language {language}"
                    )

            platforms[platform] = languages

        return LocalizedWhatsNew(
            ios_whats_new=platforms[Platform.iOS],
            visionos_whats_new=platforms[Platform.visionOS],
            macos_whats_new=platforms[Platform.macOS],
        )

    def get_screenshots(
        self, localization: str
    ) -> dict[Platform, list[ScreenshotExport]]:
        devices = {
            Platform.iOS: [
                ScreenshotSource(device="iPhone 16 Plus", size="6.9"),
                ScreenshotSource(device="iPadPro_M4", size="13"),
                ScreenshotSource(device="AppleWatchUltra2", size="Ultra"),
            ],
            Platform.macOS: [
                ScreenshotSource(device="MacBookPro_16", size="16"),
                ScreenshotSource(device="MacBookPro", size="2560_1600"),
            ],
            Platform.visionOS: [ScreenshotSource(device="VisionPro", size="3840_2160")],
        }

        return [
            [
                ScreenshotExport(
                    size=device.size,
                    path=self._get_device_screenshots(device.device, localization),
                )
                for device in devices[platform]
            ]
            for platform in self.screenshot_update_platforms
        ]

    def _get_device_screenshots(self, device_name: str, localization: str) -> str:
        # Create in root/tmp dir/auto-screenshots/{device_name}/{localization}
        # Get root (hd root not workspace root) -> tmp dir

        tmp = tempfile.gettempdir()
        screenshots_dir = os.path.join(
            tmp, "auto-screenshots", device_name, f"${localization}.xcresult"
        )
        screenshots_dir_export = os.path.join(
            tmp, "auto-screenshots", device_name, f"${localization}.export"
        )
        screenshots_dir_parent = os.path.join(tmp, "auto-screenshots", device_name)

        if os.path.exists(screenshots_dir):
            # Delete the dir
            shutil.rmtree(screenshots_dir)

        if os.path.exists(screenshots_dir_export):
            # Delete the dir
            shutil.rmtree(screenshots_dir_export)

        os.makedirs(screenshots_dir_parent, exist_ok=True)

        # Run these
        # `xcodebuild test -scheme RoamUITests -destination 'platform=iOS Simulator,name={device_name},OS=latest' -testLanguage {localization} -resultBundlePath {screenshots_dir} -only-testing 'RoamUITests/RoamUITestsLaunchTests'`
        # xcparse screenshots {screenshots_dir} {screenshots_dir_export}

        raise NotImplementedError

        return screenshots_dir_export


async def main():
    # Parse key id and issuer id from APPSTORECONNECT_API_KEY, APPSTORECONNECT_API_ISSUER env variables
    key_id = os.environ.get("APPSTORECONNECT_API_KEY")
    issuer_id = os.environ.get("APPSTORECONNECT_API_ISSUER")
    if not key_id:
        raise ValueError("Missing APPSTORECONNECT_API_KEY environment variable")
    if not issuer_id:
        raise ValueError("Missing APPSTORECONNECT_API_ISSUER environment variable")

    user_home = os.path.expanduser("~")
    key_file = os.path.join(user_home, ".private_keys", f"AuthKey_{key_id}.p8")

    if not os.path.exists(key_file):
        raise ValueError(f"Private key file not found: {key_file}")

    token_manager = TokenManager(key_id, issuer_id, key_file)

    asc = AppStoreConnect(token_manager, debug=False)

    app_versions = await asc.get_upcoming_app_store_versions("6469834197")

    metadata_manager = MetadataManager(
        workspace_path=".", screenshot_update_platforms=[]
    )

    localized_whats_new = metadata_manager.get_update_info_localizations()
    for app_version in app_versions:
        print("Updating version: ", app_version.platform)
        for localization in app_version.localizations:
            print("    Updating localization: ", localization.locale)

            whats_new = localized_whats_new.get_whats_new(
                localization.locale, app_version.platform
            )

            if not whats_new:
                raise RuntimeError(
                    f"Missing localized whats new for {app_version.platform} and {localization.locale}"
                )

            await asc.update_localization(localization.id, {"whatsNew": whats_new})

    # https://developer.apple.com/documentation/appstoreconnectapi/post-v1-appstoreversionlocalizations
    # https://developer.apple.com/documentation/appstoreconnectapi/get-v1-appstoreversionlocalizations-_id_-appscreenshotsets


if __name__ == "__main__":
    import asyncio

    asyncio.run(main())
