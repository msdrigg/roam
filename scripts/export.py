#!/usr/bin/env python3

import re
import subprocess
from datetime import datetime
import argparse
import http.client
import os
import plistlib
import random
import shutil
import sys
import tempfile
import time
import uuid
from typing import Tuple
import urllib.error
import urllib.request

# 1. Before running, make sure you create an API key from App Store Connect
#     (App Store Connect -> Users and Access -> Integrations -> App Store Connect API) and store the downloaded key in ~/.private_keys
# 2. Then set the following environment variables:
#     XCODE_API_KEY="API_KEY_ID"
#     XCODE_API_ISSUER="API_ISSUER_ID"
#
#     Find both of these values in App Store Connect web after creating the API key
#
# Which key to use (verified 2026-07-22): use XCODE_API_KEY=ZWF866Z497 with
# XCODE_API_ISSUER=cbcdbb0a-aae2-46de-af95-4700664fad72. It is the only key in
# ~/.private_keys with App Store Connect distribution access. The others fail:
#   - V7DX9R58N2 -> "Cloud signing permission error" / no "iOS Distribution" certificate
#   - 834ACPS85P -> "Unauthenticated" / "No Accounts with App Store Connect Access"
#   - PBG7VN88T9 -> "Unauthenticated" / "No Accounts with App Store Connect Access"
# The two Unauthenticated keys likely belong to a different issuer than the one above.


# The entitlement that means "this build can attest", per platform.
#
# Apple publishes `appattest-environment` for iOS, iPadOS, tvOS and visionOS
# only, and its value picks the environment the attestation is issued against --
# Vars.xcconfig interpolates it so a Debug build cannot claim production.
#
# macOS and watchOS are not on that list, even though DCAppAttestService itself
# is declared for macOS 11 and watchOS 9. Those two use `app-attest-opt-in`
# instead, from the App ID's "App Attest opt-in" capability, and Xcode drops the
# environment key from their builds without a word. That is the whole of the bug
# this file used to have: it demanded the iOS key everywhere, so no macOS archive
# could pass, and the watch app inside the iOS archive shipped unattested because
# nothing looked at it.
ATTEST_ENTITLEMENTS = {
    "iOS": "com.apple.developer.devicecheck.appattest-environment",
    "visionOS": "com.apple.developer.devicecheck.appattest-environment",
    "macOS": "com.apple.developer.devicecheck.app-attest-opt-in",
}

WATCH_ATTEST_ENTITLEMENT = "com.apple.developer.devicecheck.app-attest-opt-in"


def signed_entitlements(app: str) -> dict:
    """The entitlements actually in the signature, not the ones we asked for."""
    result = subprocess.run(
        ["codesign", "-d", "--entitlements", "-", "--xml", app],
        capture_output=True,
    )
    if result.returncode != 0 or not result.stdout:
        raise SystemExit(
            f"Could not read entitlements from {app}: "
            f"codesign exited {result.returncode}\n"
            f"{result.stderr.decode(errors='replace').strip()}"
        )
    return plistlib.loads(result.stdout)


