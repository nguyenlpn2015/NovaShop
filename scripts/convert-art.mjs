#!/usr/bin/env node
/**
 * Rasterise the SVGs written by `generate-product-art.py` into WebP.
 *
 * This step did not exist. `generate-product-art.py` ended by printing "now run
 * the conversion step" and no such step was in the repository, so the committed
 * WebPs were the output of something run once by hand and lost -- and it had
 * rendered every `fill="url(#gradient)"` as black. That is the signature of
 * ImageMagick's built-in MSVG renderer, which parses SVG but does not implement
 * gradients, and silently falls back to black rather than failing. The
 * catalogue's soft backdrops became black squares and the three hero banners
 * became black rectangles with two faint circles.
 *
 * A browser is used instead, for one reason: it is the same renderer that will
 * display the result. If a gradient survives here it survives on the page. No
 * ImageMagick, no librsvg, no delegate configuration to get wrong.
 *
 *     python3 scripts/generate-product-art.py
 *     node scripts/convert-art.mjs
 *
 * Chrome is found from CHROME_PATH or the usual install locations.
 */

import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { spawn } from "node:child_process";
import { dirname, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { tmpdir } from "node:os";

const MANIFEST = ".art-build/manifest.json";
const PORT = Number(process.env.CDP_PORT ?? 9333);

// 80 rather than 92. These are smooth gradients and flat fills, which is the
// easiest thing WebP has to encode; the difference is invisible at the sizes
// these are displayed and it is most of the file.
const QUALITY = Number(process.env.ART_QUALITY ?? 80);

const CANDIDATES = [
  process.env.CHROME_PATH,
  "C:/Program Files/Google/Chrome/Application/chrome.exe",
  "C:/Program Files (x86)/Google/Chrome/Application/chrome.exe",
  "/usr/bin/google-chrome",
  "/usr/bin/chromium",
  "/usr/bin/chromium-browser",
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
].filter(Boolean);

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function findChrome() {
  const found = CANDIDATES.find((p) => existsSync(p));
  if (!found) {
    console.error("No Chrome found. Set CHROME_PATH to the executable.");
    process.exit(1);
  }
  return found;
}

/** Minimal CDP session. A dependency-free client is shorter than the argument
 *  for adding puppeteer to a repository that otherwise has no Node tooling. */
async function connect(wsUrl) {
  const ws = new WebSocket(wsUrl);
  await new Promise((res, rej) => {
    ws.addEventListener("open", res, { once: true });
    ws.addEventListener("error", rej, { once: true });
  });

  let id = 0;
  const pending = new Map();
  const seen = [];
  ws.addEventListener("message", (event) => {
    const msg = JSON.parse(event.data);
    if (msg.id && pending.has(msg.id)) {
      const { resolve: ok, reject: no } = pending.get(msg.id);
      pending.delete(msg.id);
      msg.error ? no(new Error(JSON.stringify(msg.error))) : ok(msg.result);
    } else if (msg.method) seen.push(msg.method);
  });

  return {
    ws,
    seen,
    send(method, params = {}) {
      const n = ++id;
      ws.send(JSON.stringify({ id: n, method, params }));
      return new Promise((ok, no) => pending.set(n, { resolve: ok, reject: no }));
    },
  };
}

const jobs = JSON.parse(readFileSync(MANIFEST, "utf8"));
const chrome = findChrome();
const profile = resolve(tmpdir(), "novashop-art-profile");

const child = spawn(
  chrome,
  [
    "--headless=new",
    "--disable-gpu",
    "--hide-scrollbars",
    `--remote-debugging-port=${PORT}`,
    `--user-data-dir=${profile}`,
    "--no-first-run",
    "--force-device-scale-factor=1",
    // The SVGs are read from disk, so the renderer needs local file access.
    "--allow-file-access-from-files",
    "about:blank",
  ],
  { stdio: "ignore", detached: false },
);

// Wait for the debugging endpoint rather than sleeping a guessed interval.
let version = null;
for (let attempt = 0; attempt < 60 && !version; attempt += 1) {
  try {
    version = await (await fetch(`http://127.0.0.1:${PORT}/json/version`)).json();
  } catch {
    await sleep(250);
  }
}
if (!version) {
  console.error("Chrome did not expose a debugging port.");
  child.kill();
  process.exit(1);
}
console.log(`renderer: ${version.Browser}`);

const target = await (
  await fetch(`http://127.0.0.1:${PORT}/json/new?about:blank`, { method: "PUT" })
).json();
const session = await connect(target.webSocketDebuggerUrl);
await session.send("Page.enable");
await session.send("Runtime.enable");

let written = 0;
for (const job of jobs) {
  await session.send("Emulation.setDeviceMetricsOverride", {
    width: job.width,
    height: job.height,
    deviceScaleFactor: 1,
    mobile: false,
  });

  // Transparency is set here, on the emulation layer. `omitBackground` is
  // Puppeteer's wrapper for exactly this call and does not exist in the
  // protocol; passing it to captureScreenshot is silently ignored, and every
  // file comes out composited onto opaque white.
  if (job.transparent) {
    await session.send("Emulation.setDefaultBackgroundColorOverride", {
      color: { r: 0, g: 0, b: 0, a: 0 },
    });
  } else {
    await session.send("Emulation.setDefaultBackgroundColorOverride");
  }

  session.seen.length = 0;
  await session.send("Page.navigate", {
    url: pathToFileURL(resolve(job.svg)).href,
  });
  const deadline = Date.now() + 15000;
  while (Date.now() < deadline && !session.seen.includes("Page.loadEventFired")) {
    await sleep(20);
  }

  // Refuse to rasterise a document that is not an SVG.
  //
  // XML forbids `--` inside a comment. One prose comment in the generator
  // contained an em-dash written as two hyphens, every product SVG failed to
  // parse, and Chrome rendered its pink "This page contains the following
  // errors" page instead. Without this check the script screenshotted that page
  // 64 times, wrote them over the catalogue, and reported "68 WebP files
  // written" -- a green run that had destroyed every product image.
  const ok = await session.send("Runtime.evaluate", {
    expression: `(() => {
      const root = document.documentElement;
      if (!root || root.tagName.toLowerCase() !== 'svg') {
        return 'root element is <' + (root ? root.tagName : 'none') + '>, not <svg>';
      }
      if (document.getElementsByTagName('parsererror').length) return 'XML parse error';
      return 'ok';
    })()`,
  });
  if (ok.result.value !== "ok") {
    console.error(`\n${job.svg}: ${ok.result.value}`);
    console.error("Nothing written. Fix the SVG and re-run.");
    session.ws.close();
    child.kill();
    process.exit(1);
  }

  // An SVG document loads with a default margin, which would offset the artwork
  // by 8px and crop the same amount off the right and bottom edges.
  await session.send("Runtime.evaluate", {
    expression:
      "document.documentElement.style.margin='0';" +
      "document.documentElement.style.padding='0';" +
      "document.documentElement.style.background='transparent';",
  });
  await sleep(40);

  const shot = await session.send("Page.captureScreenshot", {
    format: "webp",
    quality: QUALITY,
  });

  mkdirSync(dirname(job.out), { recursive: true });
  writeFileSync(job.out, Buffer.from(shot.data, "base64"));
  written += 1;
}

console.log(`${written} WebP files written`);

session.ws.close();
await fetch(`http://127.0.0.1:${PORT}/json/close/${target.id}`).catch(() => {});
child.kill();
