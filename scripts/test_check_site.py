#!/usr/bin/env python3
"""Tests the site's build rules and checks: each rule gets a passing and a failing case.

Run by scripts/test-check-site.sh. Works in a temporary copy of the files the build reads (a
fresh git repository, so the "Last updated" rules can be tested), with site/node_modules linked
in for the Tailwind CLI. Standard library only.
"""
import datetime
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
COPY = [
    "scripts/build-site.py", "scripts/site_checks.py", "site/site.json", "site/content", "site/templates",
    "site/styles", "site/assets", "docs/store/privacy-policy-draft.md", "docs/store/accessibility-label.md",
    "docs/store/README.md", "docs/design/tokens.md", "store/metadata/en-US", "store/accessibility-status.json",
    "Config/Base.xcconfig", "CHANGELOG.md", "README.md", "NOTICE", "Sources/NopeUI/AccessibilitySettingsView.swift",
]
TODAY = datetime.datetime.now(datetime.timezone.utc).date().isoformat()
failures = []
passed = 0


def run(cmd, cwd, env=None):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, env=env)


def git(tree, *args):
    result = run(["git", *args], tree, env={**os.environ, "GIT_AUTHOR_NAME": "test", "GIT_AUTHOR_EMAIL": "test@example.invalid",
                                           "GIT_COMMITTER_NAME": "test", "GIT_COMMITTER_EMAIL": "test@example.invalid"})
    if result.returncode != 0:
        sys.exit(f"git {' '.join(args)} failed: {result.stderr}")


def make_tree(base):
    tree = pathlib.Path(base) / "repo"
    for item in COPY:
        source, target = ROOT / item, tree / item
        target.parent.mkdir(parents=True, exist_ok=True)
        if source.is_dir():
            shutil.copytree(source, target)
        else:
            shutil.copy(source, target)
    (tree / "site/node_modules").symlink_to(ROOT / "site/node_modules")
    git(tree, "init", "-q")
    git(tree, "add", "-A")
    git(tree, "commit", "-q", "-m", "test tree")
    return tree


def edit(tree, path, old, new, count=1):
    file = tree / path
    text = file.read_text(encoding="utf-8")
    if old not in text:
        sys.exit(f"test setup: {old!r} not in {path}")
    file.write_text(text.replace(old, new, count), encoding="utf-8")


def expect(name, result, ok, needle=None):
    global passed
    output = result.stdout + result.stderr
    if ok and result.returncode != 0:
        failures.append(f"{name}: expected to pass, failed:\n{output}")
    elif not ok and result.returncode == 0:
        failures.append(f"{name}: expected to fail, passed")
    elif not ok and needle and needle not in output:
        failures.append(f"{name}: failed without {needle!r}:\n{output}")
    else:
        passed += 1


def build(tree, out, preview=True):
    return run([sys.executable, "scripts/build-site.py", "--out", str(out)] + (["--preview"] if preview else []), tree)


def check(tree, out, preview=True):
    return run([sys.executable, "scripts/site_checks.py"] + (["--preview"] if preview else []) + [str(out)], tree)


