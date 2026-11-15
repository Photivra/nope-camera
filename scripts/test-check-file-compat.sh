#!/usr/bin/env bash
# Tests scripts/check-file-compat.sh with stand-in validators, so its pass and fail cases are
# checked without installing c2patool, exiftool or dng_validate. Run from the repository root.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
check="$here/check-file-compat.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fail=0

expect() {  # expect <pass|fail> <description> <command...>
  local want="$1" what="$2"
  shift 2
  if "$@" >"$work/out" 2>&1; then got=pass; else got=fail; fi
  if [[ "$got" != "$want" ]]; then
    echo "FAIL: $what (expected $want, got $got)"; cat "$work/out"; fail=1
  fi
}

fixtures="$work/fixtures"
mkdir -p "$fixtures" "$work/bin" "$work/empty"
printf 'a.dng\traw\ttrue\tfalse\nb.jpg\tjpeg\tfalse\tfalse\n' >"$fixtures/manifest.tsv"
echo signed >"$fixtures/a.dng"
echo unsigned >"$fixtures/b.jpg"

# Stand-ins: each reads a mode from the environment.
cat >"$work/bin/c2patool" <<'EOF'
#!/usr/bin/env bash
if grep -q signed "$1" && ! grep -q unsigned "$1"; then
  echo "{\"validation_state\": \"${C2PA_STATE:-Valid}\", \"validation_results\": {\"activeManifest\": {\"failure\": [{\"code\": \"signingCredential.untrusted\"}]}}}"
else
  echo "Error: no claim found" >&2; exit 1
fi
EOF
cat >"$work/bin/exiftool" <<'EOF'
#!/usr/bin/env bash
echo "Validate                        : ${EXIF_RESULT:-OK}"
EOF
cat >"$work/bin/dng_validate" <<'EOF'
#!/usr/bin/env bash
[[ -n "${DNG_ERROR:-}" ]] && echo "*** Error: $DNG_ERROR ***"
exit 0
EOF
chmod +x "$work/bin/"*
tools="$work/bin:/usr/bin:/bin"
bare="$work/empty:/usr/bin:/bin"

expect pass "all validators pass" env PATH="$tools" "$check" --require "c2patool exiftool dng_validate" "$fixtures"
expect pass "no validator installed and none required" env PATH="$bare" "$check" "$fixtures"
expect fail "a required validator is missing" env PATH="$bare" "$check" --require "exiftool" "$fixtures"
expect fail "an unknown validator is required" env PATH="$tools" "$check" --require "other" "$fixtures"
expect fail "a signed file isn't valid" env PATH="$tools" C2PA_STATE=Invalid "$check" "$fixtures"
expect fail "exiftool reports an error" env PATH="$tools" EXIF_RESULT="1 Error, 2 Warnings" "$check" "$fixtures"
expect pass "exiftool reports warnings only" env PATH="$tools" EXIF_RESULT="2 Warnings (all minor)" "$check" "$fixtures"
expect fail "dng_validate reports an error" env PATH="$tools" DNG_ERROR="bad tag" "$check" "$fixtures"
expect fail "no manifest" env PATH="$tools" "$check" "$work/empty"
printf 'c.heic\theif\ttrue\tfalse\n' >>"$fixtures/manifest.tsv"
expect fail "a file in the manifest is missing" env PATH="$tools" "$check" "$fixtures"

if [[ $fail -ne 0 ]]; then exit 1; fi
echo "file-compat check tests passed"
