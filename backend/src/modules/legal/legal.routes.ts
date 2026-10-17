import { Router, Request, Response } from "express";
import fs from "fs";
import path from "path";
import crypto from "crypto";
import { escapeHtml } from "../../services/notificationDeliveryService";

/**
 * Public legal pages (privacy policy, terms). The Markdown files in /legal are the single source
 * of truth: the apps and the Google Play listing link here.
 */
const router = Router();

const DOCS: Record<string, { file: string; title: string }> = {
  privacy: { file: "privacy_policy.md", title: "Privacy Policy" },
  terms: { file: "terms_of_service.md", title: "Terms of Service" },
  sellers: { file: "vendor_terms.md", title: "Seller Terms" },
  couriers: { file: "courier_agreement.md", title: "Courier Agreement" },
  "delete-account": { file: "account_deletion.md", title: "Delete your account" },
};
// Other names the apps use for the same pages
const ALIASES: Record<string, string> = { "vendor-terms": "sellers", "courier-agreement": "couriers", "account-deletion": "delete-account" };

function readDoc(file: string) {
  for (const dir of LEGAL_DIRS) {
    const p = path.join(dir, file);
    if (fs.existsSync(p)) return fs.readFileSync(p, "utf8");
  }
  return null;
}

/**
 * The version of the agreement a new account accepts: the document's name plus the first 12 hex characters of
 * the SHA-256 of its text, so every change to the text is a new version without anyone having to remember it.
 */
const versions = new Map<string, string>();
export function termsVersionFor(role: string) {
  const doc = role === "VENDOR" ? "sellers" : role === "COURIER" ? "couriers" : "terms";
  if (!versions.has(doc)) {
    const text = readDoc(DOCS[doc].file);
    versions.set(doc, `${DOCS[doc].file.replace(/\.md$/, "")}@${text ? crypto.createHash("sha256").update(text.replace(/\r/g, "")).digest("hex").slice(0, 12) : "unknown"}`);
  }
  return versions.get(doc)!;
}

// The repository is deployed whole; the API runs from /backend
const LEGAL_DIRS = [path.resolve(process.cwd(), "..", "legal"), path.resolve(__dirname, "..", "..", "..", "..", "legal")];
const cache = new Map<string, string>();

function inline(text: string) {
  return escapeHtml(text)
    .replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>")
    .replace(/\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)/g, '<a href="$2">$1</a>');
}

/** Small Markdown subset used by the legal texts: headings, paragraphs, lists, quotes, tables. */
export function renderMarkdown(md: string) {
  const out: string[] = [];
  const lines = md.replace(/\r/g, "").split("\n");
  let list = false;
  let para: string[] = [];
  const flushPara = () => {
    if (para.length) out.push(`<p>${inline(para.join(" "))}</p>`);
    para = [];
  };
  const closeList = () => {
    if (list) out.push("</ul>");
    list = false;
  };

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const heading = /^(#{1,4})\s+(.*)$/.exec(line);
    if (heading) {
      flushPara();
      closeList();
      const level = heading[1].length;
      out.push(`<h${level}>${inline(heading[2])}</h${level}>`);
    } else if (/^\s*[-*]\s+/.test(line)) {
      flushPara();
      if (!list) out.push("<ul>");
      list = true;
      out.push(`<li>${inline(line.replace(/^\s*[-*]\s+/, ""))}</li>`);
    } else if (/^>\s?/.test(line)) {
      flushPara();
      closeList();
      out.push(`<blockquote>${inline(line.replace(/^>\s?/, ""))}</blockquote>`);
    } else if (/^\|.*\|\s*$/.test(line)) {
      flushPara();
      closeList();
      const rows: string[][] = [];
      while (i < lines.length && /^\|.*\|\s*$/.test(lines[i])) {
        const cells = lines[i].trim().slice(1, -1).split("|").map((c) => c.trim());
        if (!cells.every((c) => /^:?-{2,}:?$/.test(c))) rows.push(cells);
        i++;
      }
      i--;
      const [head, ...body] = rows;
      out.push(
        "<table><thead><tr>" + head.map((c) => `<th>${inline(c)}</th>`).join("") + "</tr></thead><tbody>" +
          body.map((r) => "<tr>" + r.map((c) => `<td>${inline(c)}</td>`).join("") + "</tr>").join("") +
          "</tbody></table>"
      );
    } else if (!line.trim()) {
      flushPara();
      closeList();
    } else {
      closeList();
      para.push(line.trim());
    }
  }
  flushPara();
  closeList();
  return out.join("\n");
}

function load(doc: string) {
  if (cache.has(doc)) return cache.get(doc)!;
  const text = readDoc(DOCS[doc].file);
  if (text === null) return null;
  const html = renderMarkdown(text);
  cache.set(doc, html);
  return html;
}

router.get("/legal/:doc", (req: Request, res: Response) => {
  const doc = ALIASES[req.params.doc] ?? req.params.doc;
  const meta = Object.prototype.hasOwnProperty.call(DOCS, doc) ? DOCS[doc] : undefined;
  const body = meta ? load(doc) : null;
  if (!meta || !body) return res.status(404).type("text").send("Not found");
  res.set("Cache-Control", "public, max-age=600");
  res.set("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'");
  res.type("html").send(`<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Malvoya – ${meta.title}</title>
<style>
body{margin:0;background:#F6F3EE;color:#17131C;font:16px/1.6 -apple-system,system-ui,"Segoe UI",sans-serif}
main{max-width:760px;margin:0 auto;padding:28px 20px 64px}
h1{font-size:26px;line-height:1.25;margin:0 0 8px}h2{font-size:19px;margin:32px 0 8px}h3{font-size:16px}
table{border-collapse:collapse;width:100%;font-size:14px;margin:12px 0;display:block;overflow-x:auto}
th,td{border:1px solid #E6E1EA;padding:8px;text-align:left;vertical-align:top}th{background:#EFE8F3}
blockquote{margin:12px 0;padding:10px 14px;background:#FFF7E6;border-left:4px solid #E08A00}
a{color:#6D2E8C}nav{font-size:14px;margin-bottom:20px}nav a{margin-right:14px}
</style></head><body><main>
<nav>${Object.entries(DOCS).map(([k, d]) => `<a href="/legal/${k}">${d.title}</a>`).join("")}</nav>
${body}
</main></body></html>`);
});

export default router;
