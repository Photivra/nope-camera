#!/usr/bin/env python3
"""Builds the public site, nope.photivra.com, into _site/ (docs/design/nope-site.md, section 14).

Python standard library only. The one outside tool is the pinned Tailwind CLI in site/
(`npm ci --ignore-scripts` in site/ first).

    scripts/build-site.py [--out DIR] [--preview]

The pages say nothing the repository doesn't (section 13):
- the privacy page is the policy file named in site/site.json, converted from Markdown;
- the landing page's statements are store/metadata/en-US/description.txt, word for word;
- the support page's device list is README.md, "Requirements";
- the accessibility page's status is store/accessibility-status.json;
- the app version is MARKETING_VERSION in Config/Base.xcconfig, and the release date is its
  CHANGELOG.md entry.

The build refuses to publish a policy that still has a [bracketed] item or the word "draft" (in
any case). --preview skips that rule, and, while such markers remain, the policy's app version
and date rules, which can't hold before the policy is filled in. Every other rule runs in
--preview too, so a pull request finds what would stop the publishing build: the "Last updated"
dates of the content files and of a finished policy, the policy's app version once it has no
markers, and the listing's accessibility sentence (below).

"Last updated" dates are UTC days. Each must be a real YYYY-MM-DD date, not after today (UTC),
and not more than one day older than the newest change to the text it dates, taken from git in
UTC. The one day covers a pull request merged on the UTC day after its date was written.

The App Store description may name VoiceOver, Voice Control or text sizes only once
store/accessibility-status.json records a manual pass on an iPhone (docs/store/README.md, C11).

--preview marks the output as not for publishing, and scripts/check-site.sh fails on that mark
unless it is run with --preview too. The workflow that publishes never passes it.
"""
import argparse
import datetime
import hashlib
import html
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SITE = ROOT / "site"
PREVIEW_MARK = "PREVIEW-NOT-FOR-PUBLISHING.txt"
CSP = (
    "default-src 'none'; style-src 'self'; img-src 'self'; font-src 'self'; "
    "manifest-src 'self'; base-uri 'none'; form-action 'none'"
)
CLAIM_IDS = {f"C{n}" for n in range(1, 13)}

# The public pages, in sitemap order: (path, output file, content file).
PAGES = [
    ("/", "index.html", "home"),
    ("/privacy/", "privacy/index.html", "privacy"),
    ("/support/", "support/index.html", "support"),
    ("/accessibility/", "accessibility/index.html", "accessibility"),
]

WRAP = "mx-auto max-w-[66rem] px-4 md:px-6"
DOC = "doc mx-auto max-w-[44rem] px-4 md:px-6 pt-8 pb-12 md:pt-12 md:pb-16"
META_DL = (
    "grid grid-cols-1 md:grid-cols-[max-content_1fr] gap-x-5 md:gap-y-1 mb-8 px-5 py-4 "
    "bg-surface rounded-small text-small forced-colors:border print:flex print:flex-wrap "
    "print:gap-x-4 print:p-0 print:mb-6"
)


class BuildError(Exception):
    """A reason the site can't be built; printed without a traceback."""


def fail(message):
    raise BuildError(message)


# ---------------------------------------------------------------------------------------------
# Reading the single sources


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


def load_json(path):
    try:
        return json.loads(read(path))
    except json.JSONDecodeError as error:
        fail(f"{path}: not valid JSON ({error})")


def app_version():
    match = re.search(r"^MARKETING_VERSION = ([0-9]+\.[0-9]+\.[0-9]+)$", read("Config/Base.xcconfig"), re.M)
    if not match:
        fail("Config/Base.xcconfig: no MARKETING_VERSION")
    return match.group(1)


def release_date(version):
    match = re.search(rf"^## \[{re.escape(version)}\] - ([0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})$", read("CHANGELOG.md"), re.M)
    if not match:
        fail(f"CHANGELOG.md: no dated entry for {version} (the sitemap and security.txt need its date)")
    return datetime.date.fromisoformat(match.group(1))


def commit():
    try:
        sha = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True, text=True, check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        fail("git rev-parse HEAD failed: the build names the commit it was built from")
    return sha


def readme_section(title):
    text = read("README.md")
    match = re.search(rf"^## {re.escape(title)}\n(.*?)(?=^## |\Z)", text, re.M | re.S)
    if not match:
        fail(f'README.md: no "## {title}" section')
    return match.group(1)


def description_txt():
    """The App Store description: the first line, the groups, and the last line."""
    text = read("store/metadata/en-US/description.txt").strip()
    blocks = [b.strip() for b in re.split(r"\n\s*\n", text)]
    first, last = blocks[0], blocks[-1]
    groups = []
    for block in blocks[1:-1]:
        lines = block.splitlines()
        heading, items = lines[0].strip(), []
        for line in lines[1:]:
            if not line.startswith("• "):
                fail(f"description.txt: a line in {heading!r} that isn't a bullet: {line!r}")
            items.append(line[2:].strip())
        if not items:
            fail(f"description.txt: the group {heading!r} has no statements")
        groups.append((heading, items))
    return first, groups, last


