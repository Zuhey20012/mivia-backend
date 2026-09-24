import nodemailer from "nodemailer";
import pino from "pino";
import { env } from "../config/env";
import { formatCents } from "../utils/pricing";

const logger = pino({ name: "Notifications" });

export interface DeliveryResult {
  delivered: boolean;
  /** true when no provider is configured and we are outside production (dev convenience) */
  simulated?: boolean;
}

const BRAND = "Malvoya";
const SUPPORT_EMAIL = process.env.SUPPORT_EMAIL || "support@malvoya.com";

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

export async function sendEmail(to: string, subject: string, html: string, text: string): Promise<DeliveryResult> {
  if (!isDeliverableEmail(to)) return { delivered: false };
  const transport = getTransporter();
  if (!transport) {
    if (env.isProduction) {
      logger.error("SMTP is not configured; email not sent");
      return { delivered: false };
    }
    logger.info({ to: mask(to), subject, text }, "[dev] Email not sent (SMTP not configured)");
    return { delivered: true, simulated: true };
  }
  try {
    await transport.sendMail({ from: process.env.SMTP_FROM || `"${BRAND}" <no-reply@malvoya.com>`, to, subject, html, text });
    return { delivered: true };
  } catch (err: any) {
    logger.error({ err: err?.message, to: mask(to) }, "Email delivery failed");
    return { delivered: false };
  }
}

