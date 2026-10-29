import { Router, Response } from "express";
import pino from "pino";
import { prisma } from "../../lib/prisma";
import { auth, AuthRequest } from "../../middleware/auth";
import { positiveId, sendError } from "../../lib/errors";
import { Text, localeOfUser, pick, t } from "../../lib/i18n";
import { pushToUser } from "../../lib/push";
import { sendNoticeEmail } from "../../services/notificationDeliveryService";

const logger = pino({ name: "notices" });

/**
 * In-app notices (since 2.16.0), also emailed:
 *  - statements of reasons (DSA Art. 17) to the author when moderation hides or removes a comment, review or live chat
 *    message: what was decided, why, that it was automatic or a person, and how to object;
 *  - the outcome of a report (DSA Art. 16(5)) to everyone who reported the content.
 */
export type ContentKind = "comment" | "review" | "live_message" | "drop" | "product" | "live";

const KIND_TEXT: Record<ContentKind, Text> = {
  comment: t("comment", "kommentti"),
  review: t("review", "arvio"),
  live_message: t("live chat message", "livechat-viesti"),
  drop: t("drop", "drop"),
  product: t("product listing", "tuoteilmoitus"),
  live: t("live stream", "livelähetys"),
};
const ENTITY: Record<ContentKind, string> = {
  comment: "DropComment", review: "Review", live_message: "LiveMessage", drop: "Drop", product: "Product", live: "LiveStream",
};

const OBJECT = t(
  "If you think this is wrong, reply through Support in the app or the contact form (malvoya → Contact) within 6 months and a person will look at it again. You can also use an out-of-court dispute settlement body or go to court.",
  "Jos päätös on mielestäsi väärä, ota yhteyttä sovelluksen Tuki-osion tai yhteydenottolomakkeen kautta 6 kuukauden kuluessa, niin ihminen tarkistaa asian uudelleen. Voit myös kääntyä tuomioistuimen ulkopuolisen riidanratkaisuelimen tai tuomioistuimen puoleen.",
);

async function deliver(userId: number, kind: string, title: Text, body: Text, entity: string | null, entityId: number | null) {
  try {
    const notice = await prisma.userNotice.create({
      data: { userId, kind, titleEn: pick(title, "en"), titleFi: pick(title, "fi"), bodyEn: pick(body, "en"), bodyFi: pick(body, "fi"), entity, entityId },
    });
    const user = await prisma.user.findUnique({ where: { id: userId }, select: { email: true, isActive: true } });
    if (user?.isActive) {
      const locale = await localeOfUser(userId);
      sendNoticeEmail(user.email, pick(title, locale), pick(body, locale).split("\n\n"), locale).catch(() => {});
      pushToUser(userId, { title, body: pick(title, "en") === pick(body, "en") ? body : body, data: { type: "notice", noticeId: String(notice.id) } }).catch(() => {});
    }
    return notice;
  } catch (e: any) {
    logger.error({ err: e?.message, kind }, "Notice not stored");
    return null;
  }
}

/**
 * Statement of reasons to the author. `automatic`: hidden by the three-report rule (no person has looked yet).
 * `excerpt`: the start of the content, so the author knows which one.
 */
export async function statementOfReasons(input: {
  userId: number; kind: ContentKind; entityId: number; excerpt?: string | null; decision: "hidden" | "removed";
  reason: string; automatic: boolean;
}) {
  const what = KIND_TEXT[input.kind];
  const excerpt = input.excerpt ? `“${input.excerpt.slice(0, 80)}${input.excerpt.length > 80 ? "…" : ""}”` : "";
  const decision = input.decision === "hidden" ? t("hidden", "piilotettu") : t("removed", "poistettu");
  const title = t(`Your ${pick(what, "en")} was ${pick(decision, "en")}`, `${cap(pick(what, "fi"))}si on ${pick(decision, "fi")}`);
  const how = input.automatic
    ? t("This was done automatically because three different users reported it. A person on the Malvoya team will review it and you will hear the outcome.",
      "Tämä tehtiin automaattisesti, koska kolme eri käyttäjää ilmoitti siitä. Malvoyan tiimin jäsen tarkistaa asian, ja kerromme sinulle lopputuloksen.")
    : t("This decision was made by a person on the Malvoya team after review.", "Päätöksen teki Malvoyan tiimin jäsen tarkistuksen jälkeen.");
  const body = t(
    [excerpt, `Reason: ${input.reason}`, pick(how, "en"), "It breaks Malvoya's content rules (Terms of Service, “Content rules”).", pick(OBJECT, "en")].filter(Boolean).join("\n\n"),
    [excerpt, `Syy: ${input.reason}`, pick(how, "fi"), "Se rikkoo Malvoyan sisältösääntöjä (käyttöehdot, ”Sisältösäännöt”).", pick(OBJECT, "fi")].filter(Boolean).join("\n\n"),
  );
  return deliver(input.userId, "statement_of_reasons", title, body, ENTITY[input.kind], input.entityId);
}