# ---------------------------------------------------------------------------------------------
# Git dates, for the staleness rule ("Last updated" is never older than the text)


def utc_today():
    return datetime.datetime.now(datetime.timezone.utc).date()


def last_change(path, extract=lambda text: text):
    """The UTC day of the newest change to `extract(file)`, today (UTC) for an uncommitted change.

    Commit dates are read in UTC: GitHub's squash merges commit at the merge time, and the
    committer's own time zone must not move the day."""
    def at(rev):
        result = subprocess.run(["git", "show", f"{rev}:{path}"], cwd=ROOT, capture_output=True, text=True)
        return extract(result.stdout) if result.returncode == 0 else None

    shallow = subprocess.run(["git", "rev-parse", "--is-shallow-repository"], cwd=ROOT, capture_output=True, text=True)
    if shallow.returncode != 0:
        fail("git is needed for the \"Last updated\" check")
    if shallow.stdout.strip() == "true":
        fail("the \"Last updated\" check needs the full git history (fetch-depth: 0)")
    current = extract((ROOT / path).read_text(encoding="utf-8"))
    if at("HEAD") != current:
        return utc_today()
    log = subprocess.run(
        ["git", "log", "--date=short-local", "--format=%H %cd", "--follow", "--", path], cwd=ROOT,
        capture_output=True, text=True, check=True, env={**os.environ, "TZ": "UTC"},
    ).stdout.split("\n")
    for line in filter(None, log):
        sha, day = line.split()
        if at(sha) != at(f"{sha}^"):
            return datetime.date.fromisoformat(day)
    return utc_today()


# A "Last updated" date may be this much older than the newest change: a pull request merged on
# the UTC day after its date was written still passes.
LAST_UPDATED_TOLERANCE = datetime.timedelta(days=1)


def iso_date(label, field, value):
    """A real date written YYYY-MM-DD (fromisoformat alone also takes forms like 20261119)."""
    if not isinstance(value, str) or not re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", value):
        fail(f'{label}: "{field}" must be a date written YYYY-MM-DD, not {value!r}')
    try:
        return datetime.date.fromisoformat(value)
    except ValueError:
        fail(f'{label}: "{field}" must be a real date written YYYY-MM-DD, not {value!r}')


def check_last_updated(label, stated, changes):
    stated_date = iso_date(label, "Last updated", stated)
    today = utc_today()
    if stated_date > today:
        fail(f'{label}: "Last updated" is {stated_date}, after today ({today}, UTC). Write the UTC day of the change')
    newest = max(changes)
    if stated_date < newest - LAST_UPDATED_TOLERANCE:
        fail(f'{label}: "Last updated" is {stated_date}, but its text last changed on {newest} (UTC, from git). '
             f'Write "Last updated" {newest}: the UTC day the change is committed or merged; one day earlier is accepted')
    return stated_date


# ---------------------------------------------------------------------------------------------
# Markdown: the small set the policy and the content files use


INLINE_LINK = re.compile(r"\[([^\]\n]+)\]\(([^)\s]+)\)")


def inline(text, source="text"):
    """Converts links, **bold** and `code`; anything else Markdown-like is refused."""
    out = []
    position = 0
    for match in INLINE_LINK.finditer(text):
        out.append(inline_plain(text[position:match.start()], source))
        label, href = match.groups()
        out.append(f'<a href="{html.escape(href)}">{inline_plain(label, source)}</a>')
        position = match.end()
    out.append(inline_plain(text[position:], source))
    return "".join(out)


def inline_plain(text, source):
    for pattern, what in ((r"(?<![*\w])\*(?!\*)", "a single *"), (r"(?<!\w)_\w", "an underscore emphasis"),
                          (r"!\[", "an image"), (r"<", "raw HTML"), (r"\[[^\]]*\]\(", "a broken link")):
        if re.search(pattern, text):
            fail(f"{source}: Markdown the build doesn't know ({what}) in {text!r}")
    escaped = html.escape(text, quote=False)
    escaped = re.sub(r"`([^`]+)`", r"<code>\1</code>", escaped)
    escaped = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", escaped)
    if "*" in escaped or "`" in escaped:
        fail(f"{source}: unmatched ** or ` in {text!r}")
    return escaped


def slug(text):
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")


def markdown_blocks(text, source):
    """Headings, paragraphs and `- ` lists (with indented continuation lines)."""
    blocks = []
    for chunk in re.split(r"\n\s*\n", text.strip()):
        lines = chunk.splitlines()
        first = lines[0]
        if re.match(r"#{1,3} ", first):
            if len(lines) > 1:
                fail(f"{source}: a heading must be alone in its block: {first!r}")
            level = len(first) - len(first.lstrip("#"))
            blocks.append(("h", level, first[level + 1:].strip()))
        elif first.startswith("- "):
            items = []
            for line in lines:
                if line.startswith("- "):
                    items.append(line[2:].strip())
                elif line.startswith("  ") and items:
                    items[-1] += " " + line.strip()
                else:
                    fail(f"{source}: a list line the build doesn't know: {line!r}")
            blocks.append(("ul", items))
        elif re.match(r"(\d+\.|>|\||```|\* |\+ |---)", first):
            fail(f"{source}: Markdown the build doesn't know: {first!r}")
        else:
            blocks.append(("p", " ".join(line.strip() for line in lines)))
    return blocks


