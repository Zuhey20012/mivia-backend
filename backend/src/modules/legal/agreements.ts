import { Router, Request, Response, NextFunction } from "express";
import crypto from "crypto";
import net from "net";
import { z } from "zod";
import { prisma } from "../../lib/prisma";
import { env } from "../../config/env";
import { auth, AuthRequest } from "../../middleware/auth";
import { ApiError, positiveId, sendError } from "../../lib/errors";
import { Locale, asLocale, localeFromHeader } from "../../lib/i18n";
import { escapeHtml, sendEmail } from "../../services/notificationDeliveryService";
import {
  LEGAL_DOCS, LegalDoc, docFromParam, docUrl, docsForRole, formatHelsinki, legalState, mainDocForRole, versionText,
} from "./legalDocs";
import { renderMarkdown, legalPageHtml, PAGE_CSP } from "./legal.routes";

/**
 * Acceptance records (since 2.11.0): a clickwrap with proof. Each acceptance stores the document, the exact version,
 * the time, the client address truncated to /24 (IPv4) or /48 (IPv6), the user agent (≤ 200 chars), the app version
 * (X-App-Version) and how it was given. The account holder gets an email copy with the full text, and can open the
 * copy at any time (owner only, or through a signed 10-minute link).
 */

export type AcceptMethod = "register" | "in_app" | "admin_import";
export type AcceptContext = { ip: string | null; userAgent: string | null; appVersion: string | null };

/** IPv4 → a.b.c.0/24, IPv6 → first three groups ::/48 (IPv4-mapped addresses count as IPv4). Anything else → null. */
export function truncateIp(raw: string | null | undefined): string | null {
  if (!raw) return null;
  let ip = raw.trim();
  if (ip.startsWith("::ffff:") && net.isIPv4(ip.slice(7))) ip = ip.slice(7);
  if (net.isIPv4(ip)) return `${ip.split(".").slice(0, 3).join(".")}.0/24`;
  if (net.isIPv6(ip)) {
    // Expand "::" so the first three groups are known
    const [head, tail] = ip.split("::");
    const h = head ? head.split(":") : [];
    const t = tail !== undefined ? (tail ? tail.split(":") : []) : [];
    const groups = tail !== undefined ? [...h, ...Array(Math.max(0, 8 - h.length - t.length)).fill("0"), ...t] : h;
    return `${groups.slice(0, 3).map((g) => (parseInt(g || "0", 16) || 0).toString(16)).join(":")}::/48`;
  }
  return null;
}

export function acceptContext(req: Request): AcceptContext {
  const ua = req.headers["user-agent"];
  const app = req.headers["x-app-version"];
  const appVersion = (Array.isArray(app) ? app[0] : app)?.replace(/[^\w.+\-() ]/g, "").trim().slice(0, 40) || null;
  return {
    ip: truncateIp(req.ip),
    userAgent: (Array.isArray(ua) ? ua[0] : ua)?.slice(0, 200) || null,
    appVersion,
  };
}

/** The versions /auth/register's acceptTerms covers for a role: its own agreement, plus the privacy notice for customers. */
export async function registrationVersions(role: string) {
  const docs: LegalDoc[] = role === "CUSTOMER" ? ["terms", "privacy"] : [mainDocForRole(role)];
  const out: { doc: LegalDoc; version: string }[] = [];
  for (const doc of docs) {
    const { current } = await legalState(doc);
    if (current) out.push({ doc, version: current.version });
  }
  return out;
}

export async function recordAcceptances(userId: number, items: { doc: LegalDoc; version: string }[], method: AcceptMethod, ctx: AcceptContext) {
  if (!items.length) return;
  await prisma.agreementAcceptance.createMany({
    data: items.map((i) => ({ userId, doc: i.doc, version: i.version, method, ip: ctx.ip, userAgent: ctx.userAgent, appVersion: ctx.appVersion })),
    skipDuplicates: true,
  });
}

/** The first blocking document whose version in force the user has not accepted, or null. */
export async function missingAgreement(userId: number, role: string) {
  for (const doc of docsForRole(role)) {
    if (!LEGAL_DOCS[doc].blocking) continue;
    const { current, pending } = await legalState(doc);
    if (!current) continue;
    const accepted = await prisma.agreementAcceptance.findUnique({
      where: { userId_doc_version: { userId, doc, version: current.version } }, select: { id: true },
    });
    if (!accepted) {
      // Changed since the user accepted an earlier version, or never accepted (e.g. accounts made by social sign-in)
      const earlier = await prisma.agreementAcceptance.findFirst({ where: { userId, doc }, select: { id: true } });
      return { doc, version: current.version, effectiveAt: current.effectiveAt, pendingVersion: pending?.version ?? null, changed: !!earlier };
    }
  }
  return null;
}

