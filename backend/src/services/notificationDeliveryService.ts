import nodemailer from "nodemailer";
import pino from "pino";
import { env } from "../config/env";
import { formatCents } from "../utils/pricing";
import { Locale, Text, localeOfEmail, pick, t } from "../lib/i18n";
import { defineJob, enqueue, queueIsRemote } from "../lib/queue";

const logger = pino({ name: "Notifications" });

export interface DeliveryResult {
  delivered: boolean;
  /** true when no provider is configured and we are outside production (dev convenience) */
  simulated?: boolean;
  /** true when the email was handed to the background queue (REDIS_URL set); it is sent with retries */
  queued?: boolean;
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

/** Email can be sent: SMTP is set up, or (outside production) messages are logged instead of sent. */
export function emailAvailable() {
  return !!getTransporter() || !env.isProduction;
}

/**
 * `sensitive`: the text holds a one-time code; in development the email is logged without its text,
 * because codes and tokens are never written to logs.
 */
export async function sendEmail(to: string, subject: string, html: string, text: string, opts: { sensitive?: boolean } = {}): Promise<DeliveryResult> {
  if (!isDeliverableEmail(to)) return { delivered: false };
  const transport = getTransporter();
  if (!transport) {
    if (env.isProduction) {
      logger.error("SMTP is not configured; email not sent");
      return { delivered: false };
    }
    logger.info({ to: mask(to), subject, ...(opts.sensitive ? {} : { text }) }, "[dev] Email not sent (SMTP not configured)");
    return { delivered: true, simulated: true };
  }
  // With Redis, ordinary emails go through the background queue (retries, no waiting on SMTP in the request).
  // Sign-in and reset codes (sensitive) are always sent directly, so codes are never stored in Redis.
  if (queueIsRemote() && !opts.sensitive) {
    await enqueue<EmailJob>("email", { to, subject, html, text });
    return { delivered: true, queued: true };
  }
  try {
    await deliverEmail(transport, { to, subject, html, text });
    return { delivered: true };
  } catch (err: any) {
    logger.error({ err: err?.message, to: mask(to) }, "Email delivery failed");
    return { delivered: false };
  }
}

type EmailJob = { to: string; subject: string; html: string; text: string };

function deliverEmail(transport: NonNullable<ReturnType<typeof getTransporter>>, m: EmailJob) {
  // Send as the mailbox we log in with (e.g. a Gmail address); a foreign domain would fail SPF/DMARC
  return transport.sendMail({ from: process.env.SMTP_FROM || `"${BRAND}" <${process.env.SMTP_USER}>`, to: m.to, subject: m.subject, html: m.html, text: m.text });
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

function layout(title: string, bodyHtml: string, locale: Locale) {
  const support = SUPPORT_EMAIL
    ? `${pick(t("Support", "Asiakaspalvelu"), locale)}: <a href="mailto:${SUPPORT_EMAIL}" style="color:#86868B">${SUPPORT_EMAIL}</a>`
    : escapeHtml(pick(t("Support: the Malvoya app → Support", "Asiakaspalvelu: Malvoya-sovellus → Tuki"), locale));
  return `<!DOCTYPE html><html lang="${locale}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${escapeHtml(title)}</title></head>
<body style="margin:0;padding:24px;background:#F5F5F7;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#1D1D1F">
<div style="max-width:520px;margin:0 auto;background:#fff;border-radius:18px;overflow:hidden">
<div style="padding:24px 28px;border-bottom:1px solid #E5E5EA;font-weight:700;font-size:20px;letter-spacing:-0.3px">${BRAND}</div>
<div style="padding:28px">${bodyHtml}</div>
<div style="padding:18px 28px;background:#FAFAFC;color:#86868B;font-size:12px;line-height:1.5">
${escapeHtml(pick(t("This is an automated message.", "Tämä on automaattinen viesti."), locale))}<br>${support}
</div></div></body></html>`;
}

/** A plain message: a heading and paragraphs (each escaped), in the reader's language. */
function simpleEmail(to: string, locale: Locale, subject: Text, heading: Text, paragraphs: Text[]) {
  const h = pick(heading, locale);
  const ps = paragraphs.map((p) => pick(p, locale));
  const body = `<p style="margin:0 0 12px;font-size:18px;font-weight:700">${escapeHtml(h)}</p>` +
    ps.map((p) => `<p style="margin:0 0 12px;line-height:1.5">${escapeHtml(p).replace(/\n/g, "<br>")}</p>`).join("");
  return sendEmail(to, `${BRAND} – ${pick(subject, locale)}`, layout(h, body, locale), [h, ...ps].join("\n\n"));
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
  return sendEmail(to, `${BRAND} – ${pick(subject, locale)}`, html, text, { sensitive: true });
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
  ]);
}