/** The outcome of a report, to each person who reported the content (signed-in reporters). */
export async function reportOutcome(reporterIds: (number | null | undefined)[], kind: ContentKind, entityId: number, outcome: "actioned" | "kept") {
  const ids = [...new Set(reporterIds.filter((x): x is number => typeof x === "number"))].slice(0, 500);
  const what = KIND_TEXT[kind];
  const title = t("We looked at your report", "Tarkistimme ilmoituksesi");
  const body = outcome === "actioned"
    ? t(`Thank you. The ${pick(what, "en")} you reported was removed or hidden because it breaks Malvoya's rules.`,
      `Kiitos. Ilmoittamasi ${pick(what, "fi")} poistettiin tai piilotettiin, koska se rikkoo Malvoyan sääntöjä.`)
    : t(`Thank you. We reviewed the ${pick(what, "en")} you reported and decided to keep it: we did not find that it breaks Malvoya's rules or the law. If you disagree, contact us through Support.`,
      `Kiitos. Tarkistimme ilmoittamasi sisällön (${pick(what, "fi")}) ja päätimme pitää sen: emme havainneet sen rikkovan Malvoyan sääntöjä tai lakia. Jos olet eri mieltä, ota yhteyttä Tuki-osion kautta.`);
  for (const id of ids) await deliver(id, "report_outcome", title, body, ENTITY[kind], entityId);
  return ids.length;
}

const cap = (s: string) => (s ? s[0].toUpperCase() + s.slice(1) : s);

// ─── Routes ─────────────────────────────────────────────────────────────────

export const noticeRoutes = Router();

/** GET /me/notices?before=<id> → { notices: [{id, kind, title{en,fi}, body{en,fi}, entity, entityId, readAt, createdAt}], unread, nextBefore } */
noticeRoutes.get("/me/notices", auth, async (req: AuthRequest, res: Response) => {
  const before = req.query.before !== undefined ? positiveId(req.query.before) : null;
  try {
    const [rows, unread] = await Promise.all([
      prisma.userNotice.findMany({
        where: { userId: req.user!.id, ...(before ? { id: { lt: before } } : {}) },
        orderBy: { id: "desc" },
        take: 30,
      }),
      prisma.userNotice.count({ where: { userId: req.user!.id, readAt: null } }),
    ]);
    res.json({
      ok: true,
      unread,
      notices: rows.map((n) => ({
        id: n.id, kind: n.kind, title: { en: n.titleEn, fi: n.titleFi }, body: { en: n.bodyEn, fi: n.bodyFi },
        entity: n.entity, entityId: n.entityId, readAt: n.readAt, createdAt: n.createdAt,
      })),
      nextBefore: rows.length === 30 ? rows[rows.length - 1].id : null,
    });
  } catch (e) { sendError(res, e); }
});

noticeRoutes.post("/me/notices/read", auth, async (req: AuthRequest, res: Response) => {
  try {
    const ids = Array.isArray(req.body?.ids) ? req.body.ids.map(positiveId).filter((x: number | null): x is number => !!x).slice(0, 200) : null;
    const r = await prisma.userNotice.updateMany({ where: { userId: req.user!.id, readAt: null, ...(ids ? { id: { in: ids } } : {}) }, data: { readAt: new Date() } });
    res.json({ ok: true, marked: r.count });
  } catch (e) { sendError(res, e); }
});
