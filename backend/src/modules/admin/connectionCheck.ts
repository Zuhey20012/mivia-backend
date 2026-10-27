import { Request, Response } from "express";
import { prisma } from "../../lib/prisma";
import { env } from "../../config/env";
import { getStripe } from "../../lib/stripe";
import { pingCloudinary } from "../../lib/cloudinary";
import { verifyPushCredentials } from "../../lib/push";
import { verifyEmailConnection } from "../../services/notificationDeliveryService";
import { sendError } from "../../lib/errors";

/**
 * "Test connections" on the System page: logs in to each outside service for real, without sending
 * an email, SMS or push and without moving money, and says in plain words whether it works.
 * Results never contain keys or secrets, and provider error texts are replaced by our own.
 */
export type Check = { ok: boolean | null; detail: string };

const notSetUp = (what: string): Check => ({ ok: null, detail: `Not set up: add ${what} on Render.` });
const TIMEOUT_MS = 10_000;

function withTimeout<T>(p: Promise<T>): Promise<T> {
  return Promise.race([p, new Promise<T>((_, reject) => setTimeout(() => reject(Object.assign(new Error("No answer within 10 seconds"), { safe: true })), TIMEOUT_MS))]);
}

/** A provider's own error text can echo request details, so only our own messages are shown. */
function failure(e: any, fallback: string): Check {
  return { ok: false, detail: e?.safe ? e.message : fallback };
}

async function stripeAccount(): Promise<Check> {
  if (!env.stripeSecretKey) return notSetUp("STRIPE_SECRET_KEY");
  try {
    const stripe = getStripe();
    const account = await withTimeout(stripe.accounts.retrieveCurrent());
    const mode = env.stripeSecretKey.includes("_live_") ? "live" : "test";
    const parts = [`Key accepted (${mode} mode)`];
    if (account.country) parts.push(`account in ${account.country}`);
    if (mode === "live" && !account.charges_enabled) parts.push("but Stripe has not enabled card payments yet: finish activation in the Stripe dashboard");
    if (mode === "live" && !account.payouts_enabled) parts.push("payouts to your bank are not enabled yet");
    return { ok: mode === "test" || !!account.charges_enabled, detail: parts.join(", ") + "." };
  } catch (e: any) {
    if (e?.type === "StripeAuthenticationError") return { ok: false, detail: "Stripe refused the secret key: copy it again from the Stripe dashboard (Developers → API keys)." };
    if (e?.type === "StripePermissionError") return { ok: false, detail: "The key works but may not read the account: use the secret key, not a restricted one." };
    return failure(e, "Could not reach Stripe.");
  }
}

async function stripeWebhook(): Promise<Check> {
  if (!env.stripeSecretKey) return notSetUp("STRIPE_SECRET_KEY (needed to look up the webhook)");
  const target = `${env.publicApiUrl}/api/v1/payments/webhook`;
  const last = await prisma.stripeEvent.findFirst({ orderBy: { processedAt: "desc" }, select: { processedAt: true } });
  const lastSeen = last ? ` Last payment event received ${last.processedAt.toISOString().slice(0, 16).replace("T", " ")} UTC.` : " No payment event has reached this server yet.";
  try {
    const list = await withTimeout(getStripe().webhookEndpoints.list({ limit: 100 }));
    const mine = list.data.filter((w) => w.url.replace(/\/+$/, "") === target);
    if (!mine.length) {
      return { ok: false, detail: `Stripe has no webhook pointing at ${target}. Add one in the Stripe dashboard (Developers → Webhooks) for payment_intent.succeeded and payment_intent.payment_failed.${lastSeen}` };
    }
    const enabled = mine.filter((w) => w.status === "enabled");
    const events = new Set(enabled.flatMap((w) => w.enabled_events));
    const missing = ["payment_intent.succeeded", "payment_intent.payment_failed"].filter((ev) => !events.has(ev) && !events.has("*"));
    if (!enabled.length) return { ok: false, detail: `The webhook for this server is disabled in Stripe.${lastSeen}` };
    if (missing.length) return { ok: false, detail: `The webhook does not send ${missing.join(" and ")}.${lastSeen}` };
    if (!env.stripeWebhookSecret) return { ok: false, detail: `The webhook exists, but STRIPE_WEBHOOK_SECRET is not set on Render, so every event is refused.${lastSeen}` };
    return { ok: true, detail: `Webhook found and enabled for the payment events.${lastSeen}` };
  } catch (e: any) {
    if (e?.type === "StripeAuthenticationError") return { ok: false, detail: "Stripe refused the secret key, so the webhook could not be checked." };
    return failure(e, "Could not ask Stripe about the webhook.");
  }
}