/** An admin approved a store or courier account. */
export async function sendApprovalEmail(to: string, kind: "store" | "courier", locale: Locale): Promise<DeliveryResult> {
  return kind === "store"
    ? simpleEmail(to, locale, t("your store is approved", "kauppasi on hyväksytty"), t("You're approved", "Sinut on hyväksytty"), [
        t("Your store is now live on Malvoya: you can start selling. Shoppers nearby can see your products.",
          "Kauppasi näkyy nyt Malvoyassa: voit aloittaa myynnin. Lähellä olevat ostajat näkevät tuotteesi."),
        t("Set up payouts in Malvoya Store so your sales reach your bank account.",
          "Ota maksut käyttöön Malvoya Store -sovelluksessa, jotta myyntisi tilitetään pankkitilillesi."),
      ])
    : simpleEmail(to, locale, t("your courier account is approved", "lähettitilisi on hyväksytty"), t("You're approved", "Sinut on hyväksytty"), [
        t("Your courier account is approved: you can start delivering. Go online in Malvoya Courier to get delivery offers.",
          "Lähettitilisi on hyväksytty: voit aloittaa toimitukset. Siirry linjoille Malvoya Courier -sovelluksessa, niin saat toimitustarjouksia."),
        t("Set up payouts in the app so your earnings reach your bank account.",
          "Ota maksut käyttöön sovelluksessa, jotta ansiosi tilitetään pankkitilillesi."),
      ]);
}

/** DAC7: the store has sales this year but has not given its tax details yet. */
export async function sendTaxInfoReminder(to: string, storeName: string, locale: Locale): Promise<DeliveryResult> {
  return simpleEmail(to, locale, t("tax details needed", "verotiedot puuttuvat"), t("Please add your tax details", "Lisää verotietosi"), [
    t(`${storeName} has sales on Malvoya this year. EU rules (DAC7) require Malvoya to report sellers' sales and identity details to the Finnish Tax Administration once a year.`,
      `Kaupallasi ${storeName} on myyntiä Malvoyassa tänä vuonna. EU:n säännöt (DAC7) velvoittavat Malvoyan ilmoittamaan myyjien myynnit ja tunnistetiedot Verohallinnolle kerran vuodessa.`),
    t("Open Malvoya Store → Tax details and fill them in. It takes a couple of minutes.",
      "Avaa Malvoya Store → Verotiedot ja täytä ne. Se vie pari minuuttia."),
  ]);
}

/** DSA statement of reasons when a moderator removes a store's drop. */
export async function sendDropRemovedEmail(to: string, dropId: number, reason: string, locale: Locale): Promise<DeliveryResult> {
  return simpleEmail(to, locale, t("a drop was removed", "drop poistettiin"), t(`Your drop #${dropId} was removed from Malvoya`, `Droppisi #${dropId} poistettiin Malvoyasta`), [
    t(`Reason: ${reason}`, `Syy: ${reason}`),
    t("This decision was made by a person on the Malvoya team after review.", "Päätöksen teki Malvoyan tiimin jäsen tarkistuksen jälkeen."),
    t("If you think it is wrong, reply to this email or contact us through Support in Malvoya Store within 6 months and we will look at it again.",
      "Jos päätös on mielestäsi väärä, vastaa tähän viestiin tai ota yhteyttä Malvoya Storen Tuki-osion kautta 6 kuukauden kuluessa, niin tarkistamme asian uudelleen."),
  ]);
}

/** Support request received (to the person who wrote). */
export async function sendSupportAck(to: string, requestId: number, locale: Locale): Promise<DeliveryResult> {
  return simpleEmail(to, locale, t(`we got your message #${requestId}`, `saimme viestisi #${requestId}`), t("Thanks for your message", "Kiitos viestistäsi"), [
    t(`We received your message (#${requestId}) and will reply to ${to}.`, `Viestisi (#${requestId}) on vastaanotettu. Vastaamme osoitteeseen ${to}.`),
  ]);
}

export interface OrderConfirmationData {
  tipCents?: number;
  orderId: number;
  customerName: string;
  email?: string | null;
  storeName: string;
  items: { name: string; quantity: number; unitCents: number }[];
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
<p style="margin:20px 0 0;color:#6E6E73;font-size:13px;line-height:1.5">${p("You have a 14-day right of withdrawal from the day you receive the item.", "Sinulla on 14 päivän peruuttamisoikeus tuotteen vastaanottamisesta.")}</p>`,
    L,
  );
  const text = p(`Order #${data.orderId} from ${data.storeName}. Total ${money(data.totalCents, L)} incl. VAT.`,
    `Tilaus #${data.orderId} myyjältä ${data.storeName}. Yhteensä ${money(data.totalCents, L)} sis. ALV.`);
  return sendEmail(data.email, `${BRAND} – ${p("order confirmation", "tilausvahvistus")} #${data.orderId}`, html, text);
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
  return sendEmail(email, `${BRAND} – ${order.toLowerCase()}`, html, `${pick(text, L)}${reason ? `\n${reason}` : ""} (${order})`);
}
