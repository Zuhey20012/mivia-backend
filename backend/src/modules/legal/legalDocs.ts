import fs from "fs";
import path from "path";
import crypto from "crypto";
import pino from "pino";
import { prisma } from "../../lib/prisma";
import { env } from "../../config/env";

const logger = pino({ name: "legal" });

/**
 * The versioned legal documents (since 2.11.0). The Markdown files in /legal are where texts are written, but what is
 * in force is the LegalVersion table: the first version of each document is taken from the file at start-up and is
 * effective at once; every later version only when an admin publishes it with a notice period, so a deploy never
 * changes a contract by itself.
 */
export type LegalDoc = "terms" | "seller-terms" | "courier-agreement" | "privacy";
export type AppRole = "CUSTOMER" | "VENDOR" | "COURIER" | "ADMIN";

export type DocDef = {
  doc: LegalDoc;
  file: string;
  /** Path of the public page: /legal/<page> */
  page: string;
  title: { en: string; fi: string };
  /** Roles bound by the document (their users are notified of changes and see it in GET /me/agreements) */
  roles: AppRole[];
  /** Minimum notice before a new version takes effect, unless the change is required by law */
  minNoticeDays: number;
  noticeRule: string;
  /** Whether role-critical actions are refused (428) until the current version is accepted */
  blocking: boolean;
};

export const LEGAL_DOCS: Record<LegalDoc, DocDef> = {
  terms: {
    doc: "terms", file: "terms_of_service.md", page: "terms",
    title: { en: "Terms of Service", fi: "Käyttöehdot" },
    roles: ["CUSTOMER"], minNoticeDays: 0, blocking: true,
    noticeRule: "No minimum, but every change is announced. The Terms promise 30 days' notice for changes to the customer's disadvantage.",
  },
  "seller-terms": {
    doc: "seller-terms", file: "vendor_terms.md", page: "sellers",
    title: { en: "Seller Terms", fi: "Myyjän ehdot" },
    roles: ["VENDOR"], minNoticeDays: 15, blocking: true,
    noticeRule: "At least 15 days (EU Platform-to-Business Regulation 2019/1150, Art. 3), unless the change is required by law.",
  },
  "courier-agreement": {
    doc: "courier-agreement", file: "courier_agreement.md", page: "couriers",
    title: { en: "Courier Agreement", fi: "Lähettisopimus" },
    roles: ["COURIER"], minNoticeDays: 15, blocking: true,
    noticeRule: "At least 15 days (Malvoya policy), unless the change is required by law.",
  },
  privacy: {
    doc: "privacy", file: "privacy_policy.md", page: "privacy",
    title: { en: "Privacy Policy", fi: "Tietosuojaseloste" },
    roles: ["CUSTOMER", "VENDOR", "COURIER"], minNoticeDays: 0, blocking: false,
    noticeRule: "No minimum, but every change is announced. Reading it is acknowledged, not consented to (GDPR Art. 13).",
  },
};

export const DOC_KEYS = Object.keys(LEGAL_DOCS) as LegalDoc[];

/** Names the apps and pages use for the same documents → document key. */
const DOC_ALIASES: Record<string, LegalDoc> = {
  terms: "terms", "terms-of-service": "terms",
  "seller-terms": "seller-terms", sellers: "seller-terms", "vendor-terms": "seller-terms",
  "courier-agreement": "courier-agreement", couriers: "courier-agreement",
  privacy: "privacy", "privacy-policy": "privacy",
};
export function docFromParam(value: unknown): LegalDoc | null {
  return typeof value === "string" && Object.prototype.hasOwnProperty.call(DOC_ALIASES, value) ? DOC_ALIASES[value] : null;
}

/** The documents a role must accept or acknowledge, in display order. Admins have none. */
export function docsForRole(role: string): LegalDoc[] {
  if (role === "CUSTOMER") return ["terms", "privacy"];
  if (role === "VENDOR") return ["seller-terms", "privacy"];
  if (role === "COURIER") return ["courier-agreement", "privacy"];
  return [];
}
/** The role's own agreement (the one /auth/register's acceptTerms covers and User.termsVersion records). */
export function mainDocForRole(role: string): LegalDoc {
  return role === "VENDOR" ? "seller-terms" : role === "COURIER" ? "courier-agreement" : "terms";
}

// The repository is deployed whole; the API runs from /backend. LEGAL_DIR points elsewhere (e.g. a test copy).
export function legalDirs() {
  return [
    ...(process.env.LEGAL_DIR ? [path.resolve(process.env.LEGAL_DIR)] : []),
    path.resolve(process.cwd(), "..", "legal"),
    path.resolve(__dirname, "..", "..", "..", "..", "legal"),
  ];
}

export function readLegalFile(file: string): string | null {
  for (const dir of legalDirs()) {
    const p = path.join(dir, file);
    if (fs.existsSync(p)) return fs.readFileSync(p, "utf8").replace(/\r/g, "");
  }
  return null;
}

/** "<file>@<first 12 hex of the SHA-256 of the text>" (carriage returns ignored), plus the full hash. */
export function versionOf(file: string, text: string) {
  const sha256 = crypto.createHash("sha256").update(text.replace(/\r/g, "")).digest("hex");
  return { version: `${file.replace(/\.md$/, "")}@${sha256.slice(0, 12)}`, sha256 };
}

