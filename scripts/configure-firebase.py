#!/usr/bin/env python3
import base64
import os
import plistlib
from pathlib import Path

bundle = "com.ftcteamhub.app"
resources = Path(__file__).resolve().parents[1] / "Resources"
app_plist = resources / "Info.plist"
firebase_plist = resources / "GoogleService-Info.plist"
encoded = os.getenv("FTCTEAMHUB_FIREBASE_PLIST_BASE64", "")
if not encoded and not firebase_plist.exists():
    print("Firebase options unavailable. Google Sign-In will display a configuration notice.")
    raise SystemExit(0)

try:
    raw = base64.b64decode("".join(encoded.split()), validate=True) if encoded else firebase_plist.read_bytes()
    options = plistlib.loads(raw)
    client = options["CLIENT_ID"]
    scheme = options["REVERSED_CLIENT_ID"]
    if (not client.endswith(".apps.googleusercontent.com")
            or ".".join(reversed(client.split("."))) != scheme
            or options["BUNDLE_ID"] != bundle
            or not all(options.get(key) for key in ("API_KEY", "PROJECT_ID", "GOOGLE_APP_ID"))):
        raise ValueError("Configuration does not match app")
except (KeyError, ValueError, TypeError, AttributeError, plistlib.InvalidFileException):
    raise SystemExit("Firebase setup requires a valid iOS plist with a matching CLIENT_ID and REVERSED_CLIENT_ID.") from None

info = plistlib.loads(app_plist.read_bytes())
info["GIDClientID"] = client
url_types = [entry for entry in info.get("CFBundleURLTypes", []) if entry.get("CFBundleURLName") != "Google Sign-In"]
url_types.append({"CFBundleURLName": "Google Sign-In", "CFBundleURLSchemes": [scheme]})
info["CFBundleURLTypes"] = url_types
firebase_plist.write_bytes(raw)
app_plist.write_bytes(plistlib.dumps(info, sort_keys=False))
print("Firebase bundle ID and Google callback validated.")