def verify_archived_attest_entitlement(platform: str, archive_path: str):
    """Prove the App Attest entitlement made it into the artifact that was built.

    Nothing secret ships in the bundle any more, but the app still cannot reach
    the backend without this entitlement: `DCAppAttestService` refuses to
    generate a key, every request falls through to the unattested path, and the
    build goes out with a developer chat that answers 401. The failure modes
    this catches are a renamed variable, a target that lost its
    baseConfigurationReference, a stale build directory, and -- the one that
    actually happened -- an entitlement the provisioning profile does not grant,
    which Xcode drops at signing without a warning.

    macOS keeps its App Store receipt as a fallback for Macs below macOS 27,
    where App Attest does not exist, so a Mac that cannot attest still reaches
    the backend. That fallback is not a licence to ship the entitlement missing:
    it costs those installs the hardware-backed credential and leans the whole
    platform on the replayable one.
    """
    import glob

    entitlement = ATTEST_ENTITLEMENTS.get(platform)
    if entitlement is None:
        raise SystemExit(f"No App Attest entitlement is defined for {platform}")
    candidates = glob.glob(f"{archive_path}/Products/Applications/*.app")
    if not candidates:
        raise SystemExit(f"No app bundle found in {archive_path}")

    embedded = glob.glob(f"{archive_path}/Products/Applications/*.app/Watch/*.app")

    for app in candidates:
        value = signed_entitlements(app).get(entitlement)
        if not value:
            raise SystemExit(
                f"{platform}: {app} carries no {entitlement} entitlement.\n"
                "The archive would ship unable to authenticate against the "
                "backend (developer chat, diagnostics upload). Check that the "
                "App ID has the matching capability enabled -- Xcode strips "
                "entitlements the provisioning profile does not grant without "
                "reporting it. Refusing to continue."
            )
        print(f"App Attest entitlement present in {app} ({entitlement} = {value})")

    # The watch app rides inside the iOS archive with its own bundle id, its own
    # App ID and so its own capabilities, and it is the one bundle here with no
    # fallback of any kind: watchOS compiles no receipt path. It also takes the
    # watchOS entitlement rather than the archive platform's, which is why it is
    # checked separately instead of being folded into the loop above.
    for app in embedded:
        value = signed_entitlements(app).get(WATCH_ATTEST_ENTITLEMENT)
        if not value:
            raise SystemExit(
                f"{app} carries no {WATCH_ATTEST_ENTITLEMENT} entitlement.\n"
                "The watch app would ship unable to authenticate against the "
                "backend at all, since watchOS has no receipt fallback. Check "
                "that its App ID has App Attest opt-in enabled -- Xcode strips "
                "entitlements the profile does not grant without reporting it. "
                "Refusing to continue."
            )
        print(
            f"App Attest entitlement present in {app} "
            f"({WATCH_ATTEST_ENTITLEMENT} = {value})"
        )


def archive_application(platform: str, render_github_actions: bool = False):
    scheme = "Roam"
    project_path = "."
    archive_path = f"{project_path}/Archives/XCArchives/{platform}.xcarchive"
    # First remove directory and all its contents
    subprocess.run(f'rm -rf "{archive_path}"', shell=True)
    print(f"Archiving application for platform {platform}")
    subprocess.run(
        f"""set -o pipefail && xcodebuild archive -project "{project_path}/Roam.xcodeproj" -scheme "{scheme}" -archivePath "{archive_path}" -destination 'generic/platform={platform}'{arch_args(platform)}{authentication_args()} | xcbeautify{' --renderer github-actions' if render_github_actions else ''}""",
        shell=True,
        check=True,
    )
    verify_archived_attest_entitlement(platform, archive_path)
    print(f"Archive succeeded for platform {platform}")


def arch_args(platform: str) -> str:
    """Force Apple silicon only on macOS.

    The project sets ARCHS/EXCLUDED_ARCHS for the macosx SDK, but Xcode builds
    Swift package products (RoamGRDB.framework) with the full architecture set
    regardless of project-level conditionals, so the embedded framework comes
    out x86_64+arm64 fat. Passing ARCHS on the command line does reach the
    package build, which halves the framework (7.29 MB -> 3.77 MB).
    """
    if platform != "macOS":
        return ""
    return " ARCHS=arm64 ONLY_ACTIVE_ARCH=NO"


def authentication_args() -> str:
    """App Store Connect credentials plus -allowProvisioningUpdates.

    The archive needs these as much as the export does: every target signs
    automatically, so on a machine that has never built Roam there are no
    profiles on disk and Xcode has to mint them. Without the flag it fails with
    "No profiles for 'com.msdrigg.roam.…' were found ... Automatic signing is
    disabled and unable to generate a profile."
    """
    api_key = os.environ.get("XCODE_API_KEY")
    api_issuer = os.environ.get("XCODE_API_ISSUER")
    if not api_key or not api_issuer:
        return ""
    key_path = os.path.expanduser(f"~/.private_keys/AuthKey_{api_key}.p8")
    return (
        f" -authenticationKeyID {api_key}"
        f" -authenticationKeyIssuerID {api_issuer}"
        f" -authenticationKeyPath {key_path}"
        f" -allowProvisioningUpdates"
    )


