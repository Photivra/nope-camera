#!/usr/bin/env python3
"""The site's own checks on a built _site/ (docs/design/nope-site.md, 14.3). Standard library only.

    python3 scripts/site_checks.py [--preview] DIR

Groups, each failure printed as "site: <group>: <what>":
- promises: no script but one JSON-LD block, no event handler attributes, no style attributes or
  elements, nothing loaded from another site, external links only from the allowed list, the
  Content-Security-Policy and referrer policy on every page, no forms, frames or embeds;
- links: every internal link and anchor resolves; no http: anywhere;
- search: one h1, unique titles, descriptions, canonical addresses, lang, the sitemap link, the
  sitemap and robots.txt, the not-found page, the structured data;
- truth: no preview build, no unfinished policy, the app version, the tokens, the badge, the
  font's characters, security.txt, no private host names (AGENTS.md rule 6);
- size: the budgets of section 11.
scripts/test-check-site.sh gives each rule a passing and a failing case.
"""
import argparse
import datetime
import gzip
import html.parser
import json
import pathlib
import re
import sys
import urllib.parse

ROOT = pathlib.Path(__file__).resolve().parent.parent
CSP = (
    "default-src 'none'; style-src 'self'; img-src 'self'; font-src 'self'; "
    "manifest-src 'self'; base-uri 'none'; form-action 'none'"
)
# External links a page may have (section 12). Anything else needs a reviewed change here.
ALLOWED_EXTERNAL = [
    re.compile(r"^https://github\.com/Photivra/nope-camera(/[A-Za-z0-9/_.\-]*)?$"),
    re.compile(r"^https://docs\.github\.com/site-policy/privacy-policies/github-general-privacy-statement$"),
    re.compile(r"^https://apps\.apple\.com/us/app/id[0-9]+$"),
    re.compile(r"^https://photivra\.com/$"),
    re.compile(r"^https://www\.gnu\.org/licenses/gpl-3\.0\.html$"),
    re.compile(r"^mailto:hello@photivra\.com$"),
]
PUBLIC = ["/", "/privacy/", "/support/", "/accessibility/"]
PREVIEW_MARK = "PREVIEW-NOT-FOR-PUBLISHING.txt"
KB = 1024
BUDGETS = {
    "html": 12 * KB,
    "html_privacy": 16 * KB,
    "css": 10 * KB,
    "fonts": 45 * KB,
    "icons": 8 * KB,
    "landing_first_view": 150 * KB,
    "landing_all": 400 * KB,
    "document_page": 80 * KB,
    "social": 120 * KB,
}
BANNED_ELEMENTS = {"form", "iframe", "frame", "frameset", "object", "embed", "applet", "base", "style", "audio", "video"}


