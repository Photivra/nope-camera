// A real page load and the automated accessibility check (docs/design/nope-site.md, 14.3), in
// headless Chrome against the built site on 127.0.0.1. Fails on: any request to another host, a
// cookie, storage written, a console error or a CSP violation, sideways scrolling, and any axe-core
// violation at WCAG 2.2 A or AA, for every page in the light and dark themes and at 320 px wide.
//   node site/checks/browser-checks.mjs _site
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import path from "node:path";
import { Launcher } from "chrome-launcher";
import puppeteer from "puppeteer-core";
import { pages, serve } from "./serve.mjs";

const require = createRequire(import.meta.url);
const axeSource = readFileSync(require.resolve("axe-core/axe.min.js"), "utf8");
const root = path.resolve(process.argv[2] || "_site");
const server = await serve(root);
const executablePath = process.env.CHROME_PATH || Launcher.getInstallations()[0];
if (!executablePath) { console.error("browser checks: no Chrome found (set CHROME_PATH)"); process.exit(1); }
const browser = await puppeteer.launch({ executablePath, headless: true, args: ["--no-first-run"] });
const failures = [];
const views = [
  { name: "light, 1280 px", scheme: "light", width: 1280, height: 900 },
  { name: "dark, 1280 px", scheme: "dark", width: 1280, height: 900 },
  { name: "light, 320 px", scheme: "light", width: 320, height: 640 },
  { name: "dark, 320 px", scheme: "dark", width: 320, height: 640 },
];

for (const address of pages) {
  for (const view of views) {
    const context = await browser.createBrowserContext();
    const page = await context.newPage();
    const where = `${address} (${view.name})`;
    page.on("request", (request) => {
      const url = new URL(request.url());
      if (!["http:", "data:"].includes(url.protocol) || url.host !== new URL(server.origin).host) {
        if (url.protocol !== "data:") failures.push(`${where}: a request to another host: ${request.url()}`);
      }
    });
    page.on("console", (message) => {
      if (message.type() === "error" && !(address === "/no-such-page/" && /404/.test(message.text()))) {
        failures.push(`${where}: console error: ${message.text()}`);
      }
    });
    page.on("pageerror", (error) => failures.push(`${where}: page error: ${error.message}`));
    await page.setViewport({ width: view.width, height: view.height });
    await page.emulateMediaFeatures([{ name: "prefers-color-scheme", value: view.scheme }]);
    await page.goto(server.origin + address, { waitUntil: "networkidle0" });
    const state = await page.evaluate(() => ({
      local: localStorage.length, session: sessionStorage.length, cookie: document.cookie,
      overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth,
      scripts: [...document.scripts].filter((s) => s.type !== "application/ld+json").length,
    }));
    const cookies = await page.cookies();
    if (cookies.length || state.cookie) failures.push(`${where}: a cookie was set`);
    if (state.local || state.session) failures.push(`${where}: storage was written`);
    if (state.scripts) failures.push(`${where}: a script that isn't the JSON-LD block`);
    if (state.overflow > 0) failures.push(`${where}: scrolls sideways by ${state.overflow} px`);
    await page.evaluate(axeSource);
    const result = await page.evaluate(() => window.axe.run(document, {
      runOnly: { type: "tag", values: ["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22a", "wcag22aa"] },
      resultTypes: ["violations"],
    }));
    for (const violation of result.violations) {
      const targets = violation.nodes.map((n) => n.target.join(" ")).slice(0, 3).join("; ");
      failures.push(`${where}: axe ${violation.id} (${violation.impact}): ${violation.help} at ${targets}`);
    }
    await context.close();
  }
}
await browser.close();
server.close();
if (failures.length) {
  for (const failure of failures) console.error(`site: browser: ${failure}`);
  console.error(`browser checks failed: ${failures.length} problem(s)`);
  process.exit(1);
}
console.log(`browser checks passed: ${pages.length} pages x ${views.length} views, no outside requests, cookies, storage, console errors or axe violations (WCAG 2.2 A and AA)`);
