#!/usr/bin/env python3
"""Push AppStore/metadata.md's description/promotional text/keywords/subtitle
to the live App Store Connect listing draft for Drokpo.

Canonical copy lives in AppStore/metadata.md; this script is how it reaches
ASC. Defaults to --dry-run (prints current-vs-new for each field and writes
nothing) — pass --apply to actually PATCH the listing.

Usage (from a venv with pyjwt, cryptography, requests installed):
    python3 ci/asc_update_metadata.py             # dry run
    python3 ci/asc_update_metadata.py --apply      # writes to ASC

Requires ~/Downloads/AuthKey_DFDRX9AW9K.p8 (or pass --key-path).
"""

import argparse
import re
import time
from pathlib import Path

import jwt
import requests

REPO_ROOT = Path(__file__).resolve().parent.parent
METADATA_PATH = REPO_ROOT / "AppStore/metadata.md"

KEY_ID = "DFDRX9AW9K"
ISSUER_ID = "740fa955-2ad0-4d4c-a447-c67f9c446977"
DEFAULT_KEY_PATH = Path.home() / "Downloads" / f"AuthKey_{KEY_ID}.p8"

APP_ID = "6789103137"
VERSION_ID = "5abe0604-bb94-4346-8bb8-0ba235acaef0"
VERSION_LOC_ID = "64cd7bdd-d3d4-45e6-968d-1e17f3999b2d"
APPINFO_LOC_ID = "72bd73bc-5b35-4246-9379-9e7c089ab8aa"

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
    payload = {
        "iss": ISSUER_ID,
        "iat": now,
        "exp": now + 19 * 60,
        "aud": "appstoreconnect-v1",
    }
    headers = {"kid": KEY_ID, "typ": "JWT"}
    return jwt.encode(payload, private_key, algorithm="ES256", headers=headers)


def parse_metadata(text: str) -> dict:
    """Pull the fields we push to ASC out of AppStore/metadata.md."""
    sections = {}
    current = None
    buf = []
    for line in text.splitlines():
        header = re.match(r"^## (.+)$", line)
        if header:
            if current:
                sections[current] = "\n".join(buf).strip()
            current = header.group(1)
            buf = []
        elif current:
            buf.append(line)
    if current:
        sections[current] = "\n".join(buf).strip()

    def section(prefix: str) -> str:
        for key, value in sections.items():
            if key.startswith(prefix):
                return value
        raise KeyError(f"metadata.md has no '## {prefix}...' section")

    def strip_notes(value: str) -> str:
        # "(Note: ...)" lines are maintainer asides for whoever edits this
        # file, not public listing copy — never push them to ASC.
        cleaned = "\n".join(
            line for line in value.splitlines() if not line.strip().startswith("(Note:")
        ).strip()
        return re.sub(r"\n{3,}", "\n\n", cleaned)

    description = strip_notes(section("Description"))
    promotional_text = strip_notes(section("Promotional text"))
    whats_new = section("What's New")

    return {
        "description": description,
        "promotionalText": promotional_text,
        "keywords": section("Keywords"),
        "subtitle": section("Subtitle"),
        "whatsNew": whats_new,
    }


def get(session: requests.Session, path: str) -> dict:
    resp = session.get(f"{API_BASE}{path}")
    resp.raise_for_status()
    return resp.json()


def patch(session: requests.Session, path: str, attributes: dict) -> requests.Response:
    resource_id = path.rstrip("/").split("/")[-1]
    resource_type = path.rstrip("/").split("/")[-2]
    body = {"data": {"type": resource_type, "id": resource_id, "attributes": attributes}}
    return session.patch(f"{API_BASE}{path}", json=body)


def show_diff(label: str, current: str, new: str) -> bool:
    if current == new:
        print(f"  {label}: unchanged")
        return False
    print(f"  {label}:")
    print(f"    current: {current!r}")
    print(f"    new:     {new!r}")
    return True


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--key-path", type=Path, default=DEFAULT_KEY_PATH)
    parser.add_argument("--apply", action="store_true", help="actually write to ASC (default is dry-run)")
    args = parser.parse_args()

    if not args.key_path.exists():
        raise SystemExit(f"ASC key not found at {args.key_path} — pass --key-path")

    fields = parse_metadata(METADATA_PATH.read_text())

    token = mint_jwt(args.key_path)
    session = requests.Session()
    session.headers["Authorization"] = f"Bearer {token}"

    version = get(session, f"/appStoreVersions/{VERSION_ID}")
    state = version["data"]["attributes"].get("appVersionState")
    print(f"Version 1.0 ({VERSION_ID}) state: {state}")
    if state not in EDITABLE_STATES:
        raise SystemExit(
            f"Version state '{state}' is not editable ({sorted(EDITABLE_STATES)}). "
            "Resolve in App Store Connect before running this script."
        )

    version_loc = get(session, f"/appStoreVersionLocalizations/{VERSION_LOC_ID}")
    loc_attrs = version_loc["data"]["attributes"]

    app_info_loc = get(session, f"/appInfoLocalizations/{APPINFO_LOC_ID}")
    info_attrs = app_info_loc["data"]["attributes"]

    print("\n--- appStoreVersionLocalizations (description / promo text / keywords) ---")
    changed = {}
    if show_diff("description", loc_attrs.get("description", ""), fields["description"]):
        changed["description"] = fields["description"]
    if show_diff("promotionalText", loc_attrs.get("promotionalText", ""), fields["promotionalText"]):
        changed["promotionalText"] = fields["promotionalText"]
    if show_diff("keywords", loc_attrs.get("keywords", ""), fields["keywords"]):
        changed["keywords"] = fields["keywords"]

    print("\n--- appInfoLocalizations (subtitle) ---")
    info_changed = {}
    if show_diff("subtitle", info_attrs.get("subtitle", ""), fields["subtitle"]):
        info_changed["subtitle"] = fields["subtitle"]

    print("\n--- whatsNew (may be rejected on a first version) ---")
    show_diff("whatsNew", loc_attrs.get("whatsNew", "") or "", fields["whatsNew"])

    if not args.apply:
        print("\nDry run only — nothing written. Re-run with --apply to push these changes.")
        return

    if changed:
        resp = patch(session, f"/appStoreVersionLocalizations/{VERSION_LOC_ID}", changed)
        if resp.ok:
            print(f"\nUpdated appStoreVersionLocalizations: {list(changed)}")
        else:
            print(f"\nFAILED to update appStoreVersionLocalizations: {resp.status_code} {resp.text}")

    # whatsNew is attempted separately since ASC rejects it on a first version.
    resp = patch(
        session, f"/appStoreVersionLocalizations/{VERSION_LOC_ID}", {"whatsNew": fields["whatsNew"]}
    )
    if resp.ok:
        print("Updated whatsNew.")
    else:
        print(f"whatsNew update skipped/rejected ({resp.status_code}): {resp.text[:300]}")

    if info_changed:
        resp = patch(session, f"/appInfoLocalizations/{APPINFO_LOC_ID}", info_changed)
        if resp.ok:
            print(f"Updated appInfoLocalizations: {list(info_changed)}")
        else:
            print(f"FAILED to update appInfoLocalizations: {resp.status_code} {resp.text}")


if __name__ == "__main__":
    main()
