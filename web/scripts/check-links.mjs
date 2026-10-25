// Checks every internal link, image and anchor in dist/ after a build. Exits 1 if anything is broken.
// External links are listed (not fetched), so the owner can see where the site points.
import { readFileSync, readdirSync, statSync, existsSync } from "node:fs";
import { join, relative, dirname, posix } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "dist");
if (!existsSync(root)) {
  console.error("check-links: dist/ not found, run the build first");
  process.exit(1);
}

const files = [];
(function walk(dir) {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) walk(p);
    else files.push(p);
  }
})(root);

const html = files.filter((f) => f.endsWith(".html"));
const ids = new Map();
const pageOf = (file) => "/" + relative(root, file).split("\\").join("/");
for (const f of html) {
  const s = readFileSync(f, "utf8");
  ids.set(pageOf(f), new Set([...s.matchAll(/\sid="([^"]+)"/g)].map((m) => m[1])));
}

function resolveTarget(fromPage, url) {
  const [pathPart, hash = ""] = url.split("#");
  let path = pathPart;
  if (!path) path = fromPage;
  else if (!path.startsWith("/")) path = posix.join(posix.dirname(fromPage), path);
  path = decodeURI(path.split("?")[0]);
  let file = path;
  if (file.endsWith("/")) file += "index.html";
  else if (!posix.extname(file)) file += "/index.html";
  return { file, hash };
}

const broken = [];
const external = new Set();
let checked = 0;
for (const f of html) {
  const page = pageOf(f);
  const s = readFileSync(f, "utf8");
  const urls = [...s.matchAll(/\s(?:href|src)="([^"]+)"/g), ...s.matchAll(/\ssrcset="([^"]+)"/g)].flatMap((m) =>
    m[0].includes("srcset") ? m[1].split(",").map((x) => x.trim().split(/\s+/)[0]) : [m[1]],
  );
  for (const raw of urls) {
    const url = raw.replace(/&amp;/g, "&");
    if (/^(mailto:|tel:|data:)/.test(url)) continue;
    if (/^https?:\/\//.test(url)) {
      external.add(url);
      continue;
    }
    checked++;
    const { file, hash } = resolveTarget(page, url);
    const target = join(root, ...file.split("/").filter(Boolean));
    if (!existsSync(target)) {
      broken.push(`${page}: ${url} (no ${file})`);
      continue;
    }
    if (hash && file.endsWith(".html") && !ids.get(file)?.has(hash)) broken.push(`${page}: ${url} (no #${hash} on ${file})`);
  }
}

// Every page in the sitemap must exist
const sitemapFile = join(root, "sitemap.xml");
if (existsSync(sitemapFile)) {
  for (const m of readFileSync(sitemapFile, "utf8").matchAll(/<loc>https?:\/\/[^/]+(\/[^<]*)<\/loc>/g)) {
    checked++;
    const { file } = resolveTarget("/", m[1]);
    if (!existsSync(join(root, ...file.split("/").filter(Boolean)))) broken.push(`sitemap.xml: ${m[1]}`);
  }
} else broken.push("sitemap.xml is missing");
if (!existsSync(join(root, "robots.txt"))) broken.push("robots.txt is missing");

const ownHosts = [...external].filter((u) => !u.includes("malvoya-web.onrender.com"));
console.log(`check-links: ${html.length} pages, ${checked} internal links checked, ${ownHosts.length} distinct external links.`);
for (const u of ownHosts.sort()) console.log(`  external: ${u}`);
if (broken.length) {
  console.error(`check-links: ${broken.length} broken:`);
  for (const b of broken) console.error(`  ${b}`);
  process.exit(1);
}
console.log("check-links: no broken internal links.");