/** The text currently in the repository file and its version (null when the file is missing). */
export function fileVersion(doc: LegalDoc) {
  const def = LEGAL_DOCS[doc];
  const text = readLegalFile(def.file);
  return text === null ? null : { text, ...versionOf(def.file, text) };
}

export type VersionRow = {
  id: number; doc: string; version: string; sha256: string; publishedAt: Date; effectiveAt: Date;
  summaryEn: string; summaryFi: string; noticeDays: number; legalObligation: boolean; legalObligationReason: string | null;
  publishedById: number | null; notifiedAt: Date | null; notifiedCount: number;
};
const rowSelect = {
  id: true, doc: true, version: true, sha256: true, publishedAt: true, effectiveAt: true, summaryEn: true, summaryFi: true,
  noticeDays: true, legalObligation: true, legalObligationReason: true, publishedById: true, notifiedAt: true, notifiedCount: true,
} as const;

/** Creates the first version of a document from its file, effective now. Only when the document has no version yet. */
async function ensureFirstVersion(doc: LegalDoc) {
  if ((await prisma.legalVersion.count({ where: { doc } })) > 0) return;
  const fv = fileVersion(doc);
  if (!fv) return;
  const now = new Date();
  try {
    await prisma.legalVersion.create({
      data: {
        doc, version: fv.version, textSnapshot: fv.text, sha256: fv.sha256, publishedAt: now, effectiveAt: now, noticeDays: 0,
        summaryEn: "First published version.", summaryFi: "Ensimmäinen julkaistu versio.",
      },
    });
    logger.info({ doc, version: fv.version }, "First legal version recorded");
  } catch (e: any) {
    if (e?.code !== "P2002") throw e; // another instance created it at the same moment
  }
}

/** Start-up step: the first version of every document that has none (later changes need an admin to publish them). */
export async function ensureLegalVersions() {
  for (const doc of DOC_KEYS) await ensureFirstVersion(doc);
  invalidateLegalCache();
  for (const doc of DOC_KEYS) {
    const fv = fileVersion(doc);
    const rows = await versionsOf(doc);
    if (fv && rows.length && !rows.some((v) => v.version === fv.version)) {
      logger.warn({ doc, fileVersion: fv.version, latest: rows[0].version }, "Legal text changed but is not published (the published version stays in force)");
    }
  }
}

// Version rows per document (without the text), cached for 10 s per instance; publishing clears it here at once
const CACHE_MS = 10_000;
const cache = new Map<LegalDoc, { at: number; rows: VersionRow[] }>();
export function invalidateLegalCache() {
  cache.clear();
}

/** All versions of a document, newest effective date first. */
export async function versionsOf(doc: LegalDoc): Promise<VersionRow[]> {
  const hit = cache.get(doc);
  if (hit && Date.now() - hit.at < CACHE_MS) return hit.rows;
  let rows = await prisma.legalVersion.findMany({ where: { doc }, select: rowSelect, orderBy: [{ effectiveAt: "desc" }, { id: "desc" }], take: 100 });
  if (!rows.length) {
    await ensureFirstVersion(doc);
    rows = await prisma.legalVersion.findMany({ where: { doc }, select: rowSelect, orderBy: [{ effectiveAt: "desc" }, { id: "desc" }], take: 100 });
  }
  cache.set(doc, { at: Date.now(), rows });
  return rows;
}

/** The version in force (newest whose effective time has passed) and the announced one, if any. */
export async function legalState(doc: LegalDoc, now = new Date()) {
  const rows = await versionsOf(doc);
  const current = rows.find((r) => r.effectiveAt.getTime() <= now.getTime()) ?? null;
  // The next one to take effect (earliest in the future)
  const future = rows.filter((r) => r.effectiveAt.getTime() > now.getTime());
  const pending = future.length ? future[future.length - 1] : null;
  return { current, pending, rows };
}

export function statusOf(row: VersionRow, state: { current: VersionRow | null }, now = new Date()) {
  if (row.effectiveAt.getTime() > now.getTime()) return "pending" as const;
  return state.current?.id === row.id ? ("current" as const) : ("superseded" as const);
}

/** Public URL of a document's page, or of one exact version of it. */
export function docUrl(doc: LegalDoc, version?: string) {
  const base = `${env.publicApiUrl}/legal/${LEGAL_DOCS[doc].page}`;
  return version ? `${base}/v/${encodeURIComponent(version)}` : base;
}

/** The full stored text of one version (null when unknown). */
export async function versionText(doc: LegalDoc, version: string) {
  return prisma.legalVersion.findUnique({ where: { doc_version: { doc, version } } });
}

/** Finnish time, for dates in notices and copies. */
export function formatHelsinki(d: Date, locale: "fi" | "en", withTime = false) {
  return new Intl.DateTimeFormat(locale === "fi" ? "fi-FI" : "en-GB", {
    timeZone: "Europe/Helsinki", day: "numeric", month: "long", year: "numeric",
    ...(withTime ? { hour: "2-digit", minute: "2-digit", hourCycle: "h23" as const } : {}),
  }).format(d);
}
