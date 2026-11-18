#!/usr/bin/env bash
# Tests for scripts/check-launch-screen.sh: each case copies the repository's launch screen
# files into a small tree, breaks one thing, and checks pass or fail.
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
check="$here/scripts/check-launch-screen.sh"
failures=0
catalog=App/NopeApp/Assets.xcassets

# A tree with the repository's launch screen files and the icon's layers.
make_tree() {
  local d
  d=$(mktemp -d)
  mkdir -p "$d/$catalog" "$d/docs/design" "$d/App/NopeApp/AppIcon.icon"
  cp -R "$here/$catalog/." "$d/$catalog/"
  cp "$here/docs/design/launch-mark.svg" "$d/docs/design/"
  cp -R "$here/App/NopeApp/AppIcon.icon/Assets" "$d/App/NopeApp/AppIcon.icon/"
  echo "$d"
}

# A built app with only an Info.plist: the good keys, then the edit's changes.
make_app() { # make_app <tree> <python statements editing the dict `info`>
  local app="$1/nope.app"
  mkdir -p "$app"
  python3 -I - "$app/Info.plist" "$2" <<'PY'
import plistlib, sys
info = {
    "CFBundleIdentifier": "org.example.nope",
    "UILaunchScreen": {"UIColorName": "LaunchBackground", "UIImageName": "LaunchMark", "UIImageRespectsSafeAreaInsets": False},
    "UIStatusBarStyle": "UIStatusBarStyleLightContent",
}
exec(sys.argv[2])
with open(sys.argv[1], "wb") as handle:
    plistlib.dump(info, handle, fmt=plistlib.FMT_BINARY)
PY
  echo "$app"
}

# case_edit "want" "name" "shell statements run in the tree" ["python edit of the built Info.plist"]
case_edit() {
  local want=$1 name=$2 edit=$3 plist=${4:-} d app="" got
  d=$(make_tree)
  (cd "$d" && eval "$edit")
  if [[ -n "$plist" ]]; then app=$(make_app "$d" "$plist"); fi
  if "$check" --root "$d" $app >/dev/null 2>&1; then got=pass; else got=fail; fi
  if [[ $got == "$want" ]]; then echo "ok   $name"; else echo "FAIL $name (expected $want, got $got)"; failures=$((failures + 1)); fi
  rm -rf "$d"
}

color=$catalog/LaunchBackground.colorset/Contents.json
mark=$catalog/LaunchMark.imageset/LaunchMark.svg

case_edit pass "the repository's files" ":"
case_edit fail "a second color" "python3 -I -c 'import json,sys; p=sys.argv[1]; c=json.load(open(p)); c[\"colors\"].append(c[\"colors\"][0]); json.dump(c, open(p, \"w\"))' $color"
case_edit fail "a dark appearance variant" "python3 -I -c 'import json,sys; p=sys.argv[1]; c=json.load(open(p)); c[\"colors\"][0][\"appearances\"]=[{\"appearance\":\"luminosity\",\"value\":\"dark\"}]; json.dump(c, open(p, \"w\"))' $color"
case_edit fail "a color that isn't black" "sed -i.bak 's/\"red\" : \"0.000\"/\"red\" : \"0.100\"/' $color"
case_edit fail "a translucent color" "sed -i.bak 's/\"alpha\" : \"1.000\"/\"alpha\" : \"0.500\"/' $color"
case_edit fail "no color set" "rm -r $catalog/LaunchBackground.colorset"
case_edit fail "a launch image that differs from the design" "printf ' ' >> $mark"
case_edit fail "the design and the image with a path that isn't the icon's" "sed -i.bak 's/M824 576/M825 576/' docs/design/launch-mark.svg && cp docs/design/launch-mark.svg $mark"
case_edit fail "the design and the image with another period color" "sed -i.bak 's/#6AC5DD/#40C8E0/' docs/design/launch-mark.svg && cp docs/design/launch-mark.svg $mark"
case_edit fail "an image set that isn't rendered as the original" "sed -i.bak 's/original/template/' $catalog/LaunchMark.imageset/Contents.json"
case_edit pass "a built app with the keys" ":" "pass"
case_edit fail "a built app without the image" ":" "del info['UILaunchScreen']['UIImageName']"
case_edit fail "a built app with an extra launch key" ":" "info['UILaunchScreen']['UIImageRespectsNavigationBar'] = True"
case_edit fail "a built app whose image respects the safe area" ":" "info['UILaunchScreen']['UIImageRespectsSafeAreaInsets'] = True"
case_edit fail "a built app with the empty generated dictionary" ":" "info['UILaunchScreen'] = {}"
case_edit fail "a built app with dark status bar content" ":" "info['UIStatusBarStyle'] = 'UIStatusBarStyleDefault'"
case_edit fail "a built app with a launch storyboard too" ":" "info['UILaunchStoryboardName'] = 'LaunchScreen'"

if [[ $failures -ne 0 ]]; then echo "$failures case(s) failed"; exit 1; fi
echo "all launch screen check tests passed"
