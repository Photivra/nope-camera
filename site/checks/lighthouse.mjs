// Lighthouse floors (docs/design/nope-site.md, 14.3 and decision 19): performance 95,
// accessibility 100, best practices 95, SEO 100, on the mobile profile, the median of three runs,
// for every page, against the built site on 127.0.0.1. The not-found page is noindex by design,
// so its SEO score is not held to the floor.
// One audit is skipped: "robots-txt". Lighthouse fetches robots.txt from inside the page, and the
// site's Content-Security-Policy (default-src 'none', section 12) blocks that fetch, so the audit
// reports a CSP violation rather than anything about the file. Crawlers fetch robots.txt
// directly and aren't affected. scripts/site_checks.py checks the file's lines instead.
//   node site/checks/lighthouse.mjs _site [runs]
import path from "node:path";
import * as chromeLauncher from "chrome-launcher";
import lighthouse from "lighthouse";
import { serve } from "./serve.mjs";

const pages = ["/", "/privacy/", "/support/", "/accessibility/", "/404.html"];

const floors = { performance: 95, accessibility: 100, "best-practices": 95, seo: 100 };
const root = path.resolve(process.argv[2] || "_site");
const runs = Number(process.argv[3] || 3);
const server = await serve(root);
const chrome = await chromeLauncher.launch({ chromeFlags: ["--headless=new", "--no-first-run"] });
const failures = [];
const median = (values) => values.sort((a, b) => a - b)[Math.floor(values.length / 2)];
for (const address of pages) {
  const scores = Object.fromEntries(Object.keys(floors).map((k) => [k, []]));
  const failedAudits = new Set();
  for (let run = 0; run < runs; run++) {
    const result = await lighthouse(server.origin + address, {
      port: chrome.port, output: "json", logLevel: "error", onlyCategories: Object.keys(floors),
      skipAudits: ["robots-txt"],
    });
    for (const key of Object.keys(floors)) {
      scores[key].push(Math.round(result.lhr.categories[key].score * 100));
      for (const ref of result.lhr.categories[key].auditRefs) {
        const audit = result.lhr.audits[ref.id];
        if (ref.weight > 0 && audit.score !== null && audit.score < 1) failedAudits.add(`${key}/${ref.id}`);
      }
    }
  }
  const line = Object.keys(floors).map((k) => `${k} ${median(scores[k])}`).join(", ");
  console.log(`${address}: ${line}`);
  for (const [key, floor] of Object.entries(floors)) {
    if (address === "/404.html" && key === "seo") continue;
    if (median(scores[key]) < floor) {
      const audits = [...failedAudits].filter((a) => a.startsWith(key + "/")).join(", ");
      failures.push(`${address}: ${key} ${median(scores[key])}, under ${floor} (${audits})`);
    }
  }
}
chrome.kill();
server.close();
if (failures.length) {
  for (const failure of failures) console.error(`site: lighthouse: ${failure}`);
  process.exit(1);
}
console.log(`lighthouse floors passed (median of ${runs} runs, mobile)`);
