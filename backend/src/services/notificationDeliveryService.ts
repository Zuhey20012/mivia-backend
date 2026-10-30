import nodemailer from "nodemailer";
import pino from "pino";
import { env } from "../config/env";
import { formatCents } from "../utils/pricing";
import { Locale, Text, localeOfEmail, pick, t } from "../lib/i18n";
import { defineJob, enqueue, queueIsRemote } from "../lib/queue";
import { prisma } from "../lib/prisma";
import { unsubscribeHeaders, unsubscribeUrl } from "../lib/unsubscribe";

const logger = pino({ name: "Notifications" });

export interface DeliveryResult {
  delivered: boolean;
  /** true when no provider is configured and we are outside production (dev convenience) */
  simulated?: boolean;
  /** true when the email was handed to the background queue (REDIS_URL set); it is sent with retries */
  queued?: boolean;
  /** An optional email was not sent because the account switched optional emails off */
  skipped?: "opted_out";
}

// ─── Which emails are which (2.16.0) ────────────────────────────────────────
//
// Transactional (always sent; each carries a one-line footer saying why it was sent):
//   account  – sign-in and password-reset codes, "no password needed", two-step sign-in notices
//   order    – order confirmation, status and cancellation emails, withdrawal acknowledgements
//   legal    – agreement copies, legal-text change notices (P2B / Terms changes)
//   recall   – product-safety recall notices to buyers and the store
//   seller   – store/courier approval, DAC7 tax-detail reminders, statements of reasons (drop, live, listing removed),
//              payout matters
//   support  – "we got your message"
//   report   – the outcome of a notice the person sent (DSA Art. 16(5))
//   internal – messages to the Malvoya team only (support inbox, admins); no footer
// Optional (sendOptionalEmail: unsubscribe link in the footer, List-Unsubscribe + List-Unsubscribe-Post headers,
// never sent once User.emailMarketingOptOutAt is set):
//   launch alerts ("Malvoya is open near you"); any future referral, promo or newsletter email must use it too.
export type EmailKind = "account" | "order" | "legal" | "recall" | "seller" | "support" | "report" | "internal";

const WHY: Record<Exclude<EmailKind, "internal">, Text> = {
  account: t("You received this service message because it concerns the security of your Malvoya account.",
    "Saat tämän palveluviestin, koska se koskee Malvoya-tilisi turvallisuutta."),
  order: t("You received this service message because it concerns an order you placed on Malvoya.",
    "Saat tämän palveluviestin, koska se koskee Malvoyassa tekemääsi tilausta."),
  legal: t("You received this service message because it concerns an agreement between you and Malvoya.",
    "Saat tämän palveluviestin, koska se koskee sinun ja Malvoyan välistä sopimusta."),
  recall: t("You received this safety notice because it concerns a product you bought or sell on Malvoya.",
    "Saat tämän turvallisuustiedotteen, koska se koskee Malvoyassa ostamaasi tai myymääsi tuotetta."),
  seller: t("You received this service message because it concerns your store or courier account on Malvoya.",
    "Saat tämän palveluviestin, koska se koskee kauppa- tai lähettitiliäsi Malvoyassa."),
  support: t("You received this message because you contacted Malvoya.", "Saat tämän viestin, koska otit yhteyttä Malvoyaan."),
  report: t("You received this message because you sent Malvoya a report.", "Saat tämän viestin, koska teit ilmoituksen Malvoyalle."),
};

/** The footer line of a transactional email; both languages when the reader's language is not known. */
export function whyText(kind: EmailKind, locale?: Locale | null): string | null {
  if (kind === "internal") return null;
  const why = WHY[kind];
  return locale ? pick(why, locale) : `${pick(why, "en")} / ${pick(why, "fi")}`;
}

/** Puts the footer line into a message: in the layout's slot, or as a last paragraph of a plain message. */
function withWhy(html: string, text: string, why: string | null) {
  if (!why) return { html: html.replace("<!--why-->", ""), text };
  const line = escapeHtml(why);
  const outHtml = html.includes("<!--why-->")
    ? html.replace("<!--why-->", `${line}<br>`)
    : `${html}<p style="margin:16px 0 0;color:#86868B;font-size:12px;line-height:1.5">${line}</p>`;
  return { html: outHtml, text: `${text}\n\n${why}` };
}

const BRAND = "Malvoya";
// Only a mailbox we actually control: malvoya.com is not ours to send from or receive at.
const SUPPORT_EMAIL = process.env.SUPPORT_EMAIL || "";