def publish_to_app_store(platform: str, render_github_actions: bool = False):
    print(f"Exporting for platform {platform}")
    auth_args = authentication_args()
    subprocess.run(
        f"""set -o pipefail && xcodebuild -exportArchive -archivePath "./Archives/XCArchives/{platform}.xcarchive" -exportPath "./Archives/Exports/{platform}" -exportOptionsPlist ./scripts/options.plist{auth_args} | xcbeautify{' --renderer github-actions' if render_github_actions else ''}""",
        shell=True,
        check=True,
    )

    print(f"Publish succeeded for platform {platform}")


def load_dotenv(path: str) -> dict[str, str]:
    values: dict[str, str] = {}
    if not os.path.exists(path):
        return values

    with open(path, "r") as file:
        for raw_line in file:
            line = raw_line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            key = key.strip()
            value = value.strip().strip('"').strip("'")
            values[key] = value

    return values


def resolve_required_config(
    name: str,
    cli_value: str | None,
    dotenv_values: dict[str, str],
) -> str:
    value = cli_value or os.environ.get(name) or dotenv_values.get(name)
    if not value:
        raise ValueError(
            f"{name} is required. Pass --{name.lower().replace('_', '-')} or add {name}=... to .env"
        )
    return value


class MultipartBody:
    """Concatenates the multipart prefix, the zip file, and the closing boundary
    into one readable stream. `http.client` reads request bodies in 8 KB blocks
    when the object exposes `read`, so nothing larger than that is ever held in
    memory on either end of the upload."""

    def __init__(self, prefix: bytes, file, suffix: bytes):
        self._parts = [prefix, file, suffix]
        self._index = 0

    def read(self, size: int = -1) -> bytes:
        while self._index < len(self._parts):
            part = self._parts[self._index]
            if isinstance(part, bytes):
                if size is None or size < 0:
                    self._index += 1
                    if part:
                        return part
                    continue
                chunk, remainder = part[:size], part[size:]
                self._parts[self._index] = remainder
                if chunk:
                    return chunk
                self._index += 1
                continue

            chunk = part.read(size)
            if chunk:
                return chunk
            self._index += 1
        return b""


# Delays before the 2nd..7th attempts - seven tries over ~7 minutes. The backend
# is a single small Fly machine that 502s while it restarts or pages in a large
# upload. The old ladder gave up after 45s, which is not long enough: a machine
# that has scaled to zero can take minutes to come back with a multi-hundred-MB
# upload arriving at the same time, and 45s of patience is how roam 1.49's and
# 1.51's symbols went missing on otherwise green runs. Seven minutes of waiting
# is cheap next to a release whose crash reports cannot be symbolicated.
RETRY_DELAYS_SECONDS = (5, 15, 30, 60, 120, 180)

# Retries are spread +/-20% so that the per-platform uploads in one run, which
# tend to fail together when the machine restarts, do not then march back in
# lockstep and hit it with three simultaneous retries.
RETRY_JITTER = 0.2


def is_retryable(error: Exception) -> bool:
    """Whether a later attempt could plausibly succeed.

    A 4xx other than 408/429 means the request itself is wrong - bad api key,
    payload too large - and will be just as wrong in seven minutes, so it fails
    immediately instead of stretching the build to reach the same conclusion.
    """
    if isinstance(error, urllib.error.HTTPError):
        return error.code in (408, 429) or 500 <= error.code < 600
    # URLError covers DNS and connection-refused; HTTPException covers the
    # half-read responses (RemoteDisconnected, IncompleteRead, BadStatusLine)
    # that a proxy hands back when it drops a long upload mid-flight; the rest
    # come straight off the socket on a timeout or reset.
    return isinstance(
        error,
        (
            urllib.error.URLError,
            http.client.HTTPException,
            TimeoutError,
            ConnectionError,
        ),
    )


def with_retries(operation, what: str):
    attempts = len(RETRY_DELAYS_SECONDS) + 1
    for index, delay in enumerate(RETRY_DELAYS_SECONDS + (None,)):
        try:
            return operation()
        except Exception as error:
            if delay is None or not is_retryable(error):
                raise
            if isinstance(error, urllib.error.HTTPError):
                reason = f"HTTP {error.code}"
            else:
                reason = f"{type(error).__name__}: {error}"
            delay = round(delay * random.uniform(1 - RETRY_JITTER, 1 + RETRY_JITTER), 1)
            print(
                f"  {what} failed ({reason}) - retrying in {delay}s "
                f"[attempt {index + 2} of {attempts}]",
                flush=True,
            )
            time.sleep(delay)


