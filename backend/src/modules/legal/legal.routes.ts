import { Router, Request, Response } from "express";
import { escapeHtml } from "../../services/notificationDeliveryService";
import { sendError } from "../../lib/errors";
import {
  LEGAL_DOCS, LegalDoc, docFromParam, docUrl, formatHelsinki, legalState, readLegalFile, statusOf, versionText,
} from "./legalDocs";

/**
 * Public legal pages (privacy policy, terms). The apps and the Google Play listing link here. Since 2.11.0 the four
 * agreements show the version in force (LegalVersion), with every version listed at /legal/:doc/versions and each one
 * readable at /legal/:doc/v/:version; the Markdown files in /legal are where new versions are written.
 */
const router = Router();

// Pages: the four versioned documents (what is in force comes from LegalVersion) and the account-deletion help page
const PAGES: Record<string, { title: string; doc?: LegalDoc; file?: string }> = {
  privacy: { title: "Privacy Policy", doc: "privacy" },
  terms: { title: "Terms of Service", doc: "terms" },
  sellers: { title: "Seller Terms", doc: "seller-terms" },
  couriers: { title: "Courier Agreement", doc: "courier-agreement" },
  "delete-account": { title: "Delete your account", file: "account_deletion.md" },
  // How rights holders report copyright / trademark infringement, sellers' counter-notice, repeat infringers (2.16.0)
  "ip-notice": { title: "Copyright & trademark", file: "ip_notice.md" },
};
// Other names the apps use for the same pages
const ALIASES: Record<string, string> = {
  "vendor-terms": "sellers", "seller-terms": "sellers", "courier-agreement": "couriers", "account-deletion": "delete-account", "copyright": "ip-notice", "ip": "ip-notice",
};

const fileCache = new Map<string, string>();

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

export const PAGE_CSP = "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'";