# ---------------------------------------------------------------------------------------------
# The privacy policy


POLICY_DATES = re.compile(r"^Effective date: (.+?)\. Last updated: (.+?)\. App version: (.+?)\.$", re.M)


def policy_body(text):
    """Everything under the draft notice: the part after the first `---` line, if there is one."""
    parts = re.split(r"^---$", text, maxsplit=1, flags=re.M)
    return parts[1] if len(parts) == 2 else text


def policy_markers(text):
    """The items that stop publication: [brackets] that aren't links, and "draft" in any case."""
    markers = []
    for number, line in enumerate(text.splitlines(), 1):
        for match in re.finditer(r"\[[^\]\n]*\](?!\()", line):
            markers.append(f"line {number}: {match.group(0)}")
        for match in re.finditer(r"\bdraft\b", line, re.I):
            markers.append(f"line {number}: {match.group(0)}")
    return markers


def build_policy(path, version, preview):
    text = read(path)
    markers = policy_markers(text)
    if markers and not preview:
        fail(f"{path} isn't ready to publish. Fill or remove these first:\n  " + "\n  ".join(markers))
    body = policy_body(text)
    dates = POLICY_DATES.search(body)
    if not dates:
        fail(f'{path}: no line "Effective date: …. Last updated: …. App version: …."')
    effective, updated, policy_version = (value.strip() for value in dates.groups())
    body = body[:dates.start()] + body[dates.end():]
    # With markers left (only possible in --preview) the version and dates are still placeholders.
    if not markers:
        if policy_version != version:
            fail(f"{path}: the policy's app version ({policy_version}) isn't the app's ({version}). "
                 'Each release changes the policy\'s "App version" and "Last updated" (docs/RELEASING.md)')
        iso_date(path, "Effective date", effective)
        check_last_updated(path, updated, [last_change(path, policy_body)])
    blocks = markdown_blocks(body, path)
    if not blocks or blocks[0][:2] != ("h", 1):
        fail(f"{path}: the policy must start with its # title")
    title = blocks[0][2]
    toc, parts, seen = [], [], set()
    for block in blocks[1:]:
        if block[0] == "h":
            level, heading = block[1], block[2]
            if level == 1:
                fail(f"{path}: a second # heading: {heading!r}")
            anchor = slug(heading)
            if anchor in seen:
                fail(f"{path}: two headings with the anchor #{anchor}")
            seen.add(anchor)
            if level == 2:
                toc.append(f'<li class="break-inside-avoid"><a class="inline-block py-1.5" href="#{anchor}">{inline(heading, path)}</a></li>')
            parts.append(f'<h{level} id="{anchor}">{inline(heading, path)}</h{level}>')
        elif block[0] == "ul":
            parts.append("<ul>" + "".join(f"<li>{inline(item, path)}</li>" for item in block[1]) + "</ul>")
        else:
            parts.append(f"<p>{inline(block[1], path)}</p>")
    return {
        "title": title,
        "effective": effective,
        "updated": updated,
        "version": policy_version,
        "toc": "".join(toc),
        "body": "\n".join(parts),
    }


# ---------------------------------------------------------------------------------------------
# Content files


def content(name):
    data = load_json(f"site/content/{name}.json")
    check_claims(data, f"site/content/{name}.json")
    return data


def check_claims(node, source, where="$"):
    """Every text ({"md": ...}) names the claims it relies on (docs/store/README.md, C1 to C12),
    or ["none"] for a text that relies on no listing claim: it states no fact about the app, or its
    fact is checked against another source (README.md phrases, check_readme_phrases; the app's
    Accessibility screen strings; store/accessibility-status.json). An empty list isn't an answer."""
    if isinstance(node, dict):
        if "md" in node:
            claims = node.get("claims")
            if not isinstance(claims, list) or not claims:
                fail(f'{source}: {where} has no "claims" list, or an empty one. Name its claim ids (C1 to C12), '
                     'or ["none"] for a text that relies on no listing claim')
            if "none" in claims and len(claims) > 1:
                fail(f'{source}: {where} names "none" with claim ids {claims}')
            unknown = [c for c in claims if c not in CLAIM_IDS and c != "none"]
            if unknown:
                fail(f"{source}: {where} names unknown claims {unknown}")
        for key, value in node.items():
            check_claims(value, source, f"{where}.{key}")
    elif isinstance(node, list):
        for index, value in enumerate(node):
            check_claims(value, source, f"{where}[{index}]")


def md(entry, source="content", **values):
    text = entry["md"]
    for key, value in values.items():
        text = text.replace("{" + key + "}", value)
    return inline(text, source)