class Page(html.parser.HTMLParser):
    """Collects what the checks need from one HTML file."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.elements = []  # (tag, attrs dict, line)
        self.ids = set()
        self.text = []
        self.scripts = []  # (attrs, content)
        self._script = None
        self.title = ""
        self._in_title = False
        self.h1 = 0
        self.head_order = []
        self._in_head = False

    def handle_starttag(self, tag, attrs):
        attributes = dict(attrs)
        self.elements.append((tag, attributes, self.getpos()[0]))
        if "id" in attributes:
            self.ids.add(attributes["id"])
        if tag == "head":
            self._in_head = True
        elif self._in_head:
            self.head_order.append((tag, attributes))
        if tag == "script":
            self._script = (attributes, [])
        if tag == "title":
            self._in_title = True
        if tag == "h1":
            self.h1 += 1

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)

    def handle_endtag(self, tag):
        if tag == "head":
            self._in_head = False
        if tag == "script" and self._script:
            self.scripts.append((self._script[0], "".join(self._script[1])))
            self._script = None
        if tag == "title":
            self._in_title = False

    def handle_data(self, data):
        if self._script is not None:
            self._script[1].append(data)
            return
        if self._in_title:
            self.title += data
        self.text.append(data)


class Checks:
    def __init__(self, out, preview):
        self.out = out
        self.preview = preview
        self.failures = []
        self.config = json.loads((ROOT / "site/site.json").read_text())
        self.domain = self.config["domain"]
        self.pages = {}
        for file in sorted(out.rglob("*.html")):
            parser = Page()
            parser.feed(file.read_text(encoding="utf-8"))
            self.pages[self.address(file)] = (file, parser)

    def address(self, file):
        relative = file.relative_to(self.out).as_posix()
        if relative == "index.html":
            return "/"
        if relative.endswith("/index.html"):
            return "/" + relative[: -len("index.html")]
        return "/" + relative

    def fail(self, group, message):
        self.failures.append(f"site: {group}: {message}")

    # -- promises ---------------------------------------------------------------------------

    def promises(self):
        for address, (file, page) in self.pages.items():
            if not file.read_text(encoding="utf-8").startswith("<!doctype html>\n"):
                self.fail("promises", f"{address}: the page must start with <!doctype html>")
            json_ld = 0
            for tag, attrs, line in page.elements:
                where = f"{address} line {line}"
                if tag in BANNED_ELEMENTS:
                    self.fail("promises", f"<{tag}> is not allowed ({where})")
                for name in attrs:
                    if name.lower().startswith("on"):
                        self.fail("promises", f"event handler attribute {name} ({where})")
                    if name.lower() == "style":
                        self.fail("promises", f"style attribute ({where})")
                if tag == "script":
                    if attrs.get("type") != "application/ld+json" or "src" in attrs:
                        self.fail("promises", f"a script that isn't the JSON-LD data block ({where})")
                    else:
                        json_ld += 1
                for name in ("src", "srcset", "poster", "data"):
                    if name in attrs:
                        for url in re.split(r",\s*", attrs[name]):
                            url = url.strip().split(" ")[0]
                            if not self.same_site(url):
                                self.fail("promises", f"{tag} {name} loads from another site: {url} ({where})")
                if tag == "link" and "href" in attrs and attrs.get("rel") != "canonical" and not self.same_site(attrs["href"]):
                    self.fail("promises", f"<link rel={attrs.get('rel')}> loads from another site: {attrs['href']} ({where})")
                if tag == "a":
                    href = attrs.get("href", "")
                    if self.is_external(href) and not any(p.match(href) for p in ALLOWED_EXTERNAL):
                        self.fail("promises", f"external link not on the allowed list: {href} ({where})")
                    if href.startswith("mailto:") and "?" in href:
                        self.fail("promises", f"mailto with a prefilled field: {href} ({where})")
            if json_ld > 1 or (json_ld and address != "/"):
                self.fail("promises", f"{address}: JSON-LD is allowed once, on the landing page only")
            head = page.head_order
            if len(head) < 2 or head[0][0] != "meta" or "charset" not in head[0][1]:
                self.fail("promises", f"{address}: the character set must be the first element of the head")
            elif head[1][0] != "meta" or head[1][1].get("http-equiv") != "Content-Security-Policy":
                self.fail("promises", f"{address}: the Content-Security-Policy must follow the character set")
            elif head[1][1].get("content") != CSP:
                self.fail("promises", f"{address}: the Content-Security-Policy differs from the design's")
            if not any(t == "meta" and a.get("name") == "referrer" and a.get("content") == "no-referrer" for t, a in head):
                self.fail("promises", f"{address}: no <meta name=referrer content=no-referrer>")
        for css in self.out.rglob("*.css"):
            text = css.read_text(encoding="utf-8")
            if "@import" in text:
                self.fail("promises", f"{css.name}: @import")
            for url in re.findall(r"url\(\s*['\"]?([^'\")]+)", text):
                if not self.same_site(url) and not url.startswith("data:"):
                    self.fail("promises", f"{css.name}: url() loads from another site: {url}")
        for js in list(self.out.rglob("*.js")) + list(self.out.rglob("*.mjs")):
            self.fail("promises", f"a JavaScript file: {js.relative_to(self.out)}")

    @staticmethod
    def same_site(url):
        parsed = urllib.parse.urlparse(url)
        return not parsed.scheme and not parsed.netloc

    def is_external(self, href):
        parsed = urllib.parse.urlparse(href)
        return bool(parsed.scheme) and not (parsed.scheme == "https" and parsed.netloc == self.domain)

    # -- links ------------------------------------------------------------------------------

    def links(self):
        for address, (file, page) in self.pages.items():
            for tag, attrs, line in page.elements:
                for name in ("href", "src", "content"):
                    value = attrs.get(name, "")
                    if value.startswith("http:"):
                        self.fail("links", f"http: address {value} ({address} line {line})")
                href = attrs.get("href") or attrs.get("src")
                if not href or self.is_external(href) or href.startswith("mailto:"):
                    continue
                if href.startswith(f"https://{self.domain}"):
                    href = href[len(f"https://{self.domain}"):] or "/"
                parsed = urllib.parse.urlparse(href)
                target_path = parsed.path or address
                if not target_path.startswith("/"):
                    self.fail("links", f"relative link {href} ({address} line {line}); use an address from the site root")
                    continue
                target = self.resolve(target_path)
                if target is None:
                    self.fail("links", f"broken link {href} ({address} line {line})")
                    continue
                if parsed.fragment:
                    target_address = self.address(target) if target.suffix == ".html" else None
                    ids = self.pages[target_address][1].ids if target_address in self.pages else set()
                    if parsed.fragment not in ids:
                        self.fail("links", f"broken anchor {href} ({address} line {line})")
        manifest = self.out / "manifest.webmanifest"
        if manifest.exists():
            for icon in json.loads(manifest.read_text()).get("icons", []):
                if self.resolve(icon["src"]) is None:
                    self.fail("links", f"manifest icon missing: {icon['src']}")
        for text_file in [self.out / "robots.txt", self.out / "sitemap.xml", self.out / ".well-known/security.txt"]:
            if text_file.exists() and re.search(r"\bhttp://(?!www\.sitemaps\.org/schemas)", text_file.read_text()):
                self.fail("links", f"http: address in {text_file.name}")

    def resolve(self, path):
        path = urllib.parse.unquote(path)
        candidate = self.out / path.lstrip("/")
        if path.endswith("/"):
            candidate = candidate / "index.html"
        return candidate if candidate.is_file() else None

    # -- search -----------------------------------------------------------------------------

    def search(self):
        titles = {}
        for address, (file, page) in self.pages.items():
            if page.h1 != 1:
                self.fail("search", f"{address}: {page.h1} h1 elements; exactly one is needed")
            title = page.title.strip()
            if not title:
                self.fail("search", f"{address}: no title")
            elif title in titles:
                self.fail("search", f"{address}: the same title as {titles[title]}")
            titles[title] = address
            html_tag = next((a for t, a, _ in page.elements if t == "html"), {})
            if html_tag.get("lang") != "en-US":
                self.fail("search", f'{address}: lang must be "en-US"')
            heads = {(t, a.get("name") or a.get("property") or a.get("rel")): a for t, a in page.head_order}
            if ("link", "sitemap") not in heads or heads[("link", "sitemap")].get("href") != "/sitemap.xml":
                self.fail("search", f"{address}: no sitemap link")
            if address == "/404.html":
                robots = heads.get(("meta", "robots"), {}).get("content", "")
                if "noindex" not in robots:
                    self.fail("search", "/404.html: no noindex")
                continue
            if not heads.get(("meta", "description"), {}).get("content"):
                self.fail("search", f"{address}: no meta description")
            canonical = heads.get(("link", "canonical"), {}).get("href", "")
            if canonical != f"https://{self.domain}{address}":
                self.fail("search", f"{address}: the canonical address must be https://{self.domain}{address}, not {canonical!r}")
            for name in ("og:title", "og:description", "og:url", "og:image", "og:type", "og:locale"):
                if not heads.get(("meta", name), {}).get("content"):
                    self.fail("search", f"{address}: no {name}")
        expected = set(PUBLIC)
        sitemap = self.out / "sitemap.xml"
        if not sitemap.exists():
            self.fail("search", "no sitemap.xml")
        else:
            listed = re.findall(r"<loc>https://" + re.escape(self.domain) + r"(/[^<]*)</loc>", sitemap.read_text())
            if set(listed) != expected or len(listed) != len(expected):
                self.fail("search", f"sitemap.xml must list exactly {sorted(expected)}, not {listed}")
            if "sitemaps.org/schemas/sitemap/0.9" not in sitemap.read_text():
                self.fail("search", "sitemap.xml isn't in the sitemaps.org 0.9 format")
        for address in expected:
            if address not in self.pages:
                self.fail("search", f"the public page {address} wasn't built")
        if "/404.html" not in self.pages:
            self.fail("search", "no 404.html")
        robots = self.out / "robots.txt"
        if not robots.exists() or f"Sitemap: https://{self.domain}/sitemap.xml" not in robots.read_text():
            self.fail("search", "robots.txt without the Sitemap line")
        elif any(line and not re.match(r"^(User-agent: \S+|Allow: /\S*|Disallow: /?\S*|Sitemap: https://\S+)$", line)
                 for line in robots.read_text().splitlines()):
            self.fail("search", "robots.txt has a line that isn't User-agent, Allow, Disallow or Sitemap")
        available = bool(self.config.get("available")) and bool(self.config.get("appStoreId"))
        for address, (file, page) in self.pages.items():
            for attrs, content in page.scripts:
                if attrs.get("type") != "application/ld+json":
                    continue
                try:
                    data = json.loads(content)
                except json.JSONDecodeError as error:
                    self.fail("search", f"{address}: JSON-LD doesn't parse ({error})")
                    continue
                text = json.dumps(data)
                for banned in ("aggregateRating", "review", "award"):
                    if f'"{banned}' in text:
                        self.fail("search", f"{address}: JSON-LD holds {banned}")
                if '"offers"' in text and not available:
                    self.fail("search", f"{address}: JSON-LD holds an offer while the app isn't available")

    # -- truth ------------------------------------------------------------------------------

    def truth(self):
        if (self.out / PREVIEW_MARK).exists() and not self.preview:
            self.fail("truth", "this is a --preview build, not for publishing")
        version = re.search(r"^MARKETING_VERSION = (\S+)$", (ROOT / "Config/Base.xcconfig").read_text(), re.M).group(1)
        privacy = self.pages.get("/privacy/")
        if privacy:
            text = " ".join(privacy[1].text)
            markers = re.search(r"\[[^\]]*\]", text) or re.search(r"\bdraft\b", text, re.I)
            if markers and not self.preview:
                self.fail("truth", "/privacy/: a [bracketed] item or the word draft on the policy page")
            if not markers:
                values = re.findall(r'<dt[^>]*>App version</dt><dd[^>]*>([^<]*)</dd>', privacy[0].read_text())
                if values != [version]:
                    self.fail("truth", f"/privacy/: the policy's app version {values} isn't the app's ({version})")
        badge = self.config.get("badge", "")
        available = bool(self.config.get("available")) and bool(self.config.get("appStoreId"))
        stem = pathlib.Path(badge).stem
        for address, (file, page) in self.pages.items():
            for tag, attrs, _ in page.elements:
                if tag == "img" and stem and stem in attrs.get("src", "") and not available:
                    self.fail("truth", f"{address}: the App Store badge is shown while the app isn't available")
                if tag == "a" and attrs.get("href", "").startswith("https://apps.apple.com") and not available:
                    self.fail("truth", f"{address}: an App Store link while the app isn't available")
        self.tokens()
        self.font_characters()
        self.security_txt()
        host = re.compile(r"[a-z0-9-]*" + "stag" + r"ing[a-z0-9-]*([.][a-z0-9-]+)*[.](com|dev|app|net|org|io)([^a-z0-9-]|$)", re.I)
        for file in self.out.rglob("*"):
            if file.is_file() and file.suffix in {".html", ".txt", ".xml", ".css", ".webmanifest", ".svg"}:
                if host.search(file.read_text(encoding="utf-8", errors="replace")):
                    self.fail("truth", f"a private test deployment host name in {file.relative_to(self.out)} (AGENTS.md rule 6)")

    def tokens(self):
        """Six site values must equal the app's tokens in docs/design/tokens.md (14.2)."""
        tokens = (ROOT / "docs/design/tokens.md").read_text()

        def token(name):
            match = re.search(rf"^\| `{name}` \|.*?\| `(#[0-9A-Fa-f]{{6}})` \|", tokens, re.M)
            return match.group(1).upper() if match else None

        def radius(name):
            match = re.search(rf"^\| `{name}` \| ([0-9]+) \|", tokens, re.M)
            return match.group(1) if match else None

        css = (ROOT / "site/styles/site.css").read_text()
        theme = re.search(r"@theme \{(.*?)\n\}", css, re.S).group(1)
        dark = re.search(r"@media \(prefers-color-scheme: dark\) \{(.*?)\n\}", css, re.S).group(1)

        def value(block, name):
            match = re.search(rf"--{name}:\s*([^;]+);", block)
            return match.group(1).strip().upper() if match else None

        pairs = [
            ("mark", value(theme, "color-mark"), token("mark")),
            ("period", value(theme, "color-period"), token("markPeriod")),
            ("band", value(theme, "color-band"), token("launchBackground")),
            ("dark ground", value(dark, "color-ground"), token("launchBackground")),
            ("dark muted", value(dark, "color-muted"), token("labelSecondary")),
            ("radius small", (value(theme, "radius-small") or "").removesuffix("PX"), radius("small")),
            ("radius large", (value(theme, "radius-large") or "").removesuffix("PX"), radius("large")),
        ]
        for name, site_value, app_value in pairs:
            if not app_value or site_value != app_value:
                self.fail("truth", f"token {name}: the site has {site_value}, docs/design/tokens.md has {app_value}")
        for svg in ("wordmark.svg", "icon.svg"):
            text = (ROOT / "site/assets" / svg).read_text()
            fills = {f.upper() for f in re.findall(r'fill="(#[0-9A-Fa-f]{6})"', text)}
            if token("markPeriod") not in fills or token("mark") not in fills:
                self.fail("truth", f"site/assets/{svg}: the mark and period must be {token('mark')} and {token('markPeriod')}")
            if "#6AC5DD" in fills:
                self.fail("truth", f"site/assets/{svg}: #6AC5DD is the launch screen's asset-compiler value, not the web teal")

    def font_characters(self):
        allowed = set()
        for line in (ROOT / "site/assets/fonts/charset.txt").read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            first, _, last = line[2:].partition("-")
            allowed.update(range(int(first, 16), int(last or first, 16) + 1))
        allowed.update({0x0A, 0x09, 0x0D})
        for address, (file, page) in self.pages.items():
            missing = sorted({ch for ch in "".join(page.text) if ord(ch) not in allowed})
            if missing:
                self.fail("truth", f"{address}: characters outside the font subset {missing} (site/assets/fonts/charset.txt)")

    def security_txt(self):
        path = self.out / ".well-known/security.txt"
        if not path.exists():
            self.fail("truth", "no /.well-known/security.txt")
            return
        text = path.read_text()
        contacts = re.findall(r"^Contact: (.+)$", text, re.M)
        if not contacts or "security/advisories/new" not in contacts[0] or f"mailto:{self.config['contactEmail']}" not in contacts:
            self.fail("truth", "security.txt: Contact must be private vulnerability reporting first, then the email address")
        match = re.search(r"^Expires: (\d{4}-\d{2}-\d{2})T00:00:00Z$", text, re.M)
        if not match or datetime.date.fromisoformat(match.group(1)) <= datetime.datetime.now(datetime.timezone.utc).date():
            self.fail("truth", "security.txt: Expires is missing or not in the future")
        if f"Canonical: https://{self.domain}/.well-known/security.txt" not in text:
            self.fail("truth", "security.txt: no Canonical line with its own address")

    # -- size -------------------------------------------------------------------------------

    def size(self):
        def served(path):
            data = path.read_bytes()
            if path.suffix in {".html", ".css", ".svg", ".txt", ".xml", ".webmanifest", ".ico", ".json"}:
                return len(gzip.compress(data, compresslevel=6, mtime=0))
            return len(data)

        def asset(page, kinds):
            files = []
            for tag, attrs, _ in page.elements:
                url = attrs.get("src") or (attrs.get("href") if tag == "link" else None)
                if url and self.same_site(url) and any(url.endswith(k) for k in kinds):
                    target = self.resolve(url)
                    if target:
                        files.append(target)
            return files

        for address, (file, page) in self.pages.items():
            limit = BUDGETS["html_privacy"] if address == "/privacy/" else BUDGETS["html"]
            if served(file) > limit:
                self.fail("size", f"{address}: HTML {served(file)} bytes, over {limit}")
        css_files = list(self.out.rglob("*.css"))
        if len(css_files) != 1:
            self.fail("size", f"{len(css_files)} CSS files; the site has one")
        for css in css_files:
            if served(css) > BUDGETS["css"]:
                self.fail("size", f"{css.name}: {served(css)} bytes, over {BUDGETS['css']}")
        fonts = list(self.out.rglob("*.woff2"))
        if len(fonts) > 2 or sum(served(f) for f in fonts) > BUDGETS["fonts"]:
            self.fail("size", f"fonts: {len(fonts)} files, {sum(served(f) for f in fonts)} bytes; budget 2 files, {BUDGETS['fonts']}")
        icons = [self.out / "favicon.ico"] + list((self.out / "assets").glob("icon.*.svg"))
        icon_bytes = sum(served(f) for f in icons if f.exists())
        if icon_bytes > BUDGETS["icons"]:
            self.fail("size", f"icons: {icon_bytes} bytes, over {BUDGETS['icons']}")
        for social in (self.out / "assets").glob("social.*.png"):
            if served(social) > BUDGETS["social"]:
                self.fail("size", f"{social.name}: {served(social)} bytes, over {BUDGETS['social']}")
        for address, (file, page) in self.pages.items():
            if address == "/404.html":
                continue
            loaded = {file} | set(asset(page, [".css", ".woff2", ".png", ".svg", ".avif", ".webp", ".ico"]))
            loaded |= set(fonts) | {f for f in icons if f.exists()}
            loaded = {f for f in loaded if "apple-touch-icon" not in f.name}
            total = sum(served(f) for f in loaded)
            if address == "/":
                eager = {f for f in loaded if not self.lazy(page, f)}
                first = sum(served(f) for f in eager)
                if first > BUDGETS["landing_first_view"]:
                    self.fail("size", f"/: first view {first} bytes, over {BUDGETS['landing_first_view']}")
                if total > BUDGETS["landing_all"]:
                    self.fail("size", f"/: everything {total} bytes, over {BUDGETS['landing_all']}")
            elif total > BUDGETS["document_page"]:
                self.fail("size", f"{address}: {total} bytes, over {BUDGETS['document_page']}")

    def lazy(self, page, file):
        for tag, attrs, _ in page.elements:
            if tag == "img" and attrs.get("loading") == "lazy" and file.name in attrs.get("src", "") + attrs.get("srcset", ""):
                return True
        return False

    def run(self):
        if not self.pages:
            self.fail("links", f"no pages in {self.out}")
        for group in (self.promises, self.links, self.search, self.truth, self.size):
            group()
        return self.failures


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("out", nargs="?", default=str(ROOT / "_site"))
    parser.add_argument("--preview", action="store_true", help="allow a --preview build (local use only)")
    args = parser.parse_args()
    out = pathlib.Path(args.out)
    if not out.is_dir():
        print(f"site: no built site at {out}; run scripts/build-site.py first", file=sys.stderr)
        return 1
    failures = Checks(out, args.preview).run()
    for failure in failures:
        print(failure, file=sys.stderr)
    if failures:
        print(f"site checks failed: {len(failures)} problem(s)", file=sys.stderr)
        return 1
    print("site checks passed (promises, links, search, truth, size)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