/**
 * Refuses a role-critical action with 428 AGREEMENT_REQUIRED until the user has accepted the version in force of their
 * agreement: a store accepting orders or publishing products, a courier going online or taking jobs, a customer
 * placing an order. `when` limits it to the requests that are such an action. Reading, support, payouts, data export
 * and account deletion never pass through it.
 */
export function requireAgreement(when?: (req: AuthRequest) => boolean) {
  return async (req: AuthRequest, res: Response, next: NextFunction) => {
    if (!req.user || req.user.role === "ADMIN" || (when && !when(req))) return next();
    try {
      const missing = await missingAgreement(req.user.id, req.user.role);
      if (!missing) return next();
      const def = LEGAL_DOCS[missing.doc];
      const fi = localeFromHeader(req.headers["accept-language"]) === "fi";
      res.status(428).json({
        ok: false,
        error: missing.changed
          ? (fi
            ? `${def.title.fi}: uusi versio on tullut voimaan. Lue ja hyväksy se jatkaaksesi.`
            : `The ${def.title.en} ${/Terms/.test(def.title.en) ? "have" : "has"} changed. Please read and accept the new version to continue.`)
          : (fi
            ? `Lue ja hyväksy ${def.title.fi.toLowerCase()} jatkaaksesi.`
            : `Please read and accept the ${def.title.en} to continue.`),
        code: "AGREEMENT_REQUIRED",
        doc: missing.doc,
        version: missing.version,
        title: def.title,
        url: docUrl(missing.doc, missing.version),
      });
    } catch (e) { sendError(res, e); }
  };
}

// ─── Copies ──────────────────────────────────────────────────────────────────

type AcceptanceRow = { id: number; userId: number; doc: string; version: string; acceptedAt: Date; ip: string | null; userAgent: string | null; appVersion: string | null; method: string };

const METHOD_TEXT: Record<string, { en: string; fi: string }> = {
  register: { en: "when creating the account", fi: "tiliä luotaessa" },
  in_app: { en: "in the app", fi: "sovelluksessa" },
  admin_import: { en: "recorded by Malvoya from earlier records", fi: "Malvoyan aiemmista tiedoista kirjattu" },
};

/** The copy of an accepted agreement: who, what version, when, how, then the full text of that version. */
async function renderCopy(a: AcceptanceRow, locale: Locale) {
  const doc = docFromParam(a.doc) as LegalDoc;
  const def = LEGAL_DOCS[doc];
  const [user, row] = await Promise.all([
    prisma.user.findUnique({ where: { id: a.userId }, select: { name: true, email: true, phone: true } }),
    versionText(doc, a.version),
  ]);
  const fi = locale === "fi";
  const account = user ? `${user.name} (${user.email.endsWith("@phone.malvoya.app") ? user.phone ?? user.email : user.email})` : `#${a.userId}`;
  const when = `${formatHelsinki(a.acceptedAt, locale, true)} (${fi ? "Suomen aikaa" : "Finnish time"}; ${a.acceptedAt.toISOString()})`;
  const facts: [string, string][] = [
    [fi ? "Asiakirja" : "Document", fi ? def.title.fi : def.title.en],
    [fi ? "Versio" : "Version", a.version],
    [fi ? "Hyväksytty" : "Accepted", when],
    [fi ? "Tili" : "Account", account],
    [fi ? "Tapa" : "How", (METHOD_TEXT[a.method] ?? METHOD_TEXT.in_app)[locale]],
    ...(a.ip ? [[fi ? "Osoite (lyhennetty)" : "Network address (truncated)", a.ip] as [string, string]] : []),
    ...(a.appVersion ? [[fi ? "Sovellusversio" : "App version", a.appVersion] as [string, string]] : []),
  ];
  const head = `<h1>${escapeHtml(fi ? `Kopio: ${def.title.fi}` : `Your copy: ${def.title.en}`)}</h1>
<table><tbody>${facts.map(([k, v]) => `<tr><th>${escapeHtml(k)}</th><td>${escapeHtml(v)}</td></tr>`).join("")}</tbody></table>
<p>${escapeHtml(fi
    ? "Tämä on kopio hyväksymästäsi tekstistä juuri siinä muodossa kuin se oli. Voimassa oleva versio:"
    : "This is a copy of the text you accepted, exactly as it was. The version in force is always at:")} <a href="${escapeHtml(docUrl(doc))}">${escapeHtml(docUrl(doc))}</a></p><hr>`;
  const text = row
    ? renderMarkdown(row.textSnapshot)
    : `<p>${escapeHtml(fi
      ? "Tämä versio hyväksyttiin ennen kuin tekstien versioita tallennettiin, joten sen tekstiä ei ole tallessa; versiotunnus yksilöi tekstin."
      : "This version was accepted before Malvoya stored the text of each version, so its text is not on file; the version identifier identifies the text.")}</p>`;
  return {
    title: fi ? `Kopio: ${def.title.fi}` : `Your copy: ${def.title.en}`,
    body: head + text,
    plain: [
      ...facts.map(([k, v]) => `${k}: ${v}`),
      "",
      row ? row.textSnapshot : "",
      "",
      docUrl(doc),
    ].join("\n"),
    email: user?.email ?? null,
  };
}

