#!/usr/bin/env python3
"""Builds docs/source.json from the published GitHub releases and writes docs/icon.png."""
import json, math, os, struct, urllib.request, zlib

REPO = os.environ.get("GITHUB_REPOSITORY", "Malti2/Aperture")
PAGES = "https://malti2.github.io/Aperture"
BUNDLE_ID = "de.malte.aperture"
ASSET = "Aperture.ipa"
MIN_OS = "26.0"
TINT = "#30D158"
# Must match NSCameraUsageDescription in the app. AltStore compares it with the IPA.
CAMERA_TEXT = "Aperture keeps the camera running without recording so the Camera Control button works as a game controller. Nothing is saved or sent."


def api(path):
    req = urllib.request.Request(
        "https://api.github.com/" + path,
        headers={"Accept": "application/vnd.github+json", "User-Agent": "Aperture-AltStore-Source"},
    )
    token = os.environ.get("GITHUB_TOKEN")
    if token:
        req.add_header("Authorization", "Bearer " + token)
    with urllib.request.urlopen(req) as r:
        return json.load(r)


def versions():
    out = []
    for rel in api("repos/%s/releases?per_page=100" % REPO):
        if rel.get("draft") or rel.get("prerelease"):
            continue
        asset = next((a for a in rel["assets"] if a["name"] == ASSET), None)
        if not asset:
            continue
        notes = (rel.get("body") or "").strip()
        out.append({
            "version": rel["tag_name"].lstrip("v"),
            "date": rel["published_at"][:10],
            "localizedDescription": notes,
            "downloadURL": asset["browser_download_url"],
            "size": asset["size"],
            "minOSVersion": MIN_OS,
        })
    return out


def icon_png(size=256):
    """Dark square, light ring and a green dot, drawn without any image library."""
    c = size / 2
    rows = bytearray()
    for y in range(size):
        rows.append(0)
        for x in range(size):
            d = math.hypot(x + 0.5 - c, y + 0.5 - c)
            if abs(d - size * 0.37) < size * 0.03:
                px = (235, 235, 240)
            elif d < size * 0.07:
                px = (48, 209, 88)
            else:
                px = (10, 10, 14)
            rows += bytes(px)

    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(bytes(rows), 9))
            + chunk(b"IEND", b""))


def main():
    os.makedirs("docs", exist_ok=True)
    source = {
        "name": "Aperture",
        "subtitle": "Arcade game steered with Camera Control",
        "description": "AltStore source for Aperture, an arcade game for iPhone steered with Camera Control.",
        "iconURL": PAGES + "/icon.png",
        "website": "https://github.com/" + REPO,
        "tintColor": TINT,
        "featuredApps": [BUNDLE_ID],
        "apps": [{
            "name": "Aperture",
            "bundleIdentifier": BUNDLE_ID,
            "developerName": "Malte",
            "subtitle": "Steer with Camera Control.",
            "localizedDescription": "An arcade game for iPhone that you steer with the Camera Control button. Needs an iPhone with Camera Control. The camera runs only so the button works. Nothing is recorded, stored or sent.",
            "iconURL": PAGES + "/icon.png",
            "tintColor": TINT,
            "category": "games",
            "versions": versions(),
            "appPermissions": {
                "entitlements": [],
                "privacy": {"NSCameraUsageDescription": CAMERA_TEXT},
            },
        }],
        "news": [],
    }
    with open("docs/source.json", "w") as f:
        json.dump(source, f, indent=2, ensure_ascii=False)
        f.write("\n")
    with open("docs/icon.png", "wb") as f:
        f.write(icon_png())


if __name__ == "__main__":
    main()