# Mutations of a good build: (name, file in the build, old, new, text expected in the failure).
PAGE_CASES = [
    ("script", "support/index.html", "</main>", "<script>1</script></main>", "isn't the JSON-LD"),
    ("event handler", "support/index.html", "<main id=\"main\">", "<main id=\"main\" onclick=\"x\">", "event handler"),
    ("style attribute", "support/index.html", "<main id=\"main\">", "<main id=\"main\" style=\"color:red\">", "style attribute"),
    ("style element", "support/index.html", "</head>", "<style>p{}</style></head>", "<style> is not allowed"),
    ("iframe", "support/index.html", "</main>", "<iframe></iframe></main>", "<iframe> is not allowed"),
    ("form", "support/index.html", "</main>", "<form></form></main>", "<form> is not allowed"),
    ("outside image", "support/index.html", "</main>", "<img src=\"https://example.com/a.png\" alt=\"\"></main>", "loads from another site"),
    ("outside stylesheet", "support/index.html", "</head>", "<link rel=\"stylesheet\" href=\"https://example.com/a.css\"></head>", "loads from another site"),
    ("link not allowed", "support/index.html", "</main>", "<a href=\"https://example.com/\">x</a></main>", "not on the allowed list"),
    ("mailto body", "support/index.html", "mailto:hello@photivra.com\"", "mailto:hello@photivra.com?subject=x\"", "prefilled"),
    ("CSP changed", "support/index.html", "form-action 'none'", "form-action 'self'", "differs from the design"),
    ("CSP moved", "support/index.html", "<meta http-equiv=\"Content-Security-Policy\"", "<meta name=\"x\" content=\"y\">\n<meta http-equiv=\"Content-Security-Policy\"", "must follow the character set"),
    ("referrer", "support/index.html", "<meta name=\"referrer\" content=\"no-referrer\">", "", "referrer"),
    ("doctype", "support/index.html", "<!doctype html>", "<!DOCTYPE html PUBLIC \"x\">", "<!doctype html>"),
    ("broken link", "support/index.html", "</main>", "<a href=\"/nowhere/\">x</a></main>", "broken link"),
    ("broken anchor", "support/index.html", "</main>", "<a href=\"/privacy/#nowhere\">x</a></main>", "broken anchor"),
    ("http link", "support/index.html", "</main>", "<a href=\"http://photivra.com/\">x</a></main>", "http: address"),
    ("two h1", "support/index.html", "</main>", "<h1>x</h1></main>", "h1 elements"),
    ("same title", "support/index.html", "<title>Support · Photivra Nope Camera</title>", "<title>Privacy policy · Photivra Nope Camera</title>", "the same title"),
    ("no description", "support/index.html", "<meta name=\"description\"", "<meta name=\"x-description\"", "no meta description"),
    ("canonical", "support/index.html", "href=\"https://nope.photivra.com/support/\"", "href=\"https://nope.photivra.com/support\"", "canonical address"),
    ("lang", "support/index.html", "lang=\"en-US\"", "lang=\"en\"", "lang must be"),
    ("sitemap link", "support/index.html", "<link rel=\"sitemap\"", "<link rel=\"x-sitemap\"", "no sitemap link"),
    ("og", "support/index.html", "property=\"og:image\"", "property=\"og:picture\"", "no og:image"),
    ("sitemap pages", "sitemap.xml", "</urlset>", "<url><loc>https://nope.photivra.com/404.html</loc></url></urlset>", "sitemap.xml must list"),
    ("robots sitemap", "robots.txt", "Sitemap:", "Site-map:", "robots.txt"),
    ("404 noindex", "404.html", "<meta name=\"robots\" content=\"noindex\">", "", "no noindex"),
    ("JSON-LD", "index.html", "\"@context\"", "@context\"", "doesn't parse"),
    ("rating", "index.html", "\"isAccessibleForFree\"", "\"aggregateRating\":1,\"isAccessibleForFree\"", "aggregateRating"),
    ("offer", "index.html", "\"isAccessibleForFree\"", "\"offers\":{},\"isAccessibleForFree\"", "an offer while"),
    ("badge", "index.html", "</main>", "<img src=\"/assets/app-store-badge.1.svg\" alt=\"x\"></main>", "badge is shown"),
    ("store link", "index.html", "</main>", "<a href=\"https://apps.apple.com/us/app/id1\">x</a></main>", "App Store link"),
    ("character", "support/index.html", "</main>", "<p>→</p></main>", "outside the font subset"),
    ("private host", "support/index.html", "</main>", "<p>example-" "stag" "ing.example.com</p></main>", "private test deployment"),
    ("security.txt", ".well-known/security.txt", "Expires: ", "Expires: 2001-01-01T00:00:00Z\nX: ", "Expires"),
    ("big page", "support/index.html", "</main>", "<p>" + os.urandom(9000).hex() + "</p></main>", "HTML"),
]