def plain(entry):
    """The text without Markdown, for titles and meta descriptions."""
    return INLINE_LINK.sub(r"\1", entry["md"]).replace("**", "")


def texts(data, source):
    return {key: md(value, source) for key, value in data.get("text", {}).items()}


def check_readme_phrases(entries, source):
    readme = readme_section("Requirements") + readme_section("Languages")
    for entry in entries:
        for phrase in entry.get("readme", []):
            if phrase not in readme:
                fail(f'{source}: "{entry["md"]}" relies on README.md saying {phrase!r}, and it no longer does')


# ---------------------------------------------------------------------------------------------
# Templates


def fill(template_name, values):
    template = read(f"site/templates/{template_name}")

    def value(match):
        key = match.group(1)
        if key not in values:
            fail(f"site/templates/{template_name}: no value for {{{{{key}}}}}")
        return values[key]

    return re.sub(r"\{\{(\w+)\}\}", value, template)


def svg_inline(path, css_class, label=None):
    """An SVG asset as inline markup: no prolog or comment, decorative unless labeled."""
    svg = read(path)
    svg = re.sub(r"<\?xml[^>]*\?>\s*", "", svg)
    svg = re.sub(r"<!--.*?-->\s*", "", svg, flags=re.S).strip()
    attributes = f'class="{css_class}" focusable="false" ' + ('aria-hidden="true"' if label is None else f'role="img" aria-label="{html.escape(label)}"')
    return svg.replace("<svg ", f"<svg {attributes} ", 1)


# ---------------------------------------------------------------------------------------------
# Assets


def hashed(source, out, name=None):
    """Copies an asset to out/assets/ with a content hash in its name; returns its address."""
    data = source.read_bytes() if isinstance(source, pathlib.Path) else source
    stem, suffix = (name or source.name).rsplit(".", 1)
    target = f"assets/{stem}.{hashlib.sha256(data).hexdigest()[:10]}.{suffix}"
    (out / target).parent.mkdir(parents=True, exist_ok=True)
    (out / target).write_bytes(data)
    return "/" + target


def tailwind():
    binary = SITE / "node_modules" / ".bin" / "tailwindcss"
    if not binary.exists():
        fail("site/node_modules is missing: run `npm ci --ignore-scripts` in site/ first")
    with tempfile.TemporaryDirectory() as tmp:
        target = pathlib.Path(tmp) / "site.css"
        result = subprocess.run([str(binary), "-i", str(SITE / "styles" / "site.css"), "-o", str(target), "--minify"],
                                cwd=ROOT, capture_output=True, text=True)
        if result.returncode != 0:
            fail("the Tailwind CLI failed:\n" + result.stderr)
        return target.read_text(encoding="utf-8")


def svg_size(path):
    svg = read(path)
    width = re.search(r'<svg[^>]*\swidth="([0-9.]+)', svg)
    height = re.search(r'<svg[^>]*\sheight="([0-9.]+)', svg)
    if not width or not height:
        fail(f"{path}: the SVG needs width and height attributes")
    return float(width.group(1)), float(height.group(1))


# ---------------------------------------------------------------------------------------------
# Pages


def apple_credit(pages_text, badge_shown):
    """Apple's credit line, naming only the Apple names the built pages use."""
    names = ["iPhone", "iPad", "Apple Watch"]
    used = [n for n in names if re.search(rf"\b{re.escape(n)}\b", pages_text)]
    if badge_shown:
        used = ["Apple", "the Apple logo"] + used
    elif re.search(r"\bApple\b", pages_text):
        used = ["Apple"] + used
    sentence = ""
    if used:
        listed = used[0] if len(used) == 1 else ", ".join(used[:-1]) + " and " + used[-1]
        verb = "is a trademark" if len(used) == 1 else "are trademarks"
        sentence = f"{listed} {verb} of Apple Inc., registered in the U.S. and other countries and regions."
    if "App Store" in pages_text:
        sentence += " App Store is a service mark of Apple Inc."
    return sentence.strip()


