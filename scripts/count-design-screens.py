#!/usr/bin/env python3
"""Counts the design screens from the generated set in docs/design/screens (issue #113).

Usage: count-design-screens.py [--root DIR] [--leave-out PREFIX]... [--only PREFIX]...

The screen counts in docs/design/README.md are taken from this output, not by adding up the
figure counts written in each design page: a screen shown on two pages would be counted twice,
and a hand-written figure count goes stale when a screen is added or removed.

- A screen is one PNG file in docs/design/screens/. Its HTML mockup isn't counted again, and a
  PNG without a mockup (a picture of the site) still counts.
- The device is read from the parts of the file name between hyphens: a part "watch" is Apple
  Watch, "duo" the iPhone Duo, "ipad" iPad, and every other screen is iPhone. A part must match
  whole, so "ipadding" is not iPad.
- --leave-out PREFIX drops the screens whose names start with PREFIX, for the sets the README
  keeps out of its counts (for example --leave-out store- for the App Store mockups).
- --only PREFIX counts only the screens whose names start with PREFIX (for example
  --only bracket- for the bracketing screens). With several, a screen matching any counts.

Prints the total, the count for each device, and the PNG files' total size in megabytes
(10^6 bytes, one decimal). Standard library only.
"""
import argparse
import os
import pathlib
import sys

DEVICES = ["iPhone", "iPad", "iPhone Duo", "Apple Watch"]

# The name part that marks each device other than iPhone, checked in this order.
DEVICE_PARTS = [("watch", "Apple Watch"), ("duo", "iPhone Duo"), ("ipad", "iPad")]


def device(stem):
    """Returns the device a screen is drawn for, from its file name without the extension."""
    parts = stem.lower().split("-")
    for part, name in DEVICE_PARTS:
        if part in parts:
            return name
    return "iPhone"


def main():
    parser = argparse.ArgumentParser(description="Counts the design screens in docs/design/screens.")
    parser.add_argument("--root", default=pathlib.Path(__file__).resolve().parent.parent, type=pathlib.Path,
                        help="the repository root (default: this script's repository)")
    parser.add_argument("--leave-out", action="append", default=[], metavar="PREFIX",
                        help="leave out the screens whose names start with PREFIX")
    parser.add_argument("--only", action="append", default=[], metavar="PREFIX",
                        help="count only the screens whose names start with PREFIX")
    args = parser.parse_args()

    screens_dir = args.root / "docs" / "design" / "screens"
    if not screens_dir.is_dir():
        sys.exit(f"error: {screens_dir} not found")
    for prefix in args.leave_out + args.only:
        if not prefix:
            sys.exit("error: an empty prefix matches every screen")

    screens = sorted(path for path in screens_dir.glob("*.png") if path.is_file())
    if args.only:
        screens = [path for path in screens if path.name.startswith(tuple(args.only))]
    screens = [path for path in screens if not path.name.startswith(tuple(args.leave_out))]

    counts = dict.fromkeys(DEVICES, 0)
    for path in screens:
        counts[device(path.stem)] += 1
    size = sum(os.path.getsize(path) for path in screens)

    by_device = ", ".join(f"{counts[name]} {name}" for name in DEVICES)
    noun = "screen" if len(screens) == 1 else "screens"
    print(f"{len(screens)} {noun}: {by_device}")
    print(f"PNG files: {size / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