export function escapeHtml(value: unknown): string {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function isDeliverableEmail(email?: string | null): email is string {
  return !!email && !email.endsWith("@phone.malvoya.app") && !email.endsWith("@deleted.invalid");
}

function mask(value: string) {
  return value.includes("@") ? value.replace(/^(.).*(@.*)$/, "$1***$2") : `***${value.slice(-3)}`;
}

// ─── Transports ─────────────────────────────────────────────────────────────

let transporter: ReturnType<typeof nodemailer.createTransport> | null = null;
function getTransporter() {
  if (transporter) return transporter;
  if (!process.env.SMTP_HOST || !process.env.SMTP_USER || !process.env.SMTP_PASS) return null;
  transporter = nodemailer.createTransport({
    host: process.env.SMTP_HOST,
    port: Number(process.env.SMTP_PORT) || 587,
    secure: Number(process.env.SMTP_PORT) === 465,
    auth: { user: process.env.SMTP_USER, pass: process.env.SMTP_PASS },
  });
  return transporter;
}

/** Logs in to the SMTP server and logs out again: no email is sent. Null when SMTP is not set up. */
export async function verifyEmailConnection(): Promise<boolean | null> {
  const transport = getTransporter();
  if (!transport) return null;
  await transport.verify();
  return true;
}

/** Email can be sent: SMTP is set up, or (outside production) messages are logged instead of sent. */
export function emailAvailable() {
  return !!getTransporter() || !env.isProduction;
}

/**
 * `sensitive`: the text holds a one-time code; in development the email is logged without its text,
 * because codes and tokens are never written to logs.
 */
export async function sendEmail(
  to: string, subject: string, htmlIn: string, textIn: string,
  opts: { sensitive?: boolean; kind?: EmailKind; locale?: Locale | null; headers?: Record<string, string> } = {},
): Promise<DeliveryResult> {
  if (!isDeliverableEmail(to)) return { delivered: false };
  const { html, text } = withWhy(htmlIn, textIn, opts.kind ? whyText(opts.kind, opts.locale) : null);
  const headers = opts.headers;
  const transport = getTransporter();
  if (!transport) {
    if (env.isProduction) {
      logger.error("SMTP is not configured; email not sent");
      return { delivered: false };
    }
    logger.info({ to: mask(to), subject, ...(opts.sensitive ? {} : { text }), ...(headers ? { headers: Object.keys(headers) } : {}) }, "[dev] Email not sent (SMTP not configured)");
    return { delivered: true, simulated: true };
  }
  // With Redis, ordinary emails go through the background queue (retries, no waiting on SMTP in the request).
  // Sign-in and reset codes (sensitive) are always sent directly, so codes are never stored in Redis.
  if (queueIsRemote() && !opts.sensitive) {
    await enqueue<EmailJob>("email", { to, subject, html, text, headers });
    return { delivered: true, queued: true };
  }
  try {
    await deliverEmail(transport, { to, subject, html, text, headers });
    return { delivered: true };
  } catch (err: any) {
    logger.error({ err: err?.message, to: mask(to) }, "Email delivery failed");
    return { delivered: false };
  }
}

type EmailJob = { to: string; subject: string; html: string; text: string; headers?: Record<string, string> };

function deliverEmail(transport: NonNullable<ReturnType<typeof getTransporter>>, m: EmailJob) {
  // Send as the mailbox we log in with (e.g. a Gmail address); a foreign domain would fail SPF/DMARC
  return transport.sendMail({ from: process.env.SMTP_FROM || `"${BRAND}" <${process.env.SMTP_USER}>`, to: m.to, subject: m.subject, html: m.html, text: m.text, ...(m.headers ? { headers: m.headers } : {}) });
}

defineJob<EmailJob>("email", async (m) => {
  const transport = getTransporter();
  if (!transport) return;
  try {
    await deliverEmail(transport, m);
  } catch (err: any) {
    logger.warn({ err: err?.message, to: mask(m.to) }, "Email delivery failed; will retry");
    throw new Error(err?.message || "Email delivery failed"); // the error never carries the address
  }
}, { attempts: 5, backoffMs: 5_000 });

export async function sendSms(to: string, body: string, opts: { sensitive?: boolean } = {}): Promise<DeliveryResult> {
  const phone = to.replace(/[^0-9+]/g, "");
  const { TWILIO_ACCOUNT_SID: sid, TWILIO_AUTH_TOKEN: token, TWILIO_PHONE_NUMBER: from } = process.env;
  if (!sid || !token || !from) {
    if (env.isProduction) {
      logger.error("Twilio is not configured; SMS not sent");
      return { delivered: false };
    }
    logger.info({ to: mask(phone), ...(opts.sensitive ? {} : { body }) }, "[dev] SMS not sent (Twilio not configured)");
    return { delivered: true, simulated: true };
  }
  try {
    const res = await fetch(`https://api.twilio.com/2010-04-01/Accounts/${sid}/Messages.json`, {
      method: "POST",
      headers: {
        Authorization: "Basic " + Buffer.from(`${sid}:${token}`).toString("base64"),
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: new URLSearchParams({ From: from, To: phone, Body: body }).toString(),
    });
    if (!res.ok) {
      logger.warn({ status: res.status, to: mask(phone) }, "Twilio rejected SMS");
      return { delivered: false };
    }
    return { delivered: true };
  } catch (err: any) {
    logger.error({ err: err?.message, to: mask(phone) }, "SMS delivery failed");
    return { delivered: false };
  }
}

// ─── Templates: each in English and Finnish; the recipient's language is used (English by default) ─────

const money = (cents: number, locale: Locale) => formatCents(cents, locale === "fi" ? "fi-FI" : "en-IE");

function layout(title: string, bodyHtml: string, locale: Locale, footerHtml = "") {
  const support = SUPPORT_EMAIL
    ? `${pick(t("Support", "Asiakaspalvelu"), locale)}: <a href="mailto:${SUPPORT_EMAIL}" style="color:#86868B">${SUPPORT_EMAIL}</a>`
    : escapeHtml(pick(t("Support: the Malvoya app → Support", "Asiakaspalvelu: Malvoya-sovellus → Tuki"), locale));
  return `<!DOCTYPE html><html lang="${locale}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${escapeHtml(title)}</title></head>
<body style="margin:0;padding:24px;background:#F5F5F7;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#1D1D1F">
<div style="max-width:520px;margin:0 auto;background:#fff;border-radius:18px;overflow:hidden">
<div style="padding:24px 28px;border-bottom:1px solid #E5E5EA;font-weight:700;font-size:20px;letter-spacing:-0.3px">${BRAND}</div>
<div style="padding:28px">${bodyHtml}</div>
<div style="padding:18px 28px;background:#FAFAFC;color:#86868B;font-size:12px;line-height:1.5">
<!--why-->${escapeHtml(pick(t("This is an automated message.", "Tämä on automaattinen viesti."), locale))}<br>${support}${footerHtml}
</div></div></body></html>`;
}

/** A plain message: a heading and paragraphs (each escaped), in the reader's language. */
function simpleEmail(to: string, locale: Locale, subject: Text, heading: Text, paragraphs: Text[], kind: EmailKind) {
  const h = pick(heading, locale);
  const ps = paragraphs.map((p) => pick(p, locale));
  const body = `<p style="margin:0 0 12px;font-size:18px;font-weight:700">${escapeHtml(h)}</p>` +
    ps.map((p) => `<p style="margin:0 0 12px;line-height:1.5">${escapeHtml(p).replace(/\n/g, "<br>")}</p>`).join("");
  return sendEmail(to, `${BRAND} – ${pick(subject, locale)}`, layout(h, body, locale), [h, ...ps].join("\n\n"), { kind, locale });
}

/**
 * An optional email (launch alerts; any future referral, promo or newsletter message): never sent to an account that
 * switched optional emails off, and always carries an unsubscribe link in the footer plus List-Unsubscribe and
 * List-Unsubscribe-Post (RFC 8058 one-click) headers.
 */
export async function sendOptionalEmail(userId: number, subject: Text, heading: Text, paragraphs: Text[]): Promise<DeliveryResult> {
  const u = await prisma.user.findUnique({ where: { id: userId }, select: { email: true, locale: true, isActive: true, emailMarketingOptOutAt: true } });
  if (!u || !u.isActive || !isDeliverableEmail(u.email)) return { delivered: false };
  if (u.emailMarketingOptOutAt) return { delivered: false, skipped: "opted_out" };
  const locale: Locale = u.locale === "fi" ? "fi" : "en";
  const h = pick(heading, locale);
  const ps = paragraphs.map((p) => pick(p, locale));
  const url = unsubscribeUrl(userId);
  const why = pick(t("You received this because you asked Malvoya to tell you about it. You can stop these emails at any time:",
    "Saat tämän, koska pyysit Malvoyaa kertomaan siitä. Voit lopettaa nämä viestit milloin tahansa:"), locale);
  const linkText = pick(t("Unsubscribe", "Peru tilaus"), locale);
  const body = `<p style="margin:0 0 12px;font-size:18px;font-weight:700">${escapeHtml(h)}</p>` +
    ps.map((p) => `<p style="margin:0 0 12px;line-height:1.5">${escapeHtml(p)}</p>`).join("");
  const footer = `<br><br>${escapeHtml(why)} <a href="${escapeHtml(url)}" style="color:#6D2E8C">${escapeHtml(linkText)}</a>`;
  const text = [h, ...ps, `${why} ${url}`].join("\n\n");
  return sendEmail(u.email, `${BRAND} – ${pick(subject, locale)}`, layout(h, body, locale, footer), text, { headers: unsubscribeHeaders(userId) });
}

/** A one-time code in large type (sign-in or password reset). Never logged. */
function codeEmail(to: string, locale: Locale, subject: Text, intro: Text, validity: Text, code: string) {
  const html = layout(
    pick(subject, locale),
    `<p style="margin:0 0 16px">${escapeHtml(pick(intro, locale))}</p>
<p style="font-size:34px;font-weight:700;letter-spacing:8px;margin:0 0 16px;font-family:ui-monospace,Menlo,monospace">${escapeHtml(code)}</p>
<p style="margin:0;color:#6E6E73;font-size:14px">${escapeHtml(pick(validity, locale))}</p>`,
    locale,
  );
  const text = `${pick(intro, locale)} ${code}\n\n${pick(validity, locale)}`;
  return sendEmail(to, `${BRAND} – ${pick(subject, locale)}`, html, text, { sensitive: true, kind: "account", locale });
}

export async function sendVerificationCode(target: string, channel: "sms" | "email", code: string, locale: Locale = "en"): Promise<DeliveryResult> {
  if (channel === "sms") {
    return sendSms(target, pick(t(
      `${BRAND}: your code is ${code}. Valid for 10 minutes. Do not share it.`,
      `${BRAND}: vahvistuskoodisi on ${code}. Voimassa 10 min. Älä jaa koodia.`,
    ), locale), { sensitive: true });
  }
  return codeEmail(target, locale,
    t("verification code", "vahvistuskoodi"),
    t("Your verification code:", "Vahvistuskoodisi:"),
    t("The code is valid for 10 minutes. If you didn't ask for this, ignore this email.",
      "Koodi on voimassa 10 minuuttia. Jos et pyytänyt koodia, voit jättää tämän viestin huomiotta."),
    code);
}

/** Password reset code (POST /auth/password/forgot). */
export async function sendPasswordResetCode(to: string, code: string, locale: Locale): Promise<DeliveryResult> {
  return codeEmail(to, locale,
    t("password reset code", "salasanan vaihtokoodi"),
    t("Your code for setting a new password:", "Koodisi uuden salasanan asettamiseen:"),
    t("The code is valid for 15 minutes. If you didn't ask for this, ignore this email.",
      "Koodi on voimassa 15 minuuttia. Jos et pyytänyt tätä, voit jättää viestin huomiotta."),
    code);
}

export type SignInMethod = "google" | "phone" | "email_code" | "apple";

/** Someone asked for a password reset for an account that signs in without a password. */
export async function sendNoPasswordNote(to: string, method: SignInMethod, locale: Locale): Promise<DeliveryResult> {
  const how: Record<SignInMethod, Text> = {
    google: t("You signed in with Google.", "Kirjauduit Googlella."),
    phone: t("You signed in with your phone number.", "Kirjauduit puhelinnumerollasi."),
    email_code: t("You signed in with a one-time code sent to this email address.", "Kirjauduit tähän sähköpostiosoitteeseen lähetetyllä kertakoodilla."),
    apple: t("You signed in with Apple.", "Kirjauduit Applella."),
  };
  return simpleEmail(to, locale, t("how to sign in", "näin kirjaudut"), t("No password is needed", "Salasanaa ei tarvita"), [
    how[method],
    t("Use that to sign in. No password is needed.", "Kirjaudu samalla tavalla. Salasanaa ei tarvita."),
    t("If you didn't ask for this, ignore this email.", "Jos et pyytänyt tätä, voit jättää viestin huomiotta."),
  ], "account");
}

/** An admin approved a store or courier account. */
export type TwoStepEvent = "enabled" | "disabled" | "recovery_code_used" | "recovery_codes_renewed";

/** Security notice to the account's own address when two-step sign-in changes or a recovery code is used. */
export async function sendTwoStepNotice(to: string, event: TwoStepEvent, recoveryCodesLeft: number | null, locale: Locale): Promise<DeliveryResult> {
  const texts: Record<TwoStepEvent, [Text, Text]> = {
    enabled: [t("Two-step sign-in is on", "Kaksivaiheinen kirjautuminen on päällä"),
      t("From now on, signing in also asks for a code from your authenticator app. Keep your recovery codes somewhere safe.",
        "Kirjautuminen kysyy tästä lähtien myös todennussovelluksesi koodia. Säilytä varakoodit turvallisessa paikassa.")],
    disabled: [t("Two-step sign-in was turned off", "Kaksivaiheinen kirjautuminen poistettiin käytöstä"),
      t("Signing in no longer asks for an authenticator code.", "Kirjautuminen ei enää kysy todennussovelluksen koodia.")],
    recovery_code_used: [t("A recovery code was used to sign in", "Kirjautumiseen käytettiin varakoodia"),
      t(`Each recovery code works once. Codes left: ${recoveryCodesLeft ?? 0}.`, `Jokainen varakoodi toimii kerran. Koodeja jäljellä: ${recoveryCodesLeft ?? 0}.`)],
    recovery_codes_renewed: [t("New recovery codes were made", "Uudet varakoodit luotiin"),
      t("Your earlier recovery codes no longer work.", "Aiemmat varakoodisi eivät enää toimi.")],
  };
  const [heading, body] = texts[event];
  return simpleEmail(to, locale, heading, heading, [body,
    t("If this was not you, change your password at once and contact the Malvoya team.",
      "Jos tämä et ollut sinä, vaihda salasanasi heti ja ota yhteyttä Malvoyan tiimiin.")], "account");
}

export async function sendApprovalEmail(to: string, kind: "store" | "courier", locale: Locale): Promise<DeliveryResult> {
  return kind === "store"
    ? simpleEmail(to, locale, t("your store is approved", "kauppasi on hyväksytty"), t("You're approved", "Sinut on hyväksytty"), [
        t("Your store is now live on Malvoya: you can start selling. Shoppers nearby can see your products.",
          "Kauppasi näkyy nyt Malvoyassa: voit aloittaa myynnin. Lähellä olevat ostajat näkevät tuotteesi."),
        t("Set up payouts in Malvoya Store so your sales reach your bank account.",
          "Ota maksut käyttöön Malvoya Store -sovelluksessa, jotta myyntisi tilitetään pankkitilillesi."),
      ], "seller")
    : simpleEmail(to, locale, t("your courier account is approved", "lähettitilisi on hyväksytty"), t("You're approved", "Sinut on hyväksytty"), [
        t("Your courier account is approved: you can start delivering. Go online in Malvoya Courier to get delivery offers.",
          "Lähettitilisi on hyväksytty: voit aloittaa toimitukset. Siirry linjoille Malvoya Courier -sovelluksessa, niin saat toimitustarjouksia."),
        t("Set up payouts in the app so your earnings reach your bank account.",
          "Ota maksut käyttöön sovelluksessa, jotta ansiosi tilitetään pankkitilillesi."),
      ], "seller");
}

/** DAC7: the store has sales this year but has not given its tax details yet. */
export async function sendTaxInfoReminder(to: string, storeName: string, locale: Locale): Promise<DeliveryResult> {
  return simpleEmail(to, locale, t("tax details needed", "verotiedot puuttuvat"), t("Please add your tax details", "Lisää verotietosi"), [
    t(`${storeName} has sales on Malvoya this year. EU rules (DAC7) require Malvoya to report sellers' sales and identity details to the Finnish Tax Administration once a year.`,
      `Kaupallasi ${storeName} on myyntiä Malvoyassa tänä vuonna. EU:n säännöt (DAC7) velvoittavat Malvoyan ilmoittamaan myyjien myynnit ja tunnistetiedot Verohallinnolle kerran vuodessa.`),
    t("Open Malvoya Store → Tax details and fill them in. It takes a couple of minutes.",
      "Avaa Malvoya Store → Verotiedot ja täytä ne. Se vie pari minuuttia."),
  ], "seller");
}

/** DSA statement of reasons when a moderator removes a store's drop. */
export async function sendDropRemovedEmail(to: string, dropId: number, reason: string, locale: Locale): Promise<DeliveryResult> {
  return simpleEmail(to, locale, t("a drop was removed", "drop poistettiin"), t(`Your drop #${dropId} was removed from Malvoya`, `Droppisi #${dropId} poistettiin Malvoyasta`), [
    t(`Reason: ${reason}`, `Syy: ${reason}`),
    t("This decision was made by a person on the Malvoya team after review.", "Päätöksen teki Malvoyan tiimin jäsen tarkistuksen jälkeen."),
    t("If you think it is wrong, reply to this email or contact us through Support in Malvoya Store within 6 months and we will look at it again.",
      "Jos päätös on mielestäsi väärä, vastaa tähän viestiin tai ota yhteyttä Malvoya Storen Tuki-osion kautta 6 kuukauden kuluessa, niin tarkistamme asian uudelleen."),
  ], "seller");
}

/** Statement of reasons (DSA Art. 17) when an admin ends a store's live stream. */
export async function sendLiveEndedEmail(to: string, liveId: number, title: string, reason: string, locale: Locale): Promise<DeliveryResult> {
  return simpleEmail(to, locale, t("your live was ended", "livelähetyksesi lopetettiin"), t(`Your live "${title}" (#${liveId}) was ended by Malvoya`, `Livelähetyksesi "${title}" (#${liveId}) lopetettiin Malvoyassa`), [
    t(`Reason: ${reason}`, `Syy: ${reason}`),
    t("This decision was made by a person on the Malvoya team. The live was not recorded.", "Päätöksen teki Malvoyan tiimin jäsen. Lähetystä ei tallennettu."),
    t("If you think it is wrong, reply to this email or contact us through Support in Malvoya Store within 6 months and we will look at it again.",
      "Jos päätös on mielestäsi väärä, vastaa tähän viestiin tai ota yhteyttä Malvoya Storen Tuki-osion kautta 6 kuukauden kuluessa, niin tarkistamme asian uudelleen."),
  ], "seller");
}

/** Support request received (to the person who wrote). */
export async function sendSupportAck(to: string, requestId: number, locale: Locale): Promise<DeliveryResult> {
  return simpleEmail(to, locale, t(`we got your message #${requestId}`, `saimme viestisi #${requestId}`), t("Thanks for your message", "Kiitos viestistäsi"), [
    t(`We received your message (#${requestId}) and will reply to ${to}.`, `Viestisi (#${requestId}) on vastaanotettu. Vastaamme osoitteeseen ${to}.`),
  ], "support");
}

export interface OrderConfirmationData {
  tipCents?: number;
  orderId: number;
  customerName: string;
  email?: string | null;
  storeName: string;
  items: { name: string; quantity: number; unitCents: number; hygieneSealed?: boolean }[];
  subtotalCents: number;
  deliveryFeeCents: number;
  serviceFeeCents?: number;
  smallOrderFeeCents?: number;
  discountCents?: number;
  promoCode?: string | null;
  totalCents: number;
  deliveryAddress?: string | null;
  /** Scheduled delivery window, e.g. { en: "Tonight 17:00–19:00", fi: "Tänä iltana 17.00–19.00" } */
  deliveryWindow?: { en: string; fi: string } | null;
}

/**
 * Order confirmation (tilausvahvistus). The seller is the store, not Malvoya — this is not a VAT invoice.
 */
/**
 * Hygiene-sealed items (KSL 6:13 and 6:16): the confirmation repeats that the right of withdrawal is lost once the seal
 * is opened, and names the items it applies to.
 */
function sealedNote(items: OrderConfirmationData["items"], L: Locale) {
  const sealed = items.filter((i) => i.hygieneSealed).map((i) => escapeHtml(i.name));
  if (!sealed.length) return "";
  const text = L === "fi"
    ? `Hygieniasinetöidyt tuotteet: ${sealed.join(", ")}. Niitä ei voi palauttaa peruuttamisoikeudella, jos sinetti avataan. Avaamattomina voit palauttaa ne 14 päivän kuluessa, ja virheelliset tuotteet aina.`
    : `Hygiene-sealed items: ${sealed.join(", ")}. They can't be returned under the right of withdrawal once the seal is opened. Unopened, you can return them within 14 days, and faulty items always.`;
  return `<p style="margin:8px 0 0;color:#6E6E73;font-size:13px;line-height:1.5">${text}</p>`;
}

export async function sendOrderConfirmation(data: OrderConfirmationData): Promise<DeliveryResult> {
  if (!isDeliverableEmail(data.email)) return { delivered: false };
  const L = await localeOfEmail(data.email);
  const p = (en: string, fi: string) => (L === "fi" ? fi : en);
  const row = (label: string, cents: number, minus = false) =>
    `<tr><td style="padding:6px 0">${label}</td><td style="padding:6px 0;text-align:right">${minus ? "−" : ""}${money(cents, L)}</td></tr>`;
  const rows = data.items
    .map((i) => `<tr><td style="padding:6px 0">${escapeHtml(i.name)} × ${i.quantity}</td><td style="padding:6px 0;text-align:right">${money(i.unitCents * i.quantity, L)}</td></tr>`)
    .join("");
  const title = p(`Order confirmation #${data.orderId}`, `Tilausvahvistus #${data.orderId}`);
  const html = layout(
    title,
    `<p style="margin:0 0 4px;font-size:22px;font-weight:700">${p("Thank you for your order", "Kiitos tilauksestasi")}, ${escapeHtml(data.customerName)}!</p>
<p style="margin:0 0 20px;color:#6E6E73">${p("Order", "Tilaus")} #${data.orderId}</p>
<p style="margin:0 0 12px">${p("Seller", "Myyjä")}: <strong>${escapeHtml(data.storeName)}</strong></p>
<table style="width:100%;border-collapse:collapse;font-size:15px">${rows}
<tr><td style="padding:6px 0;border-top:1px solid #E5E5EA">${p("Delivery", "Toimitus")}</td><td style="padding:6px 0;border-top:1px solid #E5E5EA;text-align:right">${money(data.deliveryFeeCents, L)}</td></tr>
${data.serviceFeeCents ? row(p("Service fee", "Palvelumaksu"), data.serviceFeeCents) : ""}
${data.smallOrderFeeCents ? row(p("Small-order fee", "Pientilauslisä"), data.smallOrderFeeCents) : ""}
${data.discountCents ? row(`${p("Discount", "Alennus")}${data.promoCode ? ` (${escapeHtml(data.promoCode)})` : ""}`, data.discountCents, true) : ""}
${data.tipCents ? row(p("Courier tip", "Tippi lähetille"), data.tipCents) : ""}
<tr><td style="padding:10px 0;font-weight:700">${p("Total (incl. VAT)", "Yhteensä (sis. ALV)")}</td><td style="padding:10px 0;text-align:right;font-weight:700">${money(data.totalCents, L)}</td></tr></table>
${data.deliveryAddress ? `<p style="margin:16px 0 0;color:#6E6E73;font-size:14px">${p("Delivery address", "Toimitusosoite")}: ${escapeHtml(data.deliveryAddress)}</p>` : ""}
${data.deliveryWindow ? `<p style="margin:8px 0 0;color:#6E6E73;font-size:14px">${p("Delivery time", "Toimitusaika")}: ${escapeHtml(pick(data.deliveryWindow, L))}</p>` : ""}
<p style="margin:20px 0 0;color:#6E6E73;font-size:13px;line-height:1.5">${p("You have a 14-day right of withdrawal from the day you receive the item.", "Sinulla on 14 päivän peruuttamisoikeus tuotteen vastaanottamisesta.")}</p>
${sealedNote(data.items, L)}`,
    L,
  );
  const text = p(`Order #${data.orderId} from ${data.storeName}. Total ${money(data.totalCents, L)} incl. VAT.`,
    `Tilaus #${data.orderId} myyjältä ${data.storeName}. Yhteensä ${money(data.totalCents, L)} sis. ALV.`);
  return sendEmail(data.email, `${BRAND} – ${p("order confirmation", "tilausvahvistus")} #${data.orderId}`, html, text, { kind: "order", locale: L });
}

const STATUS_TEXT: Record<string, { fi: string; en: string }> = {
  CONFIRMED: { fi: "Myyjä vahvisti tilauksesi.", en: "The seller confirmed your order." },
  SHIPPED:   { fi: "Lähetti on noutanut tilauksesi ja on matkalla.", en: "Your courier has picked up the order and is on the way." },
  DELIVERED: { fi: "Tilauksesi on toimitettu.", en: "Your order has been delivered." },
  READY_FOR_PICKUP: { fi: "Tilauksesi on noudettavissa myymälästä. Näytä noutokoodisi sovelluksesta.", en: "Your order is ready for pickup at the store. Show your pickup code from the app." },
  COLLECTED: { fi: "Olet noutanut tilauksesi.", en: "You have collected your order." },
  CANCELLED: { fi: "Tilauksesi on peruttu. Mahdollinen maksu palautetaan.", en: "Your order was cancelled. Any payment will be refunded." },
  RETURNED_TO_STORE: {
    fi: "Lähetti ei tavoittanut sinua osoitteessa, joten tilaus viedään takaisin kauppaan ja se on peruttu. Tuotteiden hinta palautetaan maksutavallesi. Toimitusmaksua ja lähetin tippiä ei palauteta, koska toimitus ajettiin.",
    en: "Your courier could not reach you at the address, so the order is going back to the shop and has been cancelled. The price of the items is refunded to your payment method. The delivery fee and the courier's tip are not refunded, because the delivery was made.",
  },
};

/** Order status email; `reason` (e.g. the store's reason for cancelling) is added on its own line. */
export async function sendOrderStatusEmail(orderId: number, email: string | null | undefined, status: string, extra: { reason?: string | null } = {}): Promise<DeliveryResult> {
  const text = STATUS_TEXT[status];
  if (!text || !isDeliverableEmail(email)) return { delivered: false };
  const L = await localeOfEmail(email);
  const order = pick(t(`Order #${orderId}`, `Tilaus #${orderId}`), L);
  const reason = extra.reason ? `${pick(t("Reason", "Syy"), L)}: ${extra.reason}` : "";
  const html = layout(order, `<p style="margin:0 0 8px;font-size:18px;font-weight:700">${escapeHtml(order)}</p><p style="margin:0">${escapeHtml(pick(text, L))}</p>${reason ? `<p style="margin:12px 0 0;color:#6E6E73">${escapeHtml(reason)}</p>` : ""}`, L);
  return sendEmail(email, `${BRAND} – ${order.toLowerCase()}`, html, `${pick(text, L)}${reason ? `\n${reason}` : ""} (${order})`, { kind: "order", locale: L });
}

export interface WithdrawalAck {
  orderId: number;
  at: Date;
  storeName: string;
  storeAddress: string | null;
  items: { name: string; quantity: number }[];
  note: string | null;
  email: string | null;
  phone: string | null;
  locale: Locale;
}

/**
 * Acknowledgement of a withdrawal made with the withdrawal function (KSL 6:14 a, CRD Art. 11a; since 2.16.0), sent at
 * once on a durable medium: what was withdrawn (order, seller, items), the date and time, and what happens next. Email
 * to the account address; phone-only accounts get an SMS. Returns the channel used, or null when neither could be sent.
 */
export async function sendWithdrawalAck(a: WithdrawalAck): Promise<{ channel: "email" | "sms" | null }> {
  const L = a.locale;
  const when = new Intl.DateTimeFormat(L === "fi" ? "fi-FI" : "en-GB", {
    timeZone: "Europe/Helsinki", day: "numeric", month: "numeric", year: "numeric", hour: "2-digit", minute: "2-digit", second: "2-digit",
  }).format(a.at);
  const items = a.items.map((i) => `${i.name} × ${i.quantity}`).join(", ");
  if (isDeliverableEmail(a.email)) {
    const r = await simpleEmail(a.email, L,
      t(`withdrawal received – order #${a.orderId}`, `peruminen vastaanotettu – tilaus #${a.orderId}`),
      t("We received your withdrawal", "Perumisesi on vastaanotettu"),
      [
        t(`You withdrew from your purchase from ${a.storeName} (order #${a.orderId}) with the withdrawal function in the Malvoya app on ${when} (Finnish time, ${a.at.toISOString()}).`,
          `Peruit ostoksesi myyjältä ${a.storeName} (tilaus #${a.orderId}) Malvoya-sovelluksen peruuttamistoiminnolla ${when} (Suomen aikaa, ${a.at.toISOString()}).`),
        t(`Items withdrawn: ${items}.`, `Perutut tuotteet: ${items}.`),
        ...(a.note ? [t(`Your note: ${a.note}`, `Viestisi: ${a.note}`)] : []),
        t(`Next steps: return the items to ${a.storeName}${a.storeAddress ? `, ${a.storeAddress}` : ""} within 14 days of today. The seller refunds what you paid for them, and the standard delivery fee when you return the whole order, within 14 days of receiving your withdrawal; the seller may wait until it has the items back or you show that you have sent them. Hygiene-sealed items must come back with the seal unbroken.`,
          `Seuraavaksi: palauta tuotteet myyjälle ${a.storeName}${a.storeAddress ? `, ${a.storeAddress}` : ""} 14 päivän kuluessa tästä päivästä. Myyjä palauttaa niistä maksamasi summan, ja koko tilauksen palauttaessasi myös tavallisen toimitusmaksun, 14 päivän kuluessa perumisesi vastaanottamisesta; myyjä voi odottaa, kunnes se on saanut tuotteet takaisin tai osoitat lähettäneesi ne. Hygieniasinetöidyt tuotteet on palautettava sinetti ehjänä.`),
        t("You can follow the return in the app: Profile → Returns. Keep this email: it is your acknowledgement of the withdrawal.",
          "Voit seurata palautusta sovelluksessa: Profiili → Palautukset. Säilytä tämä viesti: se on vahvistus perumisestasi."),
      ], "order");
    return { channel: r.delivered ? "email" : null };
  }
  if (a.phone) {
    const r = await sendSms(a.phone, pick(t(
      `Malvoya: withdrawal received ${when} for order #${a.orderId} (${a.storeName}): ${items}. Return the items within 14 days; refund within 14 days. Details: app → Returns.`,
      `Malvoya: peruminen vastaanotettu ${when}, tilaus #${a.orderId} (${a.storeName}): ${items}. Palauta tuotteet 14 päivässä; hyvitys 14 päivässä. Lisätiedot: sovellus → Palautukset.`,
    ), L));
    return { channel: r.delivered ? "sms" : null };
  }
  return { channel: null };
}