def page_cases(tree, good):
    for name, file, old, new, needle in PAGE_CASES:
        with tempfile.TemporaryDirectory() as tmp:
            out = pathlib.Path(tmp) / "site"
            shutil.copytree(good, out)
            target = out / file
            text = target.read_text(encoding="utf-8")
            if old not in text:
                failures.append(f"{name}: test setup, {old!r} not in {file}")
                continue
            target.write_text(text.replace(old, new, 1), encoding="utf-8")
            expect(name, check(tree, out), False, needle)
    with tempfile.TemporaryDirectory() as tmp:
        out = pathlib.Path(tmp) / "site"
        shutil.copytree(good, out)
        css = next(out.rglob("*.css"))
        css.write_text(css.read_text() + "/*" + os.urandom(8000).hex() + "*/")
        (out / "assets" / "app.js").write_text("1")
        (out / "assets" / "fonts" / "extra.woff2").write_bytes(os.urandom(30000))
        result = check(tree, out)
        for needle in ("over 10240", "JavaScript file", "fonts: 3 files"):
            expect(f"size: {needle}", result, False, needle)
        (out / "assets" / "x.css").write_text("@import url(https://example.com/a.css);")
        expect("css import", check(tree, out), False, "@import")
    expect("preview build without --preview", check(tree, good, preview=False), False, "--preview build")


def build_cases(base):
    def fresh(name):
        tree = make_tree(pathlib.Path(base) / name)
        return tree, pathlib.Path(base) / name / "out"

    # The policy: markers stop a publishing build, and are listed.
    tree, out = fresh("markers")
    result = build(tree, out, preview=False)
    expect("policy markers", result, False, "isn't ready to publish")
    expect("policy markers listed", result, False, "line ")

    # A finished policy builds; a later change without a new date doesn't.
    tree, out = fresh("finished")
    policy = tree / "docs/store/privacy-policy-draft.md"
    text = policy.read_text()
    text = re.sub(r"^.*?\n---\n", "", text, count=1, flags=re.S)
    text = text.replace("Effective date: [date]. Last updated: [date]. App version: [1.0.0].",
                        f"Effective date: {TODAY}. Last updated: {TODAY}. App version: 1.0.0.")
    text = text.replace("[LLC legal name]", "Example LLC")
    policy.write_text(text)
    git(tree, "commit", "-q", "-am", "finish the policy")
    expect("finished policy builds", build(tree, out, preview=False), True)
    expect("finished policy passes the checks", check(tree, out, preview=False), True)
    edit(tree, "docs/store/privacy-policy-draft.md", f"Last updated: {TODAY}", "Last updated: 2026-01-01")
    expect("stale last updated", build(tree, out, preview=False), False, "Last updated")
    edit(tree, "docs/store/privacy-policy-draft.md", "Last updated: 2026-01-01", f"Last updated: {TODAY}")
    edit(tree, "docs/store/privacy-policy-draft.md", "App version: 1.0.0.", "App version: 9.9.9.")
    expect("policy version", build(tree, out, preview=False), False, "isn't the app's")

    # Source rules, each in a fresh tree, built in preview.
    cases = [
        ("unknown Markdown", "docs/store/privacy-policy-draft.md", "## Children\n", "## Children\n\n| a | b |\n", "doesn't know"),
        ("single asterisk", "docs/store/privacy-policy-draft.md", "## Children\n", "## Children\n\nSome *word*.\n", "doesn't know"),
        ("no claims", "site/content/support.json", "\"h1\": {\"md\": \"Support\", \"claims\": []}", "\"h1\": {\"md\": \"Support\"}", "no \"claims\""),
        ("unknown claim", "site/content/support.json", "\"h1\": {\"md\": \"Support\", \"claims\": []}", "\"h1\": {\"md\": \"Support\", \"claims\": [\"C99\"]}", "unknown claims"),
        ("new listing group", "store/metadata/en-US/description.txt", "FOR EVERYONE", "FOR ALL", "no sentence-case name"),
        ("README devices", "README.md", "iPhone 11 and later", "iPhone 12 and later", "relies on README.md"),
        ("app string", "site/content/accessibility.json", "take a photo.\", \"claims\": [\"C11\"]", "take a picture.\", \"claims\": [\"C11\"]", "isn't a string of"),
        ("app heading", "site/content/accessibility.json", "\"appHeading\": \"Feedback\"", "\"appHeading\": \"Responses\"", "isn't a string of"),
        ("evidence", "docs/store/accessibility-label.md", "| Captions | Not applicable |", "| Captions | Yes |", "no longer says"),
        ("declared without pass", "store/accessibility-status.json", "\"declared\": []", "\"declared\": [\"VoiceOver\"]", "without a manual pass"),
        ("unknown feature", "store/accessibility-status.json", "\"manualPass\": null,\n      \"declared\": []",
         "\"manualPass\": {\"date\": \"2026-11-19\", \"device\": \"iPhone 16 Pro Max\"},\n      \"declared\": [\"Talking\"]", "unknown features"),
        ("badge file", "site/site.json", "\"appStoreId\": null,\n  \"available\": false", "\"appStoreId\": 123,\n  \"available\": true", "badge file"),
        ("available without id", "site/site.json", "\"available\": false", "\"available\": true", "appStoreId is missing"),
        ("token", "site/styles/site.css", "--color-period: #40C8E0;", "--color-period: #6AC5DD;", "token period"),
        ("radius", "site/styles/site.css", "--radius-large: 24px;", "--radius-large: 20px;", "token radius large"),
        ("wordmark color", "site/assets/wordmark.svg", "#40C8E0", "#6AC5DD", "wordmark.svg"),
    ]
    for name, path, old, new, needle in cases:
        tree, out = fresh(slug(name))
        edit(tree, path, old, new)
        result = build(tree, out)
        if result.returncode == 0:
            result = check(tree, out)
        expect(name, result, False, needle)

    tree, out = fresh("support-stale")
    edit(tree, "site/content/support.json", "\"lastUpdated\": \"2026-11-19\"", "\"lastUpdated\": \"2026-01-01\"")
    git(tree, "commit", "-q", "-am", "an old date")
    edit(tree, "site/content/support.json", "\"md\": \"Support\"", "\"md\": \"Support \"")
    tree_policy_done(tree)
    expect("support last updated", build(tree, out, preview=False), False, "site/content/support.json: \"Last updated\"")

    tree, out = fresh("passes")
    edit(tree, "store/accessibility-status.json", "\"manualPass\": null,\n      \"declared\": []",
         "\"manualPass\": {\"date\": \"2026-11-19\", \"device\": \"iPhone 16 Pro Max\"},\n      \"declared\": [\"VoiceOver\", \"Larger Text\"]")
    expect("a recorded pass builds", build(tree, out), True)
    page = (out / "accessibility/index.html").read_text()
    if "Declared on the App Store for iPhone: VoiceOver, Larger Text." not in page or "Done on an iPhone 16 Pro Max, 2026-11-19" not in page:
        failures.append("a recorded pass: the page doesn't show the declared features and the pass")


