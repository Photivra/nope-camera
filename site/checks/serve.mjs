// A static server for the built site on 127.0.0.1, as GitHub Pages serves it: a directory
// address serves its index.html, and an unknown address serves 404.html with status 404.
// Used only by the checks; nothing here is published.
import { createServer } from "node:http";
import { readFile, stat } from "node:fs/promises";
import path from "node:path";

const types = {
  ".html": "text/html; charset=utf-8", ".css": "text/css; charset=utf-8", ".woff2": "font/woff2",
  ".png": "image/png", ".svg": "image/svg+xml", ".ico": "image/x-icon", ".xml": "application/xml",
  ".txt": "text/plain; charset=utf-8", ".webmanifest": "application/manifest+json",
  ".avif": "image/avif", ".webp": "image/webp",
};

export async function serve(root) {
  const server = createServer(async (request, response) => {
    const url = new URL(request.url, "http://127.0.0.1");
    let file = path.join(root, decodeURIComponent(url.pathname));
    if (!file.startsWith(root)) { response.writeHead(400).end(); return; }
    try {
      if ((await stat(file)).isDirectory()) file = path.join(file, "index.html");
      const body = await readFile(file);
      response.writeHead(200, { "content-type": types[path.extname(file)] || "application/octet-stream" }).end(body);
    } catch {
      response.writeHead(404, { "content-type": types[".html"] }).end(await readFile(path.join(root, "404.html")));
    }
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  return { origin: `http://127.0.0.1:${server.address().port}`, close: () => server.close() };
}

export const pages = ["/", "/privacy/", "/support/", "/accessibility/", "/no-such-page/"];
