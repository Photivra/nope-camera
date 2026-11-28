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
# The build reads every date in UTC, so the tests do too.
TODAY = datetime.datetime.now(datetime.timezone.utc).date().isoformat()
# The test tree's first commit is dated before every "Last updated" in the repository, so the
# staleness rules pass on the unchanged files whatever day the tests run.
TREE_DATE = "2026-01-01T12:00:00+0000"
failures = []
passed = 0


def run(cmd, cwd, env=None):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, env=env)


def git(tree, *args, date=None):
    env = {**os.environ, "GIT_AUTHOR_NAME": "test", "GIT_AUTHOR_EMAIL": "test@example.invalid",
           "GIT_COMMITTER_NAME": "test", "GIT_COMMITTER_EMAIL": "test@example.invalid"}
    if date:
        env.update(GIT_AUTHOR_DATE=date, GIT_COMMITTER_DATE=date)
    result = run(["git", *args], tree, env=env)
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
    # Cases edit page text without committing, which the build dates today (UTC): the pages'
    # "Last updated" dates are today too, so only the rule a case tests can stop its build.
    for page in ("site/content/support.json", "site/content/accessibility.json"):
        set_last_updated(tree, page, TODAY)
    # The cases start from the site before the app is on the App Store (no id, no badge), whatever
    # the repository's site.json says; "available" below checks the published state.
    config = tree / "site/site.json"
    config.write_text(re.sub(r'"appStoreId": [^,]+,\n  "available": (true|false),', '"appStoreId": null,\n  "available": false,',
                             config.read_text(), count=1))
    (tree / "site/assets/app-store-badge.svg").unlink(missing_ok=True)
    policy = tree / "docs/store/privacy-policy-draft.md"
    policy.write_text(re.sub(r"(?m)^(Effective date: .+?\. )Last updated: [0-9-]+\.", rf"\g<1>Last updated: {TODAY}.",
                             policy.read_text(), count=1))
    git(tree, "init", "-q")
    git(tree, "add", "-A")
    git(tree, "commit", "-q", "-m", "test tree", date=TREE_DATE)
    return tree


def edit(tree, path, old, new, count=1):
    file = tree / path
    text = file.read_text(encoding="utf-8")
    if old not in text:
        sys.exit(f"test setup: {old!r} not in {path}")
    file.write_text(text.replace(old, new, count), encoding="utf-8")