def build(out, preview):
    config = load_json("site/site.json")
    domain = config["domain"]
    base = f"https://{domain}"
    version = app_version()
    released = release_date(version)
    sha = commit()
    copyright_line = read("store/metadata/en-US/copyright.txt").strip()
    available = bool(config.get("available")) and bool(config.get("appStoreId"))
    badge_path = SITE / config["badge"]
    if config.get("available") and not config.get("appStoreId"):
        fail("site/site.json: available is true but appStoreId is missing")
    if available and not badge_path.exists():
        fail(f"site/site.json: available is true, but Apple's badge file {badge_path.relative_to(ROOT)} is missing")
    check_app_store_id(config.get("appStoreId"))

    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)

    common = content("common")
    common_text = texts(common, "site/content/common.json")

    # Assets with hashed names.
    font400 = hashed(SITE / "assets/fonts/inter-400.woff2", out, "fonts/inter-400.woff2")
    font600 = hashed(SITE / "assets/fonts/inter-600-700.woff2", out, "fonts/inter-600-700.woff2")
    (out / "assets/fonts").mkdir(parents=True, exist_ok=True)
    shutil.copy(SITE / "assets/fonts/OFL.txt", out / "assets/fonts/OFL.txt")
    icon_svg = hashed(SITE / "assets/icon.svg", out)
    touch_icon = hashed(SITE / "assets/apple-touch-icon.png", out)
    social = hashed(SITE / "assets/social.png", out)
    shutil.copy(SITE / "assets/favicon.ico", out / "favicon.ico")
    badge = hashed(badge_path, out) if available else None

    pages = {}
    home = content("home")
    privacy = content("privacy")
    support = content("support")
    accessibility = content("accessibility")
    notfound = content("404")

    check_listing_accessibility()
    pages["/"] = page_home(home, config, version, available, badge)
    pages["/privacy/"] = page_privacy(privacy, config, version, preview)
    pages["/support/"] = page_support(support, version)
    pages["/accessibility/"] = page_accessibility(accessibility, version)
    pages["/404.html"] = page_404(notfound)

    # The CSS, with the fonts' hashed names.
    css = tailwind()
    css = css.replace("/assets/fonts/inter-400.woff2", font400).replace("/assets/fonts/inter-600-700.woff2", font600)
    css_url = hashed(css.encode("utf-8"), out, "site.css")

    all_text = " ".join(re.sub(r"<[^>]+>", " ", p["main"]) for p in pages.values())
    credit = apple_credit(all_text + " " + plain(home["description"]), available)
    footer_values = {
        "footItems": nav_items(common_text, footer=True),
        "built": md(common["text"]["built"], "common", version=version, commit=sha[:7],
                    commitUrl=f"{config['repository']}/commit/{sha}"),
        "owner": md(common["text"]["owner"], "common", copyright=copyright_line),
        "apple": html.escape(credit, quote=False),
        "dng": common_text["dng"],
        "wrap": WRAP,
    }
    footer = fill("footer.html", footer_values)

    for path, page in pages.items():
        current = path if path != "/404.html" else None
        header = fill("header.html", {
            "headerClass": "band" if path == "/" else "border-b border-rule",
            "wrap": WRAP,
            "mark": svg_inline("site/assets/icon.svg", "size-9 flex-none"),
            "name": common_text["name"],
            "homeCurrent": ' aria-current="page"' if path == "/" else "",
            "navLabel": common_text["navLabel"],
            "navItems": nav_items(common_text, current=current),
        })
        meta = head_meta(page, path, base, social, common)
        html_text = fill("layout.html", {
            "csp": CSP,
            "title": html.escape(page["title"]),
            "meta": meta,
            "font400": font400,
            "css": css_url,
            "iconSvg": icon_svg,
            "touchIcon": touch_icon,
            "jsonld": page.get("jsonld", ""),
            "skip": common_text["skip"],
            "header": header,
            "main": page["main"],
            "footer": footer,
        })
        if re.search(r"\{\{\w+\}\}", html_text):
            fail(f"{path}: a template placeholder was left unfilled")
        target = out / ("404.html" if path == "/404.html" else path.strip("/") + "/index.html" if path != "/" else "index.html")
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(html_text, encoding="utf-8")

    public = [path for path, _, _ in PAGES]
    write_sitemap(out, base, public, released)
    (out / "robots.txt").write_text(f"User-agent: *\nAllow: /\n\nSitemap: {base}/sitemap.xml\n", encoding="utf-8")
    write_manifest(out, icon_svg, touch_icon)
    write_security_txt(out, base, config, released)
    if preview:
        (out / PREVIEW_MARK).write_text(
            "Built with --preview: the policy's draft-marker rule was skipped. Not for publishing.\n", encoding="utf-8")
    return {"version": version, "commit": sha, "released": str(released), "available": available, "preview": preview}


def check_app_store_id(site_id):
    """The site's appStoreId and AboutScreen.appStoreID agree when both exist (section 4.3)."""
    for swift in (ROOT / "Sources").rglob("*.swift"):
        match = re.search(r"appStoreID[^=\n]*=\s*\"?([0-9]+)\"?", swift.read_text(encoding="utf-8"))
        if match and site_id and str(site_id) != match.group(1):
            fail(f"site/site.json appStoreId ({site_id}) differs from {swift.relative_to(ROOT)} ({match.group(1)})")


def nav_items(t, current=None, footer=False):
    if footer:
        links = [("/", t["footHome"]), ("/privacy/", t["footPrivacy"]), ("/support/", t["footSupport"]),
                 ("/accessibility/", t["footAccessibility"]), ("https://github.com/Photivra/nope-camera", t["footSource"])]
        cls = "inline-flex items-center min-h-11 text-ink font-semibold text-small"
    else:
        links = [("/privacy/", t["navPrivacy"]), ("/support/", t["navSupport"]),
                 ("/accessibility/", t["navAccessibility"]), ("https://github.com/Photivra/nope-camera", t["navSource"])]
        cls = "inline-flex items-center min-h-11 px-2 font-semibold text-nav"
    items = []
    for href, label in links:
        mark = ' aria-current="page"' if href == current and not footer else ""
        items.append(f'<li><a class="{cls}" href="{href}"{mark}>{label}</a></li>')
    return "".join(items)


