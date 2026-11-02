import { Router, Request, Response } from "express";
import { z } from "zod";
import pino from "pino";
import { prisma } from "../../lib/prisma";
import { AuthRequest } from "../../middleware/auth";
import { ApiError, positiveId, sendError } from "../../lib/errors";
import { asLocale, Locale } from "../../lib/i18n";
import { pushToUsers } from "../../lib/push";
import { escapeHtml, sendEmail } from "../../services/notificationDeliveryService";
import { env } from "../../config/env";
import {
  DOC_KEYS, LEGAL_DOCS, LegalDoc, docFromParam, docUrl, fileVersion, formatHelsinki, invalidateLegalCache, legalState, statusOf,
} from "./legalDocs";

const logger = pino({ name: "legal" });
const DAY_MS = 86_400_000;

/**
 * Admin side of the legal texts (since 2.11.0): every document with its versions, acceptance counts, whether the file
 * in the repository holds an unpublished change, and publishing that change with a notice period.
 */
export const adminLegalRoutes = Router();

async function acceptanceCounts() {
  const rows = await prisma.agreementAcceptance.groupBy({ by: ["doc", "version"], _count: { _all: true } });
  return new Map(rows.map((r) => [`${r.doc}|${r.version}`, r._count._all]));
}

function affectedWhere(doc: LegalDoc) {
  return { role: { in: LEGAL_DOCS[doc].roles }, isActive: true, deletedAt: null };
}

/** Documents whose repository text differs from every published version (shown in System → attention). */
export async function unpublishedLegalChanges() {
  const out: { doc: LegalDoc; fileVersion: string }[] = [];
  for (const doc of DOC_KEYS) {
    const fv = fileVersion(doc);
    const { rows } = await legalState(doc);
    if (fv && rows.length && !rows.some((r) => r.version === fv.version)) out.push({ doc, fileVersion: fv.version });
  }
  return out;
}

adminLegalRoutes.get("/legal", async (_req: Request, res: Response) => {
  try {
    const now = new Date();
    const counts = await acceptanceCounts();
    const docs = [];
    for (const doc of DOC_KEYS) {
      const def = LEGAL_DOCS[doc];
      const state = await legalState(doc, now);
      const fv = fileVersion(doc);
      const affectedUsers = await prisma.user.count({ where: affectedWhere(doc) });
      docs.push({
        doc,
        title: def.title,
        file: def.file,
        url: docUrl(doc),
        minNoticeDays: def.minNoticeDays,
        noticeRule: def.noticeRule,
        blocking: def.blocking,
        roles: def.roles,
        affectedUsers,
        currentVersion: state.current?.version ?? null,
        pendingVersion: state.pending?.version ?? null,
        fileVersion: fv?.version ?? null,
        // The repository text is a new version nobody has published yet: the published one stays in force
        unpublishedChange: !!fv && !state.rows.some((r) => r.version === fv.version),
        versions: state.rows.map((r) => ({
          ...r,
          status: statusOf(r, state, now),
          acceptances: counts.get(`${doc}|${r.version}`) ?? 0,
          url: docUrl(doc, r.version),
        })),
        // Acceptances recorded for versions from before 2.11 (no stored text), e.g. at registration
        legacyAcceptances: [...counts.entries()]
          .filter(([k]) => k.startsWith(`${doc}|`) && !state.rows.some((r) => `${doc}|${r.version}` === k))
          .map(([k, n]) => ({ version: k.slice(doc.length + 1), acceptances: n })),
      });
    }
    res.json({ ok: true, docs });
  } catch (e) { sendError(res, e); }
});

const publishSchema = z.object({
  effectiveAt: z.coerce.date(),
  summaryEn: z.string().trim().min(10, "Write a summary of the change in English (at least 10 characters)").max(1000),
  summaryFi: z.string().trim().min(10, "Kirjoita muutoksen tiivistelmä suomeksi (vähintään 10 merkkiä)").max(1000),
  legalObligation: z.boolean().optional(),
  reason: z.string().trim().max(500).optional(),
}).refine((d) => !d.legalObligation || (d.reason?.length ?? 0) >= 10, {
  message: "Say which law requires the change (at least 10 characters)", path: ["reason"],
});

/**
 * Publishes the document's current repository text as a new version that takes effect at `effectiveAt`.
 * Notice: seller terms ≥ 15 days (P2B Art. 3), courier agreement ≥ 15 days (policy), customer terms and privacy ≥ 0,
 * unless `legalObligation` (the law requires the change; the reason is audited). Everyone the document binds is
 * told by push and email in their language.
 */
