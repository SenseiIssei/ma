"""Checks the app's bundle ids at Apple before a signed build.

Xcode's automatic signing fails with a misleading "Authentication failed"
when a bundle id is missing or lacks a capability it wants, because the API
key may not change capabilities. This prints what Apple actually has and
fails early with a readable list of what to tick in the developer portal.

    python3 ci/bundle_ids.py   # env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH
"""

import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from dev_cert import api  # noqa: E402

# bundle id: capabilities it needs (App Store Connect API names)
WANTED = {
    "com.sensei.ma": ["APP_GROUPS", "FAMILY_CONTROLS"],
    "com.sensei.ma.shieldconfig": ["APP_GROUPS", "FAMILY_CONTROLS"],
    "com.sensei.ma.shieldaction": ["APP_GROUPS", "FAMILY_CONTROLS"],
    "com.sensei.ma.monitor": ["APP_GROUPS", "FAMILY_CONTROLS"],
    "com.sensei.ma.filter": ["APP_GROUPS"],
    "com.sensei.ma.widgets": ["APP_GROUPS"],
    "com.sensei.ma.report": ["APP_GROUPS", "FAMILY_CONTROLS"],
    "com.sensei.ma.watchkitapp": [],
}

# Missing ones of these do not stop the build; the app is built without them.
OPTIONAL = {"com.sensei.ma.watchkitapp": "MA_SKIP_WATCH"}


def main():
    status, body = api("GET", "/bundleIds?filter[identifier]=com.sensei.ma&limit=200&include=bundleIdCapabilities")
    if status != 200:
        print(f"::warning::Could not list bundle ids ({status}); skipping the check")
        return
    caps_by_id = {c["id"]: c["attributes"].get("capabilityType") for c in body.get("included", [])}
    found = {}
    for item in body.get("data", []):
        ident = item["attributes"]["identifier"]
        rels = item.get("relationships", {}).get("bundleIdCapabilities", {}).get("data", [])
        found[ident] = sorted(filter(None, (caps_by_id.get(r["id"]) for r in rels)))
    problems = []
    for ident, needed in WANTED.items():
        have = found.get(ident)
        if have is None:
            print(f"{ident}: MISSING")
            if ident in OPTIONAL:
                print(f"::warning::{ident} does not exist yet; building without it. Register it to include it.")
                env = os.environ.get("GITHUB_ENV")
                if env:
                    with open(env, "a", encoding="utf-8") as handle:
                        handle.write(f"{OPTIONAL[ident]}=1\n")
                continue
            problems.append(f"{ident} does not exist yet")
            continue
        print(f"{ident}: {', '.join(have) or 'no capabilities'}")
        for cap in needed:
            if any(h.startswith(cap) for h in have):
                continue
            if cap == "APP_GROUPS":
                problems.append(f"{ident} needs {cap}")
            else:
                # The API does not list every capability type on every
                # account, so a missing Family Controls is only a hint.
                print(f"::warning::{ident} shows no {cap}; tick Family Controls (Development) if it is off")
    if problems:
        for p in problems:
            print(f"::error::{p}")
        print("::error::Fix these under Certificates, Identifiers & Profiles > Identifiers, "
              "then assign group.com.sensei.ma under App Groups > Configure.")
        sys.exit(1)
    print("All bundle ids are ready.")


if __name__ == "__main__":
    main()