def head_meta(page, path, base, social, common):
    description = page.get("description")
    tags = []
    if description:
        tags.append(f'<meta name="description" content="{html.escape(description)}">')
    if path == "/404.html":
        tags.append('<meta name="robots" content="noindex">')
        return "\n".join(tags)
    url = base + path
    tags += [
        f'<link rel="canonical" href="{url}">',
        '<meta property="og:type" content="website">',
        '<meta property="og:site_name" content="Photivra Nope Camera">',
        f'<meta property="og:title" content="{html.escape(page["title"])}">',
        f'<meta property="og:description" content="{html.escape(description)}">',
        f'<meta property="og:url" content="{url}">',
        f'<meta property="og:image" content="{base}{social}">',
        '<meta property="og:image:width" content="1200">',
        '<meta property="og:image:height" content="630">',
        f'<meta property="og:image:alt" content="{html.escape(plain(common["text"]["socialAlt"]))}">',
        '<meta property="og:locale" content="en_US">',
        '<meta name="twitter:card" content="summary_large_image">',
    ]
    return "\n".join(tags)


def page_home(home, config, version, available, badge):
    t = texts(home, "site/content/home.json")
    check_readme_phrases(home["devices"], "site/content/home.json")
    first, groups, last = description_txt()
    names = home["groups"]
    group_html = []
    for heading, items in groups:
        if heading not in names:
            fail(f"description.txt: the group {heading!r} has no sentence-case name in site/content/home.json")
        lis = "".join(f'<li class="mb-2.5">{inline(item, "description.txt")}</li>' for item in items)
        group_html.append(f'<div><h3 class="mb-2 font-semibold text-h3 tracking-[-0.01em]">{html.escape(names[heading])}</h3><ul class="list-disc pl-5">{lis}</ul></div>')
    if available:
        # HTML's width and height are whole pixels; Apple's badge says 119.66407 × 40.
        width, height = svg_size(f"site/{config['badge']}")
        store_url = f"https://apps.apple.com/us/app/id{config['appStoreId']}"
        get = (f'<div class="mt-8 flex flex-wrap items-center gap-x-6 gap-y-4"><a class="inline-block m-2.5" href="{store_url}">'
               f'<img class="h-10 w-auto" src="{badge}" width="{round(width)}" height="{round(height)}" alt="{html.escape(plain(home["text"]["badgeLabel"]))}"></a>'
               f'<p class="text-small text-muted max-w-[19rem]">{t["badgeLine"]}</p></div>')
    else:
        get = (f'<div class="mt-8 max-w-[34rem] px-5 py-4 border border-rule rounded-small">'
               f'<p><strong class="block">{t["notYetTitle"]}</strong>{t["notYet"]}</p></div>')
    devices = "".join(f'<li class="mb-2.5">{md(d, "home")}</li>' for d in home["devices"])
    main = fill("home.html", {
        **t,
        "wrap": WRAP,
        "wordmark": svg_inline("site/assets/wordmark.svg", "wordmark block"),
        "lead": inline(first, "description.txt"),
        "get": get,
        "groups": "".join(group_html),
        "devices": devices,
        "license": inline(last, "description.txt"),
    })
    jsonld = {
        "@context": "https://schema.org",
        "@graph": [
            {"@type": "WebSite", "name": "Photivra Nope Camera", "url": f"https://{config['domain']}/"},
            {
                "@type": "MobileApplication",
                "name": "Photivra Nope Camera",
                "operatingSystem": "iOS",
                "applicationCategory": "PhotographyApplication",
                "softwareVersion": version,
                "description": first,
                "url": f"https://{config['domain']}/",
                "license": "https://www.gnu.org/licenses/gpl-3.0.html",
                "isAccessibleForFree": True,
                "inLanguage": "en-US",
                "publisher": {"@type": "Organization", "name": notice_holder(), "url": config["publisherUrl"]},
            },
        ],
    }
    if available:
        app = jsonld["@graph"][1]
        app["downloadUrl"] = f"https://apps.apple.com/us/app/id{config['appStoreId']}"
        app["offers"] = {"@type": "Offer", "price": "0", "priceCurrency": "USD"}
    data = json.dumps(jsonld, ensure_ascii=False, separators=(",", ":")).replace("<", "\\u003c")
    return {
        "title": plain(home["title"]),
        "description": plain(home["description"]),
        "main": main,
        "jsonld": f'<script type="application/ld+json">{data}</script>',
    }


def notice_holder():
    match = re.search(r"^Copyright \(C\) [0-9]{4} (.+)$", read("NOTICE"), re.M)
    if not match:
        fail("NOTICE: no copyright line")
    return match.group(1).strip()