def upload_dsyms(
    platform: str,
    backend_url: str,
    crash_api_key: str,
    bundle_identifier: str,
):
    archive_path = f"./Archives/XCArchives/{platform}.xcarchive"
    dsym_dir = f"{archive_path}/dSYMs"
    if not os.path.isdir(dsym_dir):
        raise FileNotFoundError(f"No dSYMs directory found at {dsym_dir}")

    app_version, build_version = get_current_versions()
    backend_url = backend_url.rstrip("/")

    print(
        f"Uploading dSYMs for {platform} {bundle_identifier} {app_version} ({build_version})"
    )
    with tempfile.TemporaryDirectory() as tmp:
        zip_base = os.path.join(tmp, f"{platform}-dSYMs")
        zip_path = shutil.make_archive(zip_base, "zip", root_dir=archive_path, base_dir="dSYMs")

        # Streamed as multipart/form-data rather than base64 in a JSON body. The
        # zip runs to hundreds of MB and buffering it (plus its base64 inflation)
        # OOM-killed the 256 MB Fly machine.
        boundary = f"----RoamDsymUpload{uuid.uuid4().hex}"
        fields = {
            "bundleIdentifier": bundle_identifier,
            "appVersion": app_version,
            "buildVersion": build_version,
            "platform": platform,
        }

        prefix = b""
        for name, value in fields.items():
            prefix += (
                f"--{boundary}\r\n"
                f'Content-Disposition: form-data; name="{name}"\r\n\r\n'
                f"{value}\r\n"
            ).encode("utf-8")
        prefix += (
            f"--{boundary}\r\n"
            f'Content-Disposition: form-data; name="dsymZip"; filename="{platform}-dSYMs.zip"\r\n'
            f"Content-Type: application/zip\r\n\r\n"
        ).encode("utf-8")
        suffix = f"\r\n--{boundary}--\r\n".encode("utf-8")

        zip_size = os.path.getsize(zip_path)
        content_length = len(prefix) + zip_size + len(suffix)
        print(f"  zip is {zip_size / (1024 * 1024):.1f} MB, streaming multipart upload")

        with open(zip_path, "rb") as file:

            def attempt() -> str:
                # Both the seek and the fresh MultipartBody are required per
                # attempt: the body consumes `_parts` as it streams (byte chunks
                # are sliced away and the file is read to EOF), so reusing it
                # would upload an empty payload under a Content-Length promising
                # the whole zip, and hang until the timeout.
                file.seek(0)
                request = urllib.request.Request(
                    f"{backend_url}/v2/upload-roam-dsym",
                    data=MultipartBody(prefix, file, suffix),
                    headers={
                        "Content-Type": f"multipart/form-data; boundary={boundary}",
                        "Content-Length": str(content_length),
                        "x-api-key": crash_api_key,
                    },
                    method="POST",
                )
                try:
                    with urllib.request.urlopen(request, timeout=900) as response:
                        return response.read().decode("utf-8")
                except urllib.error.HTTPError as error:
                    # Read the body here - the connection is closed by the time
                    # the retry loop or the caller formats the message.
                    error.detail = error.read().decode("utf-8", errors="replace")
                    raise

            try:
                response_body = with_retries(attempt, f"dSYM upload for {platform}")
            except urllib.error.HTTPError as error:
                raise RuntimeError(
                    f"dSYM upload failed for {platform}: "
                    f"HTTP {error.code} {getattr(error, 'detail', '')}"
                ) from error
            print(f"dSYM upload succeeded for {platform}: {response_body}")


def try_upload_dsyms(
    platform: str,
    backend_url: str,
    crash_api_key: str,
    bundle_identifier: str,
    render_github_actions: bool = False,
) -> bool:
    """Upload symbols without letting a failure block the *remaining* platforms.

    Publishing and symbol upload are interleaved per platform, so raising here
    stops every later platform from being published at all: one HTTP 502 on the
    iOS dSYM upload left macOS and visionOS unshipped. Symbols can be re-uploaded
    at any time with `--upload-dsyms`; a half-published release cannot be undone.

    Swallowing the error is therefore only about *ordering*, not severity - the
    caller collects the failures and exits non-zero once every platform has had
    its turn. A build whose symbols never arrived is a broken build: its crash
    reports come back with every app frame unresolved, which also means they
    match no auto-review rule and land in the manual queue with nothing to read.
    """
    try:
        upload_dsyms(platform, backend_url, crash_api_key, bundle_identifier)
        return True
    except Exception as error:
        # ::error:: surfaces in the Actions summary instead of scrolling past in
        # the log. The run is going to fail on this; say so where it is visible.
        prefix = "::error::" if render_github_actions else "ERROR: "
        print(
            f"{prefix}dSYM upload failed for {platform}: {error}",
            flush=True,
        )
        return False