async function email(): Promise<Check> {
  try {
    const ok = await withTimeout(verifyEmailConnection());
    if (ok === null) return notSetUp("SMTP_HOST, SMTP_USER and SMTP_PASS");
    return { ok: true, detail: "Logged in to the mail server (no email was sent)." };
  } catch (e: any) {
    if (e?.code === "EAUTH") return { ok: false, detail: "The mail server refused the user name or password." };
    if (e?.code === "ECONNECTION" || e?.code === "ETIMEDOUT" || e?.code === "ESOCKET" || e?.code === "EDNS") return { ok: false, detail: "Could not connect to the mail server: check SMTP_HOST and SMTP_PORT." };
    return failure(e, "The mail server did not accept the connection.");
  }
}

async function sms(): Promise<Check> {
  const { TWILIO_ACCOUNT_SID: sid, TWILIO_AUTH_TOKEN: token, TWILIO_PHONE_NUMBER: from } = process.env;
  if (!sid || !token || !from) return notSetUp("TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN and TWILIO_PHONE_NUMBER");
  try {
    const res = await withTimeout(fetch(`https://api.twilio.com/2010-04-01/Accounts/${encodeURIComponent(sid)}.json`, {
      headers: { Authorization: "Basic " + Buffer.from(`${sid}:${token}`).toString("base64") },
    }));
    if (res.status === 401 || res.status === 404) return { ok: false, detail: "Twilio refused the account SID or auth token." };
    if (!res.ok) return { ok: false, detail: `Twilio answered ${res.status}.` };
    const account = (await res.json()) as { status?: string; type?: string };
    if (account.status !== "active") return { ok: false, detail: `The Twilio account is ${account.status ?? "not active"}.` };
    return { ok: true, detail: `Twilio account active${account.type === "Trial" ? " (trial: it can only text verified numbers)" : ""} (no SMS was sent).` };
  } catch (e: any) {
    return failure(e, "Could not reach Twilio.");
  }
}

async function push(): Promise<Check> {
  try {
    const ok = await withTimeout(verifyPushCredentials());
    if (ok === null) return notSetUp("FIREBASE_SERVICE_ACCOUNT");
    if (!ok) return { ok: false, detail: "FIREBASE_SERVICE_ACCOUNT is set but is not a valid service-account key (paste the whole JSON, or its base64)." };
    return { ok: true, detail: "Google accepted the Firebase service account (no notification was sent)." };
  } catch (e: any) {
    return failure(e, "Google refused the Firebase service account: generate a new key in Firebase (Project settings → Service accounts).");
  }
}

async function media(): Promise<Check> {
  try {
    const ok = await withTimeout(pingCloudinary());
    if (ok === null) return notSetUp("CLOUDINARY_CLOUD_NAME, CLOUDINARY_API_KEY and CLOUDINARY_API_SECRET");
    return { ok: true, detail: "Cloudinary accepted the account and key." };
  } catch (e: any) {
    return failure(e, "Could not reach Cloudinary.");
  }
}

function googleSignIn(): Check {
  if (!env.googleClientId) return notSetUp("GOOGLE_CLIENT_ID");
  if (!/^[0-9]+-[a-z0-9]+\.apps\.googleusercontent\.com$/.test(env.googleClientId)) {
    return { ok: false, detail: "GOOGLE_CLIENT_ID does not look like a Google OAuth client ID (…apps.googleusercontent.com)." };
  }
  return { ok: true, detail: "Client ID looks right. Google has no test call: the first Google sign-in confirms it (use the web client ID from Firebase)." };
}

function phoneSignIn(): Check {
  if (!process.env.FIREBASE_PROJECT_ID) return notSetUp("FIREBASE_PROJECT_ID");
  return { ok: true, detail: `Project ${process.env.FIREBASE_PROJECT_ID}. Real SMS also need the Blaze plan and the app's SHA fingerprints in Firebase; the first phone sign-in confirms it.` };
}

let cache: { at: number; result: Record<string, Check> } | null = null;

export async function runConnectionChecks(): Promise<Record<string, Check>> {
  // One run at a time per half minute: the button cannot be used to hammer the providers
  if (cache && Date.now() - cache.at < 30_000) return cache.result;
  const [payments, paymentWebhook, emailCheck, smsCheck, pushCheck, mediaCheck] = await Promise.all([
    stripeAccount(), stripeWebhook(), email(), sms(), push(), media(),
  ]);
  const result = {
    payments, paymentWebhook, email: emailCheck, sms: smsCheck, pushNotifications: pushCheck, photosAndVideos: mediaCheck,
    googleSignIn: googleSignIn(), phoneSignIn: phoneSignIn(),
  };
  cache = { at: Date.now(), result };
  return result;
}

export async function postConnectionCheck(_req: Request, res: Response) {
  try {
    res.json({ ok: true, checkedAt: new Date().toISOString(), checks: await runConnectionChecks() });
  } catch (e) { sendError(res, e); }
}