def page_privacy(privacy, config, version, preview):
    t = texts(privacy, "site/content/privacy.json")
    policy = build_policy(config["policy"], version, preview)
    main = fill("privacy.html", {
        **t,
        "doc": DOC,
        "metaDl": META_DL,
        "title": inline(policy["title"]),
        "address": f"https://{config['domain']}/privacy/",
        "effectiveValue": html.escape(policy["effective"]),
        "updatedValue": html.escape(policy["updated"]),
        "versionValue": html.escape(policy["version"]),
        "tocItems": policy["toc"],
        "body": policy["body"],
    })
    return {"title": plain(privacy["title"]), "description": plain(privacy["description"]), "main": main}


def page_support(support, version):
    source = "site/content/support.json"
    t = texts(support, source)
    check_readme_phrases([support["text"]["tested"]], source)
    check_last_updated(source, support["lastUpdated"], [last_change(source)])
    requirements = readme_section("Requirements")
    paragraphs = [p.strip() for p in re.split(r"\n\s*\n", requirements) if p.strip()]
    intro = paragraphs[0]
    bullets = next((p for p in paragraphs if p.startswith("- ")), None)
    if not bullets:
        fail('README.md, "Requirements": no device list')
    device_items = [b[2:].strip() for b in bullets.splitlines()]
    devices = f'<p>{inline(" ".join(intro.split()), "README.md")}</p><ul>' + "".join(
        f"<li>{inline(item, 'README.md')}</li>" for item in device_items) + "</ul>"
    questions = "".join(
        f'<h3>{md(q["q"], source)}</h3><p>{md(q["a"], source)}</p>' for q in support["questions"])
    main = fill("support.html", {
        **t,
        "doc": DOC,
        "metaDl": META_DL,
        "questions": questions,
        "devices": devices,
        "lastUpdatedValue": html.escape(support["lastUpdated"]),
        "versionValue": version,
        "lastUpdatedLabel": md({"md": "Last updated"}),
        "versionLabel": md({"md": "App version"}),
    })
    return {"title": plain(support["title"]), "description": plain(support["description"]), "main": main}


def accessibility_status():
    """store/accessibility-status.json's devices, each manualPass null or a dated pass on a named device."""
    source = "store/accessibility-status.json"
    devices = load_json(source).get("devices")
    if not isinstance(devices, dict):
        fail(f'{source}: no "devices" object')
    for device, entry in devices.items():
        manual = entry.get("manualPass") if isinstance(entry, dict) else None
        if manual is None:
            continue
        if not isinstance(manual, dict) or not isinstance(manual.get("device"), str) or not manual["device"].strip():
            fail(f'{source}: {device}\'s manualPass needs {{"date": "YYYY-MM-DD", "device": "the model"}}, '
                 "or null until the pass is done")
        passed = iso_date(source, f"{device} manualPass date", manual.get("date"))
        if passed > utc_today():
            fail(f"{source}: {device}'s manualPass date {passed} is after today ({utc_today()}, UTC)")
    return devices


# The listing's accessibility sentence names these; it may only once an iPhone pass is recorded.
LISTING_ACCESSIBILITY = re.compile(r"VoiceOver|Voice Control|Switch Control|Full Keyboard Access|text sizes?|"
                                   r"larg(?:e|er|est) text|Dynamic Type|screen readers?|accessib\w*|assistive\w*|"
                                   r"Reduced? Motion", re.I)


def check_listing_accessibility():
    """The App Store description names accessibility features only after the iPhone manual pass
    (docs/store/README.md, C11; store/accessibility-status.json)."""
    source = "store/metadata/en-US/description.txt"
    named = sorted({m.group(0) for m in LISTING_ACCESSIBILITY.finditer(read(source))})
    iphone = accessibility_status().get("iPhone") or {}
    if named and not iphone.get("manualPass"):
        fail(f"{source} names {', '.join(named)}, but store/accessibility-status.json records no manual pass "
             "on an iPhone. Remove that sentence from description.txt, or record the pass")


ANA_FEATURES = ["VoiceOver", "Voice Control", "Larger Text", "Dark Interface", "Differentiate Without Color Alone",
                "Sufficient Contrast", "Reduced Motion", "Captions", "Audio Descriptions"]