def get_current_versions() -> Tuple[str, str]:
    project_file_path = "./Roam.xcodeproj/project.pbxproj"

    with open(project_file_path, "r") as file:
        project_contents = file.readlines()

    # Any dotted numeric version, not just two components: `git describe` will
    # hand back a three-component tag sooner or later, bump_versions() will
    # happily write `MARKETING_VERSION = 1.50.1;`, and a two-component-only
    # pattern would then fail to read back what it just wrote.
    marketing_version_line = [
        line
        for line in project_contents
        if re.search(r"MARKETING_VERSION = \d+(\.\d+)*;", line)
    ]

    current_version_line = [
        line
        for line in project_contents
        if re.search(r"CURRENT_PROJECT_VERSION = \d+\.\w+\.\d+", line)
    ]

    if not marketing_version_line:
        raise ValueError("Could not find marketing version in project file")
    if not current_version_line:
        raise ValueError("Could not find current version in project file")

    current_marketing_version = (
        marketing_version_line[0].split("=")[1].strip().strip(";")
    )
    current_version = current_version_line[0].split("=")[1].strip().strip(";")

    return current_marketing_version, current_version


def get_marketing_version():
    git_tag = (
        subprocess.check_output(["git", "describe", "--tags", "--abbrev=0"])
        .decode("utf-8")
        .strip()
    )
    return git_tag.strip("v")


def get_git_build_number():
    last_commit_sha = (
        subprocess.check_output(["git", "rev-parse", "--short", "HEAD"])
        .decode("utf-8")
        .strip()
    )
    decimal_sha = int(last_commit_sha, 16)
    # Last 8 characters of the SHA
    return f"{decimal_sha}"[-7:]


def get_build_version():
    date_str = datetime.now().strftime("%Y%m%d")
    git_commit = get_git_build_number()

    _, build_version = get_current_versions()
    patch_version = 0
    if build_version.startswith(f"{date_str}.{git_commit}"):
        patch_version = int(build_version.split(".")[-1]) + 1

    return f"{date_str}.{git_commit}.{patch_version}"


def version_sort_key(version: str) -> Tuple[int, ...]:
    return tuple(int(part) for part in re.findall(r"\d+", version))


