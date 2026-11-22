#!/usr/bin/env bash
# Launch screen checks (docs/design/LAUNCH-SCREEN.md, section 8).
# Usage: scripts/check-launch-screen.sh [--root <dir>] [<built .app>]
#
# Without an app it checks the sources:
#   - App/NopeApp/Assets.xcassets/LaunchBackground.colorset has one color, sRGB black, opaque,
#     with no appearance variant;
#   - LaunchMark.imageset/LaunchMark.svg is byte for byte docs/design/launch-mark.svg, its
#     Contents.json names that one file rendered as the original, and the SVG's three paths are
#     the paths of App/NopeApp/AppIcon.icon/Assets (frame.svg, n.svg, period.svg), in the icon's
#     colors (the period's written as Display P3, as the SVG's comment explains).
# Given a built app it also reads the app's Info.plist: UILaunchScreen holds exactly
# UIColorName = LaunchBackground, UIImageName = LaunchMark and UIImageRespectsSafeAreaInsets =
# false; UIStatusBarStyle is UIStatusBarStyleLightContent; no launch storyboard is named; and
# UIApplicationSceneManifest's UIApplicationSupportsMultipleScenes is false (one window on iPad
# for 1.0.0: the one camera screen serves Siri, Shortcuts and the watch). On
# macOS, where `xcrun assetutil` exists, it also checks that the app's compiled asset catalog
# holds both assets.
# The plist is read with Python's plistlib, which reads binary and XML plists on any runner.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "${1:-}" == "--root" ]]; then
  root="${2:?usage: check-launch-screen.sh [--root <dir>] [<built .app>]}"
  shift 2
fi
app="${1:-}"

assets_info=""
if [[ -n "$app" && -f "$app/Assets.car" ]] && command -v xcrun >/dev/null 2>&1 && xcrun --find assetutil >/dev/null 2>&1; then
  assets_info=$(xcrun assetutil --info "$app/Assets.car")
fi

ASSETS_INFO="$assets_info" python3 -I - "$root" "$app" <<'PY'
import json, os, plistlib, re, sys

root, app = sys.argv[1], sys.argv[2]
failures = []

def fail(message):
    failures.append(message)

def read(path):
    with open(os.path.join(root, path), "rb") as handle:
        return handle.read()

catalog = "App/NopeApp/Assets.xcassets"

# The launch color: one color, black, no appearances.
try:
    colorset = json.loads(read(f"{catalog}/LaunchBackground.colorset/Contents.json"))
    colors = colorset.get("colors", [])
    if len(colors) != 1:
        fail(f"LaunchBackground has {len(colors)} colors; it must have exactly one")
    for entry in colors:
        if "appearances" in entry:
            fail("LaunchBackground has an appearance variant; it must be black in every appearance")
        if entry.get("idiom") != "universal":
            fail("LaunchBackground's color must be universal")
        color = entry.get("color", {})
        if color.get("color-space") != "srgb":
            fail("LaunchBackground must be in the sRGB color space")
        components = color.get("components", {})
        try:
            values = {key: float(components[key]) for key in ("red", "green", "blue", "alpha")}
        except (KeyError, ValueError):
            fail("LaunchBackground's components must be red, green, blue and alpha numbers")
            continue
        if (values["red"], values["green"], values["blue"]) != (0.0, 0.0, 0.0) or values["alpha"] != 1.0:
            fail(f"LaunchBackground must be opaque black, not {values}")
except (OSError, ValueError) as error:
    fail(f"can't read the LaunchBackground color set: {error}")

# The launch image: a copy of the design's mark, whose paths are the icon's.
def paths(svg):
    return re.findall(rb'<path\s+fill="(#[0-9A-Fa-f]{6})"\s+d="([^"]+)"', svg)

try:
    mark = read(f"{catalog}/LaunchMark.imageset/LaunchMark.svg")
    design = read("docs/design/launch-mark.svg")
    if mark != design:
        fail("LaunchMark.svg is not byte for byte docs/design/launch-mark.svg")
    imageset = json.loads(read(f"{catalog}/LaunchMark.imageset/Contents.json"))
    images = imageset.get("images", [])
    if [image.get("filename") for image in images] != ["LaunchMark.svg"] or any("appearances" in image for image in images):
        fail("LaunchMark.imageset must hold LaunchMark.svg only, with no appearance variant")
    if imageset.get("properties", {}).get("template-rendering-intent") != "original":
        fail("LaunchMark must be rendered as the original image")
    found = paths(design)
    icon = []
    for layer in ("frame", "n", "period"):
        icon += paths(read(f"App/NopeApp/AppIcon.icon/Assets/{layer}.svg"))
    if len(found) != 3:
        fail(f"launch-mark.svg has {len(found)} paths; it must have the icon's three")
    elif [d for _, d in found] != [d for _, d in icon]:
        fail("launch-mark.svg's paths are not the paths of AppIcon.icon/Assets (frame, n, period)")
    # The period is the icon's sRGB #40C8E0 written as Display P3 (#6AC5DD), because the asset
    # compiler reads SVG colors as Display P3 (see the comment in launch-mark.svg).
    elif [fill.upper() for fill, _ in found] != [b"#EDEDEE", b"#EDEDEE", b"#6AC5DD"]:
        fail("launch-mark.svg's colors must be the icon's: #EDEDEE for the frame and the n, and #6AC5DD (Display P3 for sRGB #40C8E0) for the period")
except (OSError, ValueError) as error:
    fail(f"can't read the launch mark: {error}")

# The built app's Info.plist.
if app:
    try:
        with open(os.path.join(app, "Info.plist"), "rb") as handle:
            info = plistlib.load(handle)
        expected = {"UIColorName": "LaunchBackground", "UIImageName": "LaunchMark", "UIImageRespectsSafeAreaInsets": False}
        launch = info.get("UILaunchScreen")
        if launch != expected:
            fail(f"the built Info.plist's UILaunchScreen is {launch!r}; it must be exactly {expected!r}")
        if info.get("UIStatusBarStyle") != "UIStatusBarStyleLightContent":
            fail(f"the built Info.plist's UIStatusBarStyle is {info.get('UIStatusBarStyle')!r}; it must be UIStatusBarStyleLightContent")
        if "UILaunchStoryboardName" in info:
            fail("the built Info.plist names a launch storyboard; the UILaunchScreen dictionary is used alone")
        scenes = info.get("UIApplicationSceneManifest")
        if not isinstance(scenes, dict) or scenes.get("UIApplicationSupportsMultipleScenes") is not False:
            fail(f"the built Info.plist's UIApplicationSceneManifest is {scenes!r}; UIApplicationSupportsMultipleScenes must be false")
    except (OSError, plistlib.InvalidFileException) as error:
        fail(f"can't read the built app's Info.plist: {error}")
    assets = os.environ.get("ASSETS_INFO", "")
    if assets:
        names = {entry.get("Name") for entry in json.loads(assets) if isinstance(entry, dict)}
        for name in ("LaunchBackground", "LaunchMark"):
            if name not in names:
                fail(f"the built app's asset catalog has no {name}")

for message in failures:
    print(f"launch screen: {message}")
if failures:
    sys.exit(1)
print("launch screen checks passed" + (" (sources and the built app)" if app else " (sources)"))
PY