def page_accessibility(page, version):
    source = "site/content/accessibility.json"
    t = texts(page, source)
    status = accessibility_status()
    check_last_updated(source, page["lastUpdated"], [last_change(source), last_change("store/accessibility-status.json")])
    rows = [(t["automatedLabel"], t["automatedValue"])]
    labels = {"iPhone": "By hand on an iPhone", "iPad": "By hand on an iPad", "Apple Watch": "On an Apple Watch"}
    declared_html = []
    any_pass = False
    for device in ("iPhone", "iPad", "Apple Watch"):
        if device not in status:
            fail(f"store/accessibility-status.json: no entry for {device}")
        entry = status[device]
        manual, declared = entry.get("manualPass"), entry.get("declared", [])
        unknown = [f for f in declared if f not in ANA_FEATURES]
        if unknown:
            fail(f"store/accessibility-status.json: {device} declares unknown features {unknown}")
        if declared and not manual:
            fail(f"store/accessibility-status.json: {device} declares features without a manual pass")
        if manual:
            any_pass = True
            value = f"Done on an {manual['device']}, {manual['date']}"
        else:
            value = "Not checked on a real watch" if device == "Apple Watch" else "Not yet done"
        rows.append((html.escape(labels[device]), html.escape(value)))
        if declared:
            declared_html.append(f"<p>Declared on the App Store for {html.escape(device)}: {html.escape(', '.join(declared))}.</p>")
    status_dl = "".join(f'<dt class="text-muted">{label}</dt><dd class="m-0 mb-2 last:mb-0 md:mb-0 font-semibold">{value}</dd>' for label, value in rows)
    passes = t["noPass"] if not any_pass else ""
    statements = []
    for group in page["appStatements"]:
        src = group["source"]
        swift_strings = app_strings(src) if src.endswith(".swift") else None
        if swift_strings is not None:
            if group.get("appHeading") not in swift_strings:
                fail(f"{source}: the heading {group.get('appHeading')!r} isn't a string of {src}")
            if group["heading"].lower() != group["appHeading"].lower():
                fail(f"{source}: {group['heading']!r} isn't the app's heading {group['appHeading']!r} in sentence case")
        items = []
        for item in group["items"]:
            text = item["md"]
            if swift_strings is not None:
                if normalize_quotes(text) not in {normalize_quotes(s) for s in swift_strings}:
                    fail(f"{source}: {text!r} isn't a string of {src}; the app's screen and the page must match")
            else:
                evidence = item.get("evidence")
                if not evidence:
                    fail(f"{source}: {text!r} needs evidence quoted from {src}")
                for quote in evidence:
                    if quote not in read(src):
                        fail(f"{source}: {src} no longer says {quote!r}, which {text!r} relies on")
            items.append(f"<li>{inline(text, source)}</li>")
        statements.append(f"<h3>{html.escape(group['heading'])}</h3><ul>{''.join(items)}</ul>")
    main = fill("accessibility.html", {
        **t,
        "doc": DOC,
        "metaDl": META_DL,
        "statusRows": status_dl,
        "passes": f"<p>{passes}</p>" if passes else "",
        "declared": "".join(declared_html),
        "statements": "".join(statements),
        "lastUpdatedValue": html.escape(page["lastUpdated"]),
        "versionValue": version,
        "lastUpdatedLabel": md({"md": "Last updated"}),
        "versionLabel": md({"md": "App version"}),
    })
    return {"title": plain(page["title"]), "description": plain(page["description"]), "main": main}


def normalize_quotes(text):
    return text.replace("’", "'").replace("‘", "'").replace("“", '"').replace("”", '"')


def app_strings(path):
    """The string literals of Text(...) in a SwiftUI file."""
    return {m.group(1).replace('\\"', '"') for m in re.finditer(r'Text\(\s*"((?:[^"\\]|\\.)*)"', read(path))}


def page_404(page):
    t = texts(page, "site/content/404.json")
    main = fill("404.html", {**t, "doc": DOC})
    return {"title": plain(page["title"]), "description": None, "main": main}


def write_sitemap(out, base, paths, released):
    urls = "".join(f"<url><loc>{base}{p}</loc><lastmod>{released}</lastmod></url>" for p in paths)
    (out / "sitemap.xml").write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        f'<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">{urls}</urlset>\n', encoding="utf-8")


def write_manifest(out, icon_svg, touch_icon):
    manifest = {
        "name": "Photivra Nope Camera",
        "short_name": "nope.",
        "start_url": "/",
        "display": "browser",
        "background_color": "#000000",
        "theme_color": "#000000",
        "icons": [
            {"src": icon_svg, "sizes": "any", "type": "image/svg+xml"},
            {"src": touch_icon, "sizes": "180x180", "type": "image/png"},
        ],
    }
    (out / "manifest.webmanifest").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


def write_security_txt(out, base, config, released):
    try:
        expires = released.replace(year=released.year + 1)
    except ValueError:  # 29 February
        expires = released.replace(year=released.year + 1, day=28)
    text = (
        f"Contact: {config['repository']}/security/advisories/new\n"
        f"Contact: mailto:{config['contactEmail']}\n"
        f"Expires: {expires.isoformat()}T00:00:00Z\n"
        "Preferred-Languages: en\n"
        f"Canonical: {base}/.well-known/security.txt\n"
    )
    (out / ".well-known").mkdir(exist_ok=True)
    (out / ".well-known" / "security.txt").write_text(text, encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--out", default=str(ROOT / "_site"), help="output directory (default: _site)")
    parser.add_argument("--preview", action="store_true", help="skip the policy's draft-marker rule (and its version and date rules while markers remain); not for publishing")
    args = parser.parse_args()
    try:
        info = build(pathlib.Path(args.out).resolve(), args.preview)
    except BuildError as error:
        print(f"build-site: {error}", file=sys.stderr)
        return 1
    mode = " (preview: not for publishing)" if info["preview"] else ""
    print(f"build-site: built {args.out} for {info['version']} at {info['commit'][:7]}{mode}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
