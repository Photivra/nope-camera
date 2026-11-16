#!/usr/bin/env bash
# Installs the maintainer-approved file validators for scripts/check-file-compat.sh (issue #58)
# at pinned versions, each checked against its SHA-256 before it is unpacked: c2patool and
# exiftool. dng_validate is not approved and is not installed. Neither tool is part of the app;
# they run only in the file-compat CI job and on a developer's Mac
# (security/allowed-dependencies.txt, docs/TESTING.md, "External validators").
#
# Usage: scripts/install-file-validators.sh <directory>
# Prints the directory that holds the two commands, for PATH (CI appends it to $GITHUB_PATH).
#
# Pins (update by a reviewed pull request, with the new checksums):
#   c2patool 0.28.4  universal macOS build from the project's GitHub release; the checksum is
#                    the release asset's published SHA-256 digest.
#   exiftool 13.55   the latest production release (Image-ExifTool-13.55.tar.gz) from the
#                    author's SourceForge downloads, or the same file from CPAN; the checksum
#                    matches Homebrew's exiftool formula for 13.55.
set -euo pipefail

c2patool_version=0.28.4
c2patool_url="https://github.com/contentauth/c2patool/releases/download/v${c2patool_version}/v${c2patool_version}-universal-apple-darwin.zip"
c2patool_sha256=ed669f1a0a123c2180162b7bca5da7844cfc20a233b93bbe84e37d25404fc2e1

exiftool_version=13.55
exiftool_urls=(
  "https://downloads.sourceforge.net/project/exiftool/Image-ExifTool-${exiftool_version}.tar.gz"
  "https://cpan.metacpan.org/authors/id/E/EX/EXIFTOOL/Image-ExifTool-${exiftool_version}.tar.gz"
)
exiftool_sha256=5f4c81d34ad406538c2871ad72dbfceb5d9b412b2f16cbbeb4d712d270846667

dir="${1:?usage: install-file-validators.sh <directory>}"
mkdir -p "$dir/downloads" "$dir/bin"

# download <file> <sha256> <url>...: tries each URL until one gives the expected checksum.
download() {
  local file="$1" sha="$2"
  shift 2
  for url in "$@"; do
    if curl --fail --silent --show-error --location --retry 3 --proto '=https' --output "$file" "$url" \
      && echo "$sha  $file" | shasum -a 256 --check --status; then
      return 0
    fi
    echo "install-file-validators: $url failed or didn't match its checksum" >&2
  done
  rm -f "$file"
  return 1
}

download "$dir/downloads/c2patool.zip" "$c2patool_sha256" "$c2patool_url"
rm -rf "$dir/c2patool"
unzip -q "$dir/downloads/c2patool.zip" -d "$dir/c2patool"
ln -sf "$dir/c2patool/c2patool/c2patool" "$dir/bin/c2patool"

download "$dir/downloads/exiftool.tar.gz" "$exiftool_sha256" "${exiftool_urls[@]}"
rm -rf "$dir/exiftool"
mkdir -p "$dir/exiftool"
tar -xzf "$dir/downloads/exiftool.tar.gz" -C "$dir/exiftool" --strip-components 1
# exiftool is a Perl script that finds its library next to itself (lib/), so it runs in place
# with the system Perl.
ln -sf "$dir/exiftool/exiftool" "$dir/bin/exiftool"

[[ "$("$dir/bin/c2patool" --version)" == "c2patool $c2patool_version" ]] \
  || { echo "install-file-validators: unexpected c2patool version" >&2; exit 1; }
[[ "$("$dir/bin/exiftool" -ver)" == "$exiftool_version" ]] \
  || { echo "install-file-validators: unexpected exiftool version" >&2; exit 1; }
echo "$dir/bin"
