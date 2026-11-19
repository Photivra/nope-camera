// Renders the site's raster brand images from the committed SVG and font files (a maintainer
// tool, not part of the build; the outputs are committed in site/assets/):
//   apple-touch-icon.png  180 x 180, the app icon without rounded corners (iOS rounds them)
//   favicon.ico           32 x 32, the app icon (one PNG inside an ICO container)
//   social.png            1200 x 630, the wordmark lockup on black with the tagline and the scoped
//                         sentence in Inter (docs/design/nope-site.md, section 10)
// Run from site/ after `npm ci --ignore-scripts`, with Google Chrome installed:
//   node tools/render-images.mjs
// Chrome's screenshots carry no metadata beyond the image itself.
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import { fileURLToPath } from "node:url";
import path from "node:path";
import { Launcher } from "chrome-launcher";
import puppeteer from "puppeteer-core";

const site = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const root = path.resolve(site, "..");
const assets = path.join(site, "assets");
const strip = (svg) => svg.replace(/<\?xml[^>]*\?>\s*/, "").replace(/<!--[\s\S]*?-->\s*/g, "");
const icon = strip(readFileSync(path.join(assets, "icon.svg"), "utf8"));
const square = icon.replace(/ rx="225"/, "");
const wordmark = strip(readFileSync(path.join(assets, "wordmark.svg"), "utf8"));
const description = readFileSync(path.join(root, "store/metadata/en-US/description.txt"), "utf8");
const sentence = description.split(/(?<=\.)\s/)[0];
const font = (name) => `url("file://${path.join(assets, "fonts", name)}") format("woff2")`;

const executablePath = process.env.CHROME_PATH || Launcher.getInstallations()[0];
const browser = await puppeteer.launch({ executablePath, headless: true, args: ["--allow-file-access-from-files"] });
const page = await browser.newPage();

const tmp = mkdtempSync(path.join(os.tmpdir(), "nope-site-images-"));
async function shot(html, width, height, transparent = false) {
  await page.setViewport({ width, height, deviceScaleFactor: 1 });
  const file = path.join(tmp, "page.html");
  writeFileSync(file, `<!doctype html><html><head><style>
    @font-face{font-family:Inter;font-weight:400;src:${font("inter-400.woff2")}}
    @font-face{font-family:Inter;font-weight:600 700;src:${font("inter-600-700.woff2")}}
    html,body{margin:0;width:${width}px;height:${height}px;overflow:hidden;background:${transparent ? "transparent" : "#000"}}
    svg.fill{display:block;width:${width}px;height:${height}px}
  </style></head><body>${html}</body></html>`);
  await page.goto(`file://${file}`, { waitUntil: "load" });
  await page.evaluate(() => document.fonts.ready);
  return page.screenshot({ type: "png", omitBackground: transparent });
}

const fill = (svg) => svg.replace("<svg ", '<svg class="fill" ');
writeFileSync(path.join(assets, "apple-touch-icon.png"), await shot(fill(square), 180, 180));

const favicon = await shot(fill(icon), 32, 32, true);
// An ICO file with one 32 x 32 PNG image (the ICONDIR header, one ICONDIRENTRY, the PNG).
const header = Buffer.alloc(22);
header.writeUInt16LE(0, 0); header.writeUInt16LE(1, 2); header.writeUInt16LE(1, 4);
header.writeUInt8(32, 6); header.writeUInt8(32, 7); header.writeUInt8(0, 8); header.writeUInt8(0, 9);
header.writeUInt16LE(1, 10); header.writeUInt16LE(32, 12);
header.writeUInt32LE(favicon.length, 14); header.writeUInt32LE(22, 18);
writeFileSync(path.join(site, "assets", "favicon.ico"), Buffer.concat([header, favicon]));

const social = `<div style="box-sizing:border-box;width:1200px;height:630px;padding:84px 96px;color:#F2F2F7;font-family:Inter">
  <div style="width:${(2.4709 * 150).toFixed(1)}px">${wordmark.replace("<svg ", '<svg style="display:block;width:100%;height:auto" ')}</div>
  <div style="margin-top:22px;font-weight:600;font-size:40px;letter-spacing:-0.01em">Photivra Nope Camera</div>
  <div style="margin-top:56px;font-weight:600;font-size:40px;letter-spacing:-0.01em">Processing? Nope. Tracking? Nope. Network? Nope.</div>
  <div style="margin-top:20px;font-weight:400;font-size:30px;line-height:1.4;color:#AEAEB2;max-width:980px">${sentence}</div>
</div>`;
writeFileSync(path.join(assets, "social.png"), await shot(social, 1200, 630));
await browser.close();
rmSync(tmp, { recursive: true, force: true });
console.log("wrote apple-touch-icon.png, favicon.ico and social.png");