/** The shared page shell (Birch background, the legal pages listed at the top). `body` and `banner` are already escaped. */
export function legalPageHtml(title: string, body: string, banner = "") {
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Malvoya – ${escapeHtml(title)}</title>
<style>
body{margin:0;background:#F6F3EE;color:#17131C;font:16px/1.6 -apple-system,system-ui,"Segoe UI",sans-serif}
main{max-width:760px;margin:0 auto;padding:28px 20px 64px}
h1{font-size:26px;line-height:1.25;margin:0 0 8px}h2{font-size:19px;margin:32px 0 8px}h3{font-size:16px}
table{border-collapse:collapse;width:100%;font-size:14px;margin:12px 0;display:block;overflow-x:auto}
th,td{border:1px solid #E6E1EA;padding:8px;text-align:left;vertical-align:top}th{background:#EFE8F3}
blockquote{margin:12px 0;padding:10px 14px;background:#FFF7E6;border-left:4px solid #E08A00}
.version{font-size:14px;color:#5b5363;margin:0 0 18px;padding:10px 14px;background:#fff;border:1px solid #E6E1EA;border-radius:12px}
code{word-break:break-all}
a{color:#6D2E8C}nav{font-size:14px;margin-bottom:20px}nav a{margin-right:14px}
</style></head><body><main>
<nav>${Object.entries(PAGES).map(([k, d]) => `<a href="/legal/${k}">${d.title}</a>`).join("")}</nav>
${banner}
${body}
</main></body></html>`;
}

function sendPage(res: Response, title: string, body: string, banner = "", maxAge = 300) {
  res.set("Cache-Control", `public, max-age=${maxAge}`);
  res.set("Content-Security-Policy", PAGE_CSP);
  res.type("html").send(legalPageHtml(title, body, banner));
}

const day = (d: Date) => formatHelsinki(d, "en");

/** "Version …, in force from …" and, while a change is announced, when the new version takes effect. */
function versionBanner(
  doc: LegalDoc,
  row: { version: string; effectiveAt: Date },
  pending: { version: string; effectiveAt: Date; summaryEn: string } | null,
  superseded = false,
) {
  const page = LEGAL_DOCS[doc].page;
  const lines = [
    `Version <code>${escapeHtml(row.version)}</code>${superseded ? " (no longer in force)" : ""} · in force from ${escapeHtml(day(row.effectiveAt))} · <a href="/legal/${page}/versions">all versions</a>`,
  ];
  if (pending) {
    lines.push(`<strong>Change announced:</strong> a new version takes effect on ${escapeHtml(day(pending.effectiveAt))}: ${escapeHtml(pending.summaryEn)} <a href="/legal/${page}/v/${encodeURIComponent(pending.version)}">Read the new version</a>`);
  }
  return `<p class="version">${lines.join("<br>")}</p>`;
}

function pageKey(param: string) {
  const key = ALIASES[param] ?? param;
  return Object.prototype.hasOwnProperty.call(PAGES, key) ? key : null;
}

router.get("/legal/:doc", async (req: Request, res: Response) => {
  const key = pageKey(req.params.doc);
  if (!key) return res.status(404).type("text").send("Not found");
  const page = PAGES[key];
  try {
    if (page.file) {
      if (!fileCache.has(page.file)) {
        const text = readLegalFile(page.file);
        if (text === null) return res.status(404).type("text").send("Not found");
        fileCache.set(page.file, renderMarkdown(text));
      }
      return sendPage(res, page.title, fileCache.get(page.file)!, "", 600);
    }
    // What is in force: the current version's stored text (never the repository file directly)
    const state = await legalState(page.doc!);
    if (!state.current) return res.status(404).type("text").send("Not found");
    const row = await versionText(page.doc!, state.current.version);
    if (!row) return res.status(404).type("text").send("Not found");
    sendPage(res, page.title, renderMarkdown(row.textSnapshot), versionBanner(page.doc!, row, state.pending));
  } catch (e) { sendError(res, e); }
});

/** Every version of a document (public): when it was published and took effect, and what changed. */
async function listVersions(req: Request, res: Response) {
  const doc = docFromParam(req.params.doc);
  if (!doc) return res.status(404).json({ ok: false, error: "Unknown document" });
  try {
    const now = new Date();
    const state = await legalState(doc, now);
    res.set("Cache-Control", "public, max-age=60");
    res.json({
      ok: true,
      doc,
      title: LEGAL_DOCS[doc].title,
      url: docUrl(doc),
      currentVersion: state.current?.version ?? null,
      pendingVersion: state.pending?.version ?? null,
      versions: state.rows.map((r) => ({
        version: r.version,
        status: statusOf(r, state, now),
        publishedAt: r.publishedAt,
        effectiveAt: r.effectiveAt,
        noticeDays: r.noticeDays,
        legalObligation: r.legalObligation,
        summary: { en: r.summaryEn, fi: r.summaryFi },
        url: docUrl(doc, r.version),
      })),
    });
  } catch (e) { sendError(res, e); }
}
router.get("/legal/:doc/versions", listVersions);
router.get("/api/v1/legal/:doc/versions", listVersions);

/** One exact version, as it was published (also announced and superseded ones). */
router.get("/legal/:doc/v/:version", async (req: Request, res: Response) => {
  const doc = docFromParam(req.params.doc);
  if (!doc) return res.status(404).type("text").send("Not found");
  try {
    const row = await versionText(doc, String(req.params.version));
    if (!row) return res.status(404).type("text").send("Not found");
    const now = new Date();
    const state = await legalState(doc, now);
    const status = row.effectiveAt.getTime() > now.getTime() ? "pending" : state.current?.id === row.id ? "current" : "superseded";
    const banner = status === "pending"
      ? `<p class="version"><strong>Announced version</strong> <code>${escapeHtml(row.version)}</code>: takes effect on ${escapeHtml(day(row.effectiveAt))}. ${escapeHtml(row.summaryEn)} · <a href="/legal/${LEGAL_DOCS[doc].page}/versions">all versions</a></p>`
      : versionBanner(doc, row, null, status === "superseded");
    // A stored version never changes; only an announced one may still become current
    sendPage(res, LEGAL_DOCS[doc].title.en, renderMarkdown(row.textSnapshot), banner, status === "pending" ? 300 : 3600);
  } catch (e) { sendError(res, e); }
});

export default router;