adminLegalRoutes.post("/legal/:doc/publish", async (req: AuthRequest, res: Response) => {
  const doc = docFromParam(req.params.doc);
  if (!doc) return res.status(404).json({ ok: false, error: "Unknown document" });
  const body = publishSchema.safeParse(req.body);
  if (!body.success) return res.status(400).json({ ok: false, error: body.error.issues[0]?.message ?? "Invalid request", errors: body.error.flatten() });
  try {
    const def = LEGAL_DOCS[doc];
    const now = new Date();
    const { effectiveAt, summaryEn, summaryFi } = body.data;
    const legalObligation = body.data.legalObligation === true;
    // "Now" may be a few seconds old by the time it arrives
    if (effectiveAt.getTime() < now.getTime() - 5 * 60_000) throw new ApiError("The effective date cannot be in the past", 400);
    const effective = effectiveAt.getTime() < now.getTime() ? now : effectiveAt;
    const noticeMs = effective.getTime() - now.getTime();
    const minMs = def.minNoticeDays * DAY_MS;
    if (!legalObligation && noticeMs < minMs - 60_000) {
      return res.status(400).json({
        ok: false,
        error: `${def.title.en}: changes need at least ${def.minNoticeDays} days' notice. ${def.noticeRule}`,
        code: "NOTICE_TOO_SHORT",
        minNoticeDays: def.minNoticeDays,
        earliestEffectiveAt: new Date(now.getTime() + minMs),
      });
    }
    const fv = fileVersion(doc);
    if (!fv) throw new ApiError("The document's file is missing on the server", 404);
    const state = await legalState(doc, now);
    if (state.rows.some((r) => r.version === fv.version)) {
      return res.status(409).json({ ok: false, error: `This text is already published (version ${fv.version}). Change the file in the repository and deploy first.` });
    }
    if (state.pending) {
      return res.status(409).json({ ok: false, error: `A change is already announced (version ${state.pending.version}, effective ${state.pending.effectiveAt.toISOString()}). Wait until it takes effect.` });
    }
    const noticeDays = Math.floor(noticeMs / DAY_MS);
    const reason = legalObligation ? body.data.reason! : null;
    const [row] = await prisma.$transaction([
      prisma.legalVersion.create({
        data: {
          doc, version: fv.version, textSnapshot: fv.text, sha256: fv.sha256, publishedAt: now, effectiveAt: effective,
          summaryEn, summaryFi, noticeDays, legalObligation, legalObligationReason: reason, publishedById: req.user!.id,
        },
        select: { id: true, doc: true, version: true, publishedAt: true, effectiveAt: true, noticeDays: true, legalObligation: true, legalObligationReason: true },
      }),
    ]);
    await prisma.adminAuditLog.create({
      data: {
        adminId: req.user!.id, action: legalObligation ? "legal.publish.legal_obligation" : "legal.publish", entity: "LegalVersion", entityId: row.id,
        oldValue: state.current ? { version: state.current.version } : undefined,
        newValue: { doc, version: row.version, effectiveAt: row.effectiveAt.toISOString(), noticeDays, legalObligation, reason },
      },
    });
    invalidateLegalCache();
    const affectedUsers = await prisma.user.count({ where: affectedWhere(doc) });
    // Notices go out after the answer; progress is stored on the version (notifiedAt, notifiedCount)
    notifyLegalChange(row.id).catch((e) => logger.error({ err: e?.message, versionId: row.id }, "Legal change notices failed"));
    res.status(201).json({ ok: true, version: { ...row, url: docUrl(doc, row.version) }, notifying: affectedUsers });
  } catch (e) { sendError(res, e); }
});

/** A user's acceptance history (admin panel → user detail). */
adminLegalRoutes.get("/users/:id(\\d+)/agreements", async (req: Request, res: Response) => {
  const id = positiveId(req.params.id);
  if (!id) return res.status(404).json({ ok: false, error: "User not found" });
  try {
    const user = await prisma.user.findUnique({ where: { id }, select: { id: true, name: true, email: true, role: true, termsAcceptedAt: true, termsVersion: true } });
    if (!user) return res.status(404).json({ ok: false, error: "User not found" });
    const acceptances = await prisma.agreementAcceptance.findMany({ where: { userId: id }, orderBy: { acceptedAt: "desc" }, take: 200 });
    res.json({ ok: true, user, acceptances });
  } catch (e) { sendError(res, e); }
});

// ─── Change notices ──────────────────────────────────────────────────────────