def bump_versions():
    project_file_path = "./Roam.xcodeproj/project.pbxproj"

    current_marketing_version, current_build_version = get_current_versions()
    new_marketing_version, new_build_version = (
        get_marketing_version(),
        get_build_version(),
    )

    # `git describe` only sees tags that were actually pushed, so a tag living
    # only on a developer's machine leaves CI a release behind -- and the sed
    # below will happily rewrite MARKETING_VERSION *downwards*. That is how a
    # 1.50 project archived and uploaded itself to App Store Connect as 1.49.
    if version_sort_key(new_marketing_version) < version_sort_key(
        current_marketing_version
    ):
        raise SystemExit(
            f"Refusing to downgrade MARKETING_VERSION "
            f"{current_marketing_version} -> {new_marketing_version}.\n"
            f"The newest tag reachable from HEAD is v{new_marketing_version}, but "
            f"the project is already at {current_marketing_version}. Push the "
            f"newer tag (git push origin v{current_marketing_version}) or tag the "
            "release you actually intend to ship."
        )

    sed_cmd_marketing_version = f"sed -i '' 's/MARKETING_VERSION = {current_marketing_version};/MARKETING_VERSION = {new_marketing_version};/g' {project_file_path}"
    subprocess.run(sed_cmd_marketing_version, shell=True, check=True)

    sed_cmd_build_version = f"sed -i '' 's/CURRENT_PROJECT_VERSION = {current_build_version};/CURRENT_PROJECT_VERSION = {new_build_version};/g' {project_file_path}"
    subprocess.run(sed_cmd_build_version, shell=True, check=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Xcode exporting and publishing script"
    )

    parser.add_argument(
        "--archive",
        help="Build and archive the application",
        action="store_true",
    )

    parser.add_argument(
        "--publish",
        help="Publish the application to App Store Connect",
        action="store_true",
    )

    parser.add_argument(
        "--platform",
        help="Platform to build and publish",
        choices=["macOS", "iOS", "visionOS"],
        nargs="+",
    )

    parser.add_argument(
        "--github-actions",
        help="Render output for GitHub Actions",
        action="store_true",
    )
    parser.add_argument(
        "--no-bump",
        help="Don't update versions to match git",
        action="store_true",
    )
    parser.add_argument(
        "--upload-dsyms",
        help="Upload archived dSYMs to the Roam backend",
        action="store_true",
    )
    parser.add_argument(
        "--backend-url",
        help="Backend base URL. Falls back to BACKEND_URL in the environment or .env",
    )
    parser.add_argument(
        "--crash-api-key",
        help="Crash and symbolication API key. Falls back to CRASH_API_KEY in "
        "the environment or .env",
    )
    parser.add_argument(
        "--bundle-identifier",
        help="Bundle identifier to record with the dSYM upload",
        default="com.msdrigg.roam",
    )
    parser.add_argument(
        "--bump-versions",
        help="Update the marketing and build versions in the Xcode project to match git before building",
        action="store_true",
    )
    parser.add_argument(
        "--env-file",
        help="Path to the env file used for backend upload settings",
        default=".env",
    )

    args = parser.parse_args()

    if args.bump_versions:
        bump_versions()

    # Only an archive may renumber the project. Bumping on a bare --publish
    # rewrites project.pbxproj *after* the .xcarchive was built, so the upload
    # would carry one version while the binary inside it carries another --
    # and --upload-dsyms would file the symbols under the wrong build.
    if not args.no_bump and args.archive:
        bump_versions()

    if args.archive:
        for platform in args.platform or []:
            archive_application(platform, render_github_actions=args.github_actions)

    backend_url = None
    crash_api_key = None
    dsym_failures: list[str] = []
    if args.upload_dsyms:
        dotenv_values = load_dotenv(args.env_file)
        try:
            backend_url = resolve_required_config(
                "BACKEND_URL", args.backend_url, dotenv_values
            )
            crash_api_key = resolve_required_config(
                "CRASH_API_KEY", args.crash_api_key, dotenv_values
            )
        except ValueError as error:
            parser.error(str(error))

    if args.publish:
        # A bare --publish uploads an archive built by an earlier invocation,
        # which may predate the pre-flight check, so re-verify the artifact.
        for platform in args.platform or []:
            verify_archived_attest_entitlement(
                platform, f"./Archives/XCArchives/{platform}.xcarchive"
            )
        for platform in args.platform or []:
            publish_to_app_store(platform, render_github_actions=args.github_actions)
            if args.upload_dsyms and not try_upload_dsyms(
                platform,
                backend_url,
                crash_api_key,
                args.bundle_identifier,
                render_github_actions=args.github_actions,
            ):
                dsym_failures.append(platform)
    elif args.upload_dsyms:
        for platform in args.platform or []:
            if not try_upload_dsyms(
                platform,
                backend_url,
                crash_api_key,
                args.bundle_identifier,
                render_github_actions=args.github_actions,
            ):
                dsym_failures.append(platform)

    if dsym_failures:
        # Deferred to here rather than raised at the failing upload so that every
        # platform still got published - see try_upload_dsyms. By this point
        # there is nothing left to protect, and a green run would be a lie: the
        # release is out with no symbols behind it.
        summary = (
            f"Symbols were NOT uploaded for: {', '.join(dsym_failures)}.\n"
            f"Crash reports from this build cannot be symbolicated until they are."
        )
        if args.github_actions:
            print(f"::error title=dSYM upload failed::{summary}", flush=True)
        print(
            f"\n{summary}\n"
            f"Re-run once the backend is healthy (this does not rebuild or "
            f"republish anything):\n"
            f"    ./scripts/export.py --upload-dsyms --no-bump --platform "
            f"{' '.join(dsym_failures)}",
            flush=True,
        )
        sys.exit(1)