export async function sendSms(to: string, body: string): Promise<DeliveryResult> {
  const phone = to.replace(/[^0-9+]/g, "");
  const { TWILIO_ACCOUNT_SID: sid, TWILIO_AUTH_TOKEN: token, TWILIO_PHONE_NUMBER: from } = process.env;
  if (!sid || !token || !from) {
    if (env.isProduction) {
      logger.error("Twilio is not configured; SMS not sent");
      return { delivered: false };
    }
    logger.info({ to: mask(phone), body }, "[dev] SMS not sent (Twilio not configured)");
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

// ─── Templates ──────────────────────────────────────────────────────────────

function layout(title: string, bodyHtml: string) {
  return `<!DOCTYPE html><html lang="fi"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${escapeHtml(title)}</title></head>
<body style="margin:0;padding:24px;background:#F5F5F7;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#1D1D1F">
<div style="max-width:520px;margin:0 auto;background:#fff;border-radius:18px;overflow:hidden">
<div style="padding:24px 28px;border-bottom:1px solid #E5E5EA;font-weight:700;font-size:20px;letter-spacing:-0.3px">${BRAND}</div>
<div style="padding:28px">${bodyHtml}</div>
<div style="padding:18px 28px;background:#FAFAFC;color:#86868B;font-size:12px;line-height:1.5">
Tämä on automaattinen viesti. / This is an automated message.<br>Asiakaspalvelu / Support: <a href="mailto:${SUPPORT_EMAIL}" style="color:#86868B">${SUPPORT_EMAIL}</a>
</div></div></body></html>`;
}

export async function sendVerificationCode(target: string, channel: "sms" | "email", code: string): Promise<DeliveryResult> {
  if (channel === "sms") {
    return sendSms(target, `${BRAND}: vahvistuskoodisi on ${code}. Voimassa 10 min. Your code is ${code}. Älä jaa koodia. Do not share it.`);
  }
  const html = layout(
    "Vahvistuskoodi / Verification code",
    `<p style="margin:0 0 16px">Vahvistuskoodisi / Your verification code:</p>
<p style="font-size:34px;font-weight:700;letter-spacing:8px;margin:0 0 16px;font-family:ui-monospace,Menlo,monospace">${escapeHtml(code)}</p>
<p style="margin:0;color:#6E6E73;font-size:14px">Koodi on voimassa 10 minuuttia. Jos et pyytänyt koodia, voit ohittaa tämän viestin.<br>The code is valid for 10 minutes. If you did not request it, you can ignore this email.</p>`
  );
  return sendEmail(target, `${BRAND} – vahvistuskoodi / verification code`, html, `Your ${BRAND} verification code is ${code}. Valid for 10 minutes.`);
}

export interface OrderConfirmationData {
  orderId: number;
  customerName: string;
  email?: string | null;
  storeName: string;
  items: { name: string; quantity: number; unitCents: number }[];
  subtotalCents: number;
  deliveryFeeCents: number;
  totalCents: number;
  deliveryAddress?: string | null;
}

/**
 * Order confirmation (tilausvahvistus). The seller is the store, not Malvoya — this is not a VAT invoice.
 */
export async function sendOrderConfirmation(data: OrderConfirmationData): Promise<DeliveryResult> {
  if (!isDeliverableEmail(data.email)) return { delivered: false };
  const rows = data.items
    .map((i) => `<tr><td style="padding:6px 0">${escapeHtml(i.name)} × ${i.quantity}</td><td style="padding:6px 0;text-align:right">${formatCents(i.unitCents * i.quantity)}</td></tr>`)
    .join("");
  const html = layout(
    `Tilausvahvistus #${data.orderId}`,
    `<p style="margin:0 0 4px;font-size:22px;font-weight:700">Kiitos tilauksestasi, ${escapeHtml(data.customerName)}!</p>
<p style="margin:0 0 20px;color:#6E6E73">Thank you for your order. Tilaus / Order #${data.orderId}</p>
<p style="margin:0 0 12px">Myyjä / Seller: <strong>${escapeHtml(data.storeName)}</strong></p>
<table style="width:100%;border-collapse:collapse;font-size:15px">${rows}
<tr><td style="padding:6px 0;border-top:1px solid #E5E5EA">Toimitus / Delivery</td><td style="padding:6px 0;border-top:1px solid #E5E5EA;text-align:right">${formatCents(data.deliveryFeeCents)}</td></tr>
<tr><td style="padding:10px 0;font-weight:700">Yhteensä / Total (sis. ALV / incl. VAT)</td><td style="padding:10px 0;text-align:right;font-weight:700">${formatCents(data.totalCents)}</td></tr></table>
${data.deliveryAddress ? `<p style="margin:16px 0 0;color:#6E6E73;font-size:14px">Toimitusosoite / Delivery address: ${escapeHtml(data.deliveryAddress)}</p>` : ""}
<p style="margin:20px 0 0;color:#6E6E73;font-size:13px;line-height:1.5">Sinulla on 14 päivän peruuttamisoikeus tuotteen vastaanottamisesta. You have a 14-day right of withdrawal from the day you receive the item.</p>`
  );
  const text = `Order #${data.orderId} from ${data.storeName}. Total ${formatCents(data.totalCents)} incl. VAT.`;
  return sendEmail(data.email, `${BRAND} – tilausvahvistus / order confirmation #${data.orderId}`, html, text);
}

const STATUS_TEXT: Record<string, { fi: string; en: string }> = {
  CONFIRMED: { fi: "Myyjä vahvisti tilauksesi.", en: "The seller confirmed your order." },
  SHIPPED:   { fi: "Lähetti on noutanut tilauksesi ja on matkalla.", en: "Your courier has picked up the order and is on the way." },
  DELIVERED: { fi: "Tilauksesi on toimitettu.", en: "Your order has been delivered." },
  CANCELLED: { fi: "Tilauksesi on peruttu. Mahdollinen maksu palautetaan.", en: "Your order was cancelled. Any payment will be refunded." },
};

export async function sendOrderStatusEmail(orderId: number, email: string | null | undefined, status: string): Promise<DeliveryResult> {
  const text = STATUS_TEXT[status];
  if (!text || !isDeliverableEmail(email)) return { delivered: false };
  const html = layout(`Tilaus #${orderId}`, `<p style="margin:0 0 8px;font-size:18px;font-weight:700">Tilaus / Order #${orderId}</p><p style="margin:0">${text.fi}<br><span style="color:#6E6E73">${text.en}</span></p>`);
  return sendEmail(email, `${BRAND} – tilaus #${orderId}`, html, `${text.en} (Order #${orderId})`);
}