def tree_policy_done(tree):
    """Fills the policy so a publishing build reaches the later rules."""
    policy = tree / "docs/store/privacy-policy-draft.md"
    text = re.sub(r"^.*?\n---\n", "", policy.read_text(), count=1, flags=re.S)
    text = text.replace("Effective date: [date]. Last updated: [date]. App version: [1.0.0].",
                        f"Effective date: {TODAY}. Last updated: {TODAY}. App version: 1.0.0.").replace("[LLC legal name]", "Example LLC")
    policy.write_text(text)


def slug(text):
    return re.sub(r"[^a-z0-9]+", "-", text.lower())


def main():
    if not (ROOT / "site/node_modules/.bin/tailwindcss").exists():
        sys.exit("site/node_modules is missing: run npm ci --ignore-scripts in site/")
    with tempfile.TemporaryDirectory() as base:
        tree = make_tree(pathlib.Path(base) / "good")
        good = pathlib.Path(base) / "good" / "out"
        expect("a preview build", build(tree, good), True)
        expect("the checks pass on a good build", check(tree, good), True)
        page_cases(tree, good)
        build_cases(base)
    for failure in failures:
        print(f"FAIL {failure}", file=sys.stderr)
    print(f"site check tests: {passed} passed, {len(failures)} failed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