function noticeTexts(doc: LegalDoc, v: { version: string; effectiveAt: Date; summaryEn: string; summaryFi: string; legalObligation: boolean }, locale: Locale) {
  const def = LEGAL_DOCS[doc];
  const fi = locale === "fi";
  const date = formatHelsinki(v.effectiveAt, locale);
  const now = v.effectiveAt.getTime() <= Date.now() + 60_000;
  const title = fi ? `${def.title.fi} muuttuvat` : `Changes to the ${def.title.en}`;
  const when = fi ? (now ? "Muutos on voimassa heti." : `Muutos tulee voimaan ${date}.`) : (now ? "The change is in effect now." : `The change takes effect on ${date}.`);
  const law = v.legalObligation ? (fi ? "Muutos johtuu lainsäädännöstä." : "The change is required by law.") : "";
  const terminate = doc === "seller-terms"
    ? (fi
      ? "Jos et hyväksy muutosta, voit päättää sopimuksen ennen sen voimaantuloa sulkemalla kauppasi (Kauppa-sovellus → Tili → Poista tili) tai ottamalla yhteyttä tukeen."
      : "If you do not agree, you may end your agreement before the change takes effect by closing your store (store app → Account → Delete account) or by contacting support.")
    : doc === "courier-agreement"
      ? (fi ? "Voit lopettaa milloin tahansa." : "You may stop at any time.")
      : doc === "terms"
        ? (fi ? "Jos et hyväksy muutosta, voit poistaa tilisi milloin tahansa." : "If you do not agree, you can delete your account at any time.")
        : "";
  const summary = fi ? v.summaryFi : v.summaryEn;
  return { title, when, law, terminate, summary, url: docUrl(doc, v.version), allUrl: `${env.publicApiUrl}/legal/${def.page}/versions` };
}

/** Push + email (in each user's language) to everyone the document binds. Batches of 500 users. */
export async function notifyLegalChange(versionId: number) {
  const v = await prisma.legalVersion.findUnique({ where: { id: versionId }, select: { id: true, doc: true, version: true, effectiveAt: true, summaryEn: true, summaryFi: true, legalObligation: true, notifiedAt: true } });
  if (!v || v.notifiedAt) return 0;
  const doc = docFromParam(v.doc);
  if (!doc) return 0;
  // Claim the version first, so two instances never send the same notices twice
  const claim = await prisma.legalVersion.updateMany({ where: { id: v.id, notifiedAt: null }, data: { notifiedAt: new Date() } });
  if (!claim.count) return 0;
  const textEn = noticeTexts(doc, v, "en");
  const textFi = noticeTexts(doc, v, "fi");
  let sent = 0;
  let cursor = 0;
  for (;;) {
    const users = await prisma.user.findMany({
      where: { ...affectedWhere(doc), id: { gt: cursor } },
      select: { id: true, email: true, locale: true },
      orderBy: { id: "asc" },
      take: 500,
    });
    if (!users.length) break;
    cursor = users[users.length - 1].id;
    await pushToUsers(users.map((u) => u.id), {
      title: { en: textEn.title, fi: textFi.title },
      body: { en: `${textEn.when} ${textEn.summary}`, fi: `${textFi.when} ${textFi.summary}` },
      data: { type: "legal", doc, version: v.version },
    }).catch(() => {});
    for (const u of users) {
      const x = asLocale(u.locale) === "fi" ? textFi : textEn;
      const fi = asLocale(u.locale) === "fi";
      const html = `<div style="font-family:-apple-system,system-ui,'Segoe UI',sans-serif;max-width:600px;color:#17131C;line-height:1.55">
<h2>${escapeHtml(x.title)}</h2>
<p><strong>${escapeHtml(x.when)}</strong> ${escapeHtml(x.law)}</p>
<p>${escapeHtml(x.summary)}</p>
<p><a href="${escapeHtml(x.url)}">${escapeHtml(fi ? "Lue koko uusi teksti" : "Read the full new text")}</a> · <a href="${escapeHtml(x.allUrl)}">${escapeHtml(fi ? "Kaikki versiot" : "All versions")}</a></p>
${x.terminate ? `<p>${escapeHtml(x.terminate)}</p>` : ""}
<p style="color:#5b5363;font-size:13px">${escapeHtml(fi ? "Sovellus pyytää sinua hyväksymään uuden version." : "The app will ask you to accept the new version.")}</p></div>`;
      const plain = [x.title, "", `${x.when} ${x.law}`.trim(), "", x.summary, "", x.url, x.terminate].filter((l) => l !== undefined).join("\n");
      const r = await sendEmail(u.email, `Malvoya – ${x.title}`, html, plain, { kind: "legal", locale: fi ? "fi" : "en" }).catch(() => ({ delivered: false }));
      if (r.delivered) sent++;
    }
  }
  await prisma.legalVersion.update({ where: { id: v.id }, data: { notifiedCount: sent } });
  logger.info({ doc, version: v.version, emailed: sent }, "Legal change notices sent");
  return sent;
}