async function emailCopy(a: AcceptanceRow) {
  const user = await prisma.user.findUnique({ where: { id: a.userId }, select: { locale: true } });
  const locale = asLocale(user?.locale);
  const copy = await renderCopy(a, locale);
  if (!copy.email) return false;
  const html = `<div style="font-family:-apple-system,system-ui,'Segoe UI',sans-serif;max-width:720px;margin:0 auto;color:#17131C;line-height:1.55">${copy.body}</div>`;
  // `sensitive` keeps the long text out of development logs (it is not secret)
  const r = await sendEmail(copy.email, `Malvoya – ${copy.title}`, html, copy.plain, { sensitive: true });
  return r.delivered;
}

// Signed 10-minute links to a copy (same scheme as statement links, own label)
export const COPY_LINK_TTL_SECONDS = 10 * 60;
const linkKey = crypto
  .createHmac("sha256", process.env.STATEMENT_LINK_SECRET || env.jwtSecret)
  .update("malvoya:agreement-copy-link:v1")
  .digest();
function signCopy(id: number, exp: number) {
  return crypto.createHmac("sha256", linkKey).update(`agreement-copy|${id}|${exp}`).digest("base64url");
}
function checkCopyLink(id: number, expRaw: unknown, sigRaw: unknown): "ok" | "expired" | "invalid" {
  const exp = Number(expRaw);
  if (typeof sigRaw !== "string" || !Number.isInteger(exp)) return "invalid";
  const expected = Buffer.from(signCopy(id, exp));
  const given = Buffer.from(sigRaw);
  if (given.length !== expected.length || !crypto.timingSafeEqual(given, expected)) return "invalid";
  return exp * 1000 < Date.now() ? "expired" : "ok";
}

function presentAcceptance(a: AcceptanceRow) {
  const doc = docFromParam(a.doc);
  return {
    id: a.id, doc: a.doc, version: a.version, acceptedAt: a.acceptedAt, method: a.method,
    title: doc ? LEGAL_DOCS[doc].title : null,
    url: doc ? docUrl(doc, a.version) : null,
    copyUrl: `${env.publicApiUrl}/api/v1/me/agreements/${a.id}/copy`,
  };
}

/** What the user must accept or acknowledge and what they accepted (GET /me/agreements). */
export async function agreementsFor(userId: number, role: string) {
  const now = new Date();
  const history = await prisma.agreementAcceptance.findMany({ where: { userId }, orderBy: { acceptedAt: "desc" }, take: 100 });
  const required = [];
  for (const doc of docsForRole(role)) {
    const def = LEGAL_DOCS[doc];
    const { current, pending } = await legalState(doc, now);
    if (!current) continue;
    const acc = history.find((h) => h.doc === doc && h.version === current.version);
    const pendingAcc = pending ? history.find((h) => h.doc === doc && h.version === pending.version) : undefined;
    required.push({
      doc,
      title: def.title,
      blocking: def.blocking,
      currentVersion: current.version,
      effectiveAt: current.effectiveAt,
      accepted: !!acc,
      acceptedAt: acc?.acceptedAt ?? null,
      url: docUrl(doc, current.version),
      ...(pending ? {
        pendingVersion: pending.version,
        pendingEffectiveAt: pending.effectiveAt,
        pendingAccepted: !!pendingAcc,
        pendingUrl: docUrl(doc, pending.version),
        summary: { en: pending.summaryEn, fi: pending.summaryFi },
        // Sellers may end the agreement before a change takes effect (P2B Art. 3(2))
        ...(doc === "seller-terms" ? { canTerminateBefore: pending.effectiveAt } : {}),
      } : {}),
    });
  }
  return { required, history: history.map(presentAcceptance) };
}

// ─── Routes (mounted under /api/v1 through me.routes) ────────────────────────

export const agreementRoutes = Router();

agreementRoutes.get("/me/agreements", auth, async (req: AuthRequest, res: Response) => {
  try {
    res.json({ ok: true, ...(await agreementsFor(req.user!.id, req.user!.role)) });
  } catch (e) { sendError(res, e); }
});

const acceptSchema = z.object({ doc: z.string().min(1).max(40), version: z.string().min(3).max(120) });

/**
 * Accepts the version in force or the announced one of one of the user's documents. Idempotent: accepting again
 * returns the same record (alreadyAccepted: true) and sends no second email. The first acceptance emails a copy.
 */