def set_last_updated(tree, path, day):
    """Sets a content file's lastUpdated by pattern, whatever date it holds now."""
    file = tree / path
    text, count = re.subn(r'"lastUpdated": "[^"]*"', f'"lastUpdated": "{day}"', file.read_text(encoding="utf-8"), count=1)
    if count != 1:
        sys.exit(f"test setup: no lastUpdated in {path}")
    file.write_text(text, encoding="utf-8")


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
    tree_policy_markers(tree)
    result = build(tree, out, preview=False)
    expect("policy markers", result, False, "isn't ready to publish")
    expect("policy markers listed", result, False, "line ")

    # A finished policy builds; a later change without a new date doesn't.
    tree, out = fresh("finished")
    tree_policy_done(tree)
    git(tree, "commit", "-q", "--allow-empty", "-am", "finish the policy")
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
        ("no claims", "site/content/support.json", "\"h1\": {\"md\": \"Support\", \"claims\": [\"none\"]}", "\"h1\": {\"md\": \"Support\"}", "no \"claims\""),
        ("empty claims", "site/content/support.json", "\"h1\": {\"md\": \"Support\", \"claims\": [\"none\"]}", "\"h1\": {\"md\": \"Support\", \"claims\": []}", "or an empty one"),
        ("none with claims", "site/content/support.json", "\"h1\": {\"md\": \"Support\", \"claims\": [\"none\"]}", "\"h1\": {\"md\": \"Support\", \"claims\": [\"none\", \"C1\"]}", "names \"none\" with"),
        ("unknown claim", "site/content/support.json", "\"h1\": {\"md\": \"Support\", \"claims\": [\"none\"]}", "\"h1\": {\"md\": \"Support\", \"claims\": [\"C99\"]}", "unknown claims"),
        ("new listing group", "store/metadata/en-US/description.txt", "FOR EVERYONE", "FOR ALL", "no sentence-case name"),
        ("README devices", "README.md", "iPhone 11 and later", "iPhone 12 and later", "relies on README.md"),
        ("app string", "site/content/accessibility.json", "take a photo.\", \"claims\": [\"C11\"]", "take a picture.\", \"claims\": [\"C11\"]", "isn't a string of"),
        ("app heading", "site/content/accessibility.json", "\"appHeading\": \"Feedback\"", "\"appHeading\": \"Responses\"", "isn't a string of"),
        ("evidence", "docs/store/accessibility-label.md", "| Captions | Not applicable |", "| Captions | Yes |", "no longer says"),
        ("declared without pass", "store/accessibility-status.json", "\"declared\": []", "\"declared\": [\"VoiceOver\"]", "without a manual pass"),
        ("listing accessibility without a pass", "store/metadata/en-US/description.txt", "• The volume buttons work as a shutter.",
         "• Designed to work with VoiceOver, Voice Control and the largest text sizes. The volume buttons work as a shutter.",
         "records no manual pass on an iPhone"),
        ("listing largest text without a pass", "store/metadata/en-US/description.txt", "• The volume buttons work as a shutter.",
         "• Works with the largest text. The volume buttons work as a shutter.", "names largest text,"),
        ("listing screen readers without a pass", "store/metadata/en-US/description.txt", "• The volume buttons work as a shutter.",
         "• Works with screen readers. The volume buttons work as a shutter.", "names screen readers,"),
        ("listing accessible without a pass", "store/metadata/en-US/description.txt", "• The volume buttons work as a shutter.",
         "• Fully accessible. The volume buttons work as a shutter.", "names accessible,"),
        ("listing Large Text and AssistiveTouch without a pass", "store/metadata/en-US/description.txt", "• The volume buttons work as a shutter.",
         "• Supports Large Text and AssistiveTouch. The volume buttons work as a shutter.", "names AssistiveTouch, Large Text,"),
        ("listing Reduce Motion without a pass", "store/metadata/en-US/description.txt", "• The volume buttons work as a shutter.",
         "• Respects Reduce Motion. The volume buttons work as a shutter.", "names Reduce Motion,"),
        ("manual pass without a device", "store/accessibility-status.json", "\"manualPass\": null", "\"manualPass\": {\"date\": \"2026-11-19\"}", "needs {\"date\""),
        ("manual pass date", "store/accessibility-status.json", "\"manualPass\": null", "\"manualPass\": {\"date\": \"19 November\", \"device\": \"iPhone 16 Pro Max\"}", "YYYY-MM-DD"),
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

    tree, out = fresh("available")
    edit(tree, "site/site.json", "\"appStoreId\": null,\n  \"available\": false", "\"appStoreId\": \"6838151647\",\n  \"available\": true")
    shutil.copy(ROOT / "site/assets/app-store-badge.svg", tree / "site/assets/app-store-badge.svg")
    expect("on the App Store: the badge and the link build", build(tree, out), True)
    home = (out / "index.html").read_text() if (out / "index.html").exists() else ""
    if "https://apps.apple.com/us/app/id6838151647" not in home or "Not on the App Store yet" in home:
        failures.append("on the App Store: the home page doesn't link the App Store, or still says it isn't on it")
    if 'app-store-badge' not in home or 'width="120" height="40"' not in home:
        failures.append("on the App Store: the home page has no App Store badge drawn at 120 by 40")

    tree, out = fresh("support-stale")
    set_last_updated(tree, "site/content/support.json", "2026-01-01")
    git(tree, "commit", "-q", "-am", "an old date", date=TREE_DATE)
    edit(tree, "site/content/support.json", "\"md\": \"Support\"", "\"md\": \"Support \"")
    expect("support last updated, in preview too", build(tree, out), False, "site/content/support.json: \"Last updated\"")
    tree_policy_done(tree)
    expect("support last updated", build(tree, out, preview=False), False, "site/content/support.json: \"Last updated\"")

    # "Last updated" dates: UTC days, one day of tolerance, a real date, never after today.
    def dated_change(name, written, committed):
        tree, out = fresh(name)
        set_last_updated(tree, "site/content/support.json", written)
        edit(tree, "site/content/support.json", "\"md\": \"Support\"", "\"md\": \"Support \"")
        git(tree, "commit", "-q", "-am", "a dated change", date=committed)
        return build(tree, out)

    # 20:00 on 2026-10-20 at UTC-5 is 01:00 on 2026-10-21 in UTC: a local reading would accept
    # 2026-10-19 (one day before the 20th); the UTC reading doesn't (two days before the 21st).
    expect("last updated: the UTC day", dated_change("utc-day", "2026-10-21", "2026-10-20T20:00:00-0500"), True)
    expect("last updated: one day earlier is accepted", dated_change("one-day", "2026-10-20", "2026-10-20T20:00:00-0500"), True)
    expect("last updated: two days earlier in UTC", dated_change("two-days", "2026-10-19", "2026-10-20T20:00:00-0500"), False,
           "Write \"Last updated\" 2026-10-21")
    tree, out = fresh("future-date")
    set_last_updated(tree, "site/content/support.json", "2099-01-01")
    expect("last updated: a future date", build(tree, out), False, "after today")
    tree, out = fresh("bad-date")
    set_last_updated(tree, "site/content/accessibility.json", "2026-11-31")
    expect("last updated: not a real date", build(tree, out), False, "real date")
    tree, out = fresh("compact-date")
    set_last_updated(tree, "site/content/accessibility.json", "20261119")
    expect("last updated: not YYYY-MM-DD", build(tree, out), False, "YYYY-MM-DD")

    # The policy: lowercase "draft" is a marker; a finished policy's rules run in preview too.
    tree, out = fresh("draft-lowercase")
    tree_policy_done(tree)
    edit(tree, "docs/store/privacy-policy-draft.md", "## Children\n", "## Children\n\nThis is a draft.\n")
    expect("policy: draft in lowercase", build(tree, out, preview=False), False, "line ")
    tree, out = fresh("effective-date")
    tree_policy_done(tree)
    edit(tree, "docs/store/privacy-policy-draft.md", f"Effective date: {TODAY}.", "Effective date: TBD soon.")
    expect("policy: effective date", build(tree, out, preview=False), False, "\"Effective date\" must be a date")
    tree, out = fresh("policy-future")
    tree_policy_done(tree)
    edit(tree, "docs/store/privacy-policy-draft.md", f"Last updated: {TODAY}.", "Last updated: 2099-01-01.")
    expect("policy: future last updated", build(tree, out, preview=False), False, "after today")
    tree, out = fresh("policy-version-preview")
    tree_policy_done(tree)
    edit(tree, "Config/Base.xcconfig", "MARKETING_VERSION = 1.0.0", "MARKETING_VERSION = 1.0.1")
    edit(tree, "CHANGELOG.md", "## [Unreleased]\n", "## [Unreleased]\n\n## [1.0.1] - 2026-11-19\n")
    expect("policy: app version, in preview once finished", build(tree, out), False, "isn't the app's (1.0.1)")
    tree, out = fresh("policy-markers-preview")
    tree_policy_markers(tree)
    edit(tree, "Config/Base.xcconfig", "MARKETING_VERSION = 1.0.0", "MARKETING_VERSION = 1.0.1")
    edit(tree, "CHANGELOG.md", "## [Unreleased]\n", "## [Unreleased]\n\n## [1.0.1] - 2026-11-19\n")
    expect("policy: version and dates skipped in preview while markers remain", build(tree, out), True)

    tree, out = fresh("ipad-pass-only")
    status_file = tree / "store/accessibility-status.json"
    status = json.loads(status_file.read_text())
    status["devices"]["iPad"]["manualPass"] = {"date": "2026-11-19", "device": "iPad Air (5th generation)"}
    status_file.write_text(json.dumps(status, indent=2))
    edit(tree, "store/metadata/en-US/description.txt", "• The volume buttons work as a shutter.",
         "• Works with VoiceOver. The volume buttons work as a shutter.")
    expect("listing accessibility, iPad pass only", build(tree, out), False, "records no manual pass on an iPhone")

    tree, out = fresh("passes")
    tree_policy_done(tree)
    edit(tree, "store/accessibility-status.json", "\"manualPass\": null,\n      \"declared\": []",
         "\"manualPass\": {\"date\": \"2026-11-19\", \"device\": \"iPhone 16 Pro Max\"},\n      \"declared\": [\"VoiceOver\", \"Larger Text\"]")
    edit(tree, "store/metadata/en-US/description.txt", "• The volume buttons work as a shutter.",
         "• Designed to work with VoiceOver, Voice Control and the largest text sizes. The volume buttons work as a shutter.")
    expect("a recorded pass builds, with the listing's accessibility sentence", build(tree, out, preview=False), True)
    page = (out / "accessibility/index.html").read_text()
    if "Declared on the App Store for iPhone: VoiceOver, Larger Text." not in page or "Done on an iPhone 16 Pro Max, 2026-11-19" not in page:
        failures.append("a recorded pass: the page doesn't show the declared features and the pass")


def tree_policy_done(tree):
    """Dates the finished policy today, so a publishing build reaches the later rules."""
    policy = tree / "docs/store/privacy-policy-draft.md"
    text, count = re.subn(r"^Effective date: .+?\. Last updated: .+?\. App version: .+?\.$",
                          f"Effective date: {TODAY}. Last updated: {TODAY}. App version: 1.0.0.",
                          policy.read_text(), count=1, flags=re.M)
    if count != 1:
        sys.exit("test setup: the policy has no dates line")
    policy.write_text(text)


def tree_policy_markers(tree):
    """Puts an unfilled item back, as in a policy that isn't finished."""
    edit(tree, "docs/store/privacy-policy-draft.md", "Shackelford Creative, LLC", "[LLC legal name]")


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
