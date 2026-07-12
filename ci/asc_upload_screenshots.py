#!/usr/bin/env python3
"""Upload AppStore/screenshots/iphone-6.9/*.png to the live App Store Connect
listing draft for Drokpo.

The App Store Connect API has no distinct 6.9" screenshotDisplayType enum
value — 'APP_IPHONE_67' is the slot for the largest iPhone screenshots;
ASC classifies the actual size class from each image's pixel dimensions.

Usage (from a venv with pyjwt, cryptography, requests installed):
    python3 ci/asc_upload_screenshots.py             # dry run (lists files, no writes)
    python3 ci/asc_upload_screenshots.py --apply      # uploads to ASC

Requires ~/Downloads/AuthKey_DFDRX9AW9K.p8 (or pass --key-path).
"""

import argparse
import hashlib
import time
from pathlib import Path

import jwt
import requests

REPO_ROOT = Path(__file__).resolve().parent.parent
SCREENSHOTS_DIR = REPO_ROOT / "AppStore/screenshots/iphone-6.9"

KEY_ID = "DFDRX9AW9K"
ISSUER_ID = "740fa955-2ad0-4d4c-a447-c67f9c446977"
DEFAULT_KEY_PATH = Path.home() / "Downloads" / f"AuthKey_{KEY_ID}.p8"

VERSION_ID = "5abe0604-bb94-4346-8bb8-0ba235acaef0"
VERSION_LOC_ID = "64cd7bdd-d3d4-45e6-968d-1e17f3999b2d"
DISPLAY_TYPE = "APP_IPHONE_67"  # largest-iPhone slot; 1320x2868 files classify as 6.9"

EDITABLE_STATES = {
    "PREPARE_FOR_SUBMISSION",
    "DEVELOPER_REJECTED",
    "REJECTED",
    "METADATA_REJECTED",
}

API_BASE = "https://api.appstoreconnect.apple.com/v1"


def mint_jwt(key_path: Path) -> str:
    private_key = key_path.read_text()
    now = int(time.time())
    payload = {"iss": ISSUER_ID, "iat": now, "exp": now + 19 * 60, "aud": "appstoreconnect-v1"}
    headers = {"kid": KEY_ID, "typ": "JWT"}
    return jwt.encode(payload, private_key, algorithm="ES256", headers=headers)


def get_or_create_screenshot_set(session: requests.Session) -> str:
    resp = session.get(
        f"{API_BASE}/appStoreVersionLocalizations/{VERSION_LOC_ID}/appScreenshotSets"
    )
    resp.raise_for_status()
    for item in resp.json()["data"]:
        if item["attributes"]["screenshotDisplayType"] == DISPLAY_TYPE:
            return item["id"]

    body = {
        "data": {
            "type": "appScreenshotSets",
            "attributes": {"screenshotDisplayType": DISPLAY_TYPE},
            "relationships": {
                "appStoreVersionLocalization": {
                    "data": {"type": "appStoreVersionLocalizations", "id": VERSION_LOC_ID}
                }
            },
        }
    }
    resp = session.post(f"{API_BASE}/appScreenshotSets", json=body)
    resp.raise_for_status()
    return resp.json()["data"]["id"]


def clear_existing_screenshots(session: requests.Session, set_id: str) -> None:
    resp = session.get(f"{API_BASE}/appScreenshotSets/{set_id}/appScreenshots")
    resp.raise_for_status()
    for item in resp.json()["data"]:
        session.delete(f"{API_BASE}/appScreenshots/{item['id']}").raise_for_status()


def upload_screenshot(session: requests.Session, set_id: str, path: Path) -> None:
    file_bytes = path.read_bytes()

    body = {
        "data": {
            "type": "appScreenshots",
            "attributes": {"fileName": path.name, "fileSize": len(file_bytes)},
            "relationships": {
                "appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}
            },
        }
    }
    resp = session.post(f"{API_BASE}/appScreenshots", json=body)
    resp.raise_for_status()
    data = resp.json()["data"]
    screenshot_id = data["id"]
    upload_operations = data["attributes"]["uploadOperations"]

    for op in upload_operations:
        offset, length = op["offset"], op["length"]
        chunk = file_bytes[offset : offset + length]
        headers = {h["name"]: h["value"] for h in op["requestHeaders"]}
        put_resp = requests.request(op["method"], op["url"], data=chunk, headers=headers)
        put_resp.raise_for_status()

    checksum = hashlib.md5(file_bytes).hexdigest()
    patch_body = {
        "data": {
            "type": "appScreenshots",
            "id": screenshot_id,
            "attributes": {"uploaded": True, "sourceFileChecksum": checksum},
        }
    }
    resp = session.patch(f"{API_BASE}/appScreenshots/{screenshot_id}", json=patch_body)
    resp.raise_for_status()
    print(f"  uploaded {path.name} -> {screenshot_id}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--key-path", type=Path, default=DEFAULT_KEY_PATH)
    parser.add_argument("--apply", action="store_true", help="actually upload (default is dry-run)")
    args = parser.parse_args()

    if not args.key_path.exists():
        raise SystemExit(f"ASC key not found at {args.key_path} — pass --key-path")

    files = sorted(SCREENSHOTS_DIR.glob("*.png"))
    if not files:
        raise SystemExit(f"No PNGs found in {SCREENSHOTS_DIR}")

    print(f"Screenshots to upload ({DISPLAY_TYPE}, sourced from {SCREENSHOTS_DIR}):")
    for f in files:
        print(f"  {f.name} ({f.stat().st_size} bytes)")

    if not args.apply:
        print("\nDry run only — nothing uploaded. Re-run with --apply to push these to ASC.")
        return

    token = mint_jwt(args.key_path)
    session = requests.Session()
    session.headers["Authorization"] = f"Bearer {token}"

    version = session.get(f"{API_BASE}/appStoreVersions/{VERSION_ID}")
    version.raise_for_status()
    state = version.json()["data"]["attributes"].get("appVersionState")
    print(f"\nVersion 1.0 ({VERSION_ID}) state: {state}")
    if state not in EDITABLE_STATES:
        raise SystemExit(
            f"Version state '{state}' is not editable ({sorted(EDITABLE_STATES)}). "
            "Resolve in App Store Connect before running this script."
        )

    set_id = get_or_create_screenshot_set(session)
    print(f"appScreenshotSet: {set_id}")

    clear_existing_screenshots(session, set_id)

    for f in files:
        upload_screenshot(session, set_id, f)

    print("\nDone. Verify asset processing state in App Store Connect (Media Manager).")


if __name__ == "__main__":
    main()