agreementRoutes.post("/me/agreements/accept", auth, async (req: AuthRequest, res: Response) => {
  const body = acceptSchema.safeParse(req.body);
  if (!body.success) return res.status(400).json({ ok: false, error: "doc and version are required" });
  try {
    const doc = docFromParam(body.data.doc);
    if (!doc || !docsForRole(req.user!.role).includes(doc)) throw new ApiError("This document is not one your account accepts", 400);
    const { current, pending } = await legalState(doc);
    const version = body.data.version;
    if (version !== current?.version && version !== pending?.version) {
      return res.status(409).json({
        ok: false, error: "That is not the current or the announced version of this document. Reload and try again.",
        currentVersion: current?.version ?? null, pendingVersion: pending?.version ?? null,
      });
    }
    const userId = req.user!.id;
    let row = await prisma.agreementAcceptance.findUnique({ where: { userId_doc_version: { userId, doc, version } } });
    let created = false;
    if (!row) {
      const ctx = acceptContext(req);
      try {
        row = await prisma.agreementAcceptance.create({
          data: { userId, doc, version, method: "in_app", ip: ctx.ip, userAgent: ctx.userAgent, appVersion: ctx.appVersion },
        });
        created = true;
      } catch (e: any) {
        if (e?.code !== "P2002") throw e;
        row = await prisma.agreementAcceptance.findUniqueOrThrow({ where: { userId_doc_version: { userId, doc, version } } });
      }
      // The account's own agreement: GET /me and sessions show the latest accepted version
      if (created && doc === mainDocForRole(req.user!.role)) {
        await prisma.user.update({ where: { id: userId }, data: { termsAcceptedAt: row.acceptedAt, termsVersion: version } });
      }
    }
    const emailed = created ? await emailCopy(row).catch(() => false) : false;
    if (created) {
      // Onboarding: the agreement step may have been the last one before approval
      const { checkReadyForApproval } = await import("../onboarding/onboarding");
      checkReadyForApproval(userId, req.user!.role).catch(() => {});
    }
    res.status(created ? 201 : 200).json({ ok: true, acceptance: presentAcceptance(row), alreadyAccepted: !created, emailed });
  } catch (e) { sendError(res, e); }
});

async function ownAcceptance(req: AuthRequest) {
  const id = positiveId(req.params.id);
  const row = id ? await prisma.agreementAcceptance.findUnique({ where: { id } }) : null;
  // Someone else's record is "not found", never "forbidden"
  if (!row || row.userId !== req.user!.id) throw new ApiError("Agreement copy not found", 404);
  return row;
}

function sendCopyPage(res: Response, copy: { title: string; body: string }) {
  res.set("Cache-Control", "private, no-store");
  res.set("Content-Security-Policy", PAGE_CSP);
  res.set("X-Robots-Tag", "noindex");
  res.type("html").send(legalPageHtml(copy.title, copy.body));
}

/** The copy as a page (owner only, with the bearer token). */
agreementRoutes.get("/me/agreements/:id(\\d+)/copy", auth, async (req: AuthRequest, res: Response) => {
  try {
    const row = await ownAcceptance(req);
    const locale = localeFromHeader(req.headers["accept-language"]) ?? asLocale((await prisma.user.findUnique({ where: { id: row.userId }, select: { locale: true } }))?.locale);
    sendCopyPage(res, await renderCopy(row, locale));
  } catch (e) { sendError(res, e); }
});

/** A 10-minute link that opens the copy in a normal browser (no token there). */
agreementRoutes.get("/me/agreements/:id(\\d+)/copy/link", auth, async (req: AuthRequest, res: Response) => {
  try {
    const row = await ownAcceptance(req);
    const exp = Math.floor(Date.now() / 1000) + COPY_LINK_TTL_SECONDS;
    res.json({
      ok: true,
      url: `${env.publicApiUrl}/api/v1/agreements/copy/${row.id}.html?exp=${exp}&sig=${signCopy(row.id, exp)}`,
      expiresAt: new Date(exp * 1000),
    });
  } catch (e) { sendError(res, e); }
});

agreementRoutes.get("/agreements/copy/:id(\\d+).html", async (req: Request, res: Response) => {
  const id = Number(req.params.id);
  const check = checkCopyLink(id, req.query.exp, req.query.sig);
  if (check !== "ok") {
    return res.status(403).type("text").send(check === "expired" ? "This link has expired. Open the copy again from the app." : "Invalid link");
  }
  try {
    const row = await prisma.agreementAcceptance.findUnique({ where: { id } });
    if (!row) return res.status(404).type("text").send("Not found");
    const u = await prisma.user.findUnique({ where: { id: row.userId }, select: { locale: true } });
    sendCopyPage(res, await renderCopy(row, asLocale(u?.locale)));
  } catch (e) { sendError(res, e); }
});
