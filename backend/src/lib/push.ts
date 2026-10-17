import { initializeApp, cert } from "firebase-admin/app";
import { getMessaging as firebaseMessaging, Messaging } from "firebase-admin/messaging";
import pino from "pino";
import { env } from "../config/env";
import { prisma } from "./prisma";
import { Locale, Text, asLocale, pick } from "./i18n";

const logger = pino({ name: "push" });

/**
 * Firebase Cloud Messaging. Sending needs a service-account key (FIREBASE_SERVICE_ACCOUNT);
 * without it pushes are skipped and the apps still get live updates over the socket.
 * Only service messages are sent (order, delivery, payout) — never marketing.
 */
let messaging: Messaging | null | undefined;

function pushClient(): Messaging | null {
  if (messaging !== undefined) return messaging;
  messaging = null;
  if (!env.firebaseServiceAccount) return messaging;
  try {
    const raw = env.firebaseServiceAccount.trim().startsWith("{")
      ? env.firebaseServiceAccount
      : Buffer.from(env.firebaseServiceAccount, "base64").toString("utf8");
    const app = initializeApp({ credential: cert(JSON.parse(raw)) }, "push");
    messaging = firebaseMessaging(app);
  } catch (err: any) {
    logger.error({ err: err?.message }, "FIREBASE_SERVICE_ACCOUNT is invalid; push disabled");
  }
  return messaging;
}

export function pushConfigured() {
  return !!pushClient();
}

export type PushMessage = {
  /** Plain text, or { en, fi }: each device gets its user's language (User.locale, English by default). */
  title: Text;
  body: Text;
  /** Deep-link data for the app, e.g. { type: "order", orderId: "12" }. Values must be strings. */
  data?: Record<string, string>;
  /** Android channel: "new_orders" is the loud one in the store app (new and waiting orders). */
  channel?: "orders" | "new_orders";
};

export async function pushToUser(userId: number, msg: PushMessage) {
  return pushToUsers([userId], msg);
}

export async function pushToUsers(userIds: number[], msg: PushMessage) {
  const m = pushClient();
  if (!m || !userIds.length) return;
  const devices = await prisma.deviceToken.findMany({
    where: { userId: { in: userIds } },
    select: { token: true, user: { select: { locale: true } } },
  });
  if (!devices.length) return;

  // One send per language; FCM takes at most 500 tokens per multicast
  for (const locale of ["fi", "en"] as Locale[]) {
    const tokens = devices.filter((d) => asLocale(d.user.locale) === locale).map((d) => d.token);
    for (let i = 0; i < tokens.length; i += 500) {
      await sendBatch(m, tokens.slice(i, i + 500), msg, locale);
    }
  }
}

async function sendBatch(m: Messaging, tokens: string[], msg: PushMessage, locale: Locale) {
  try {
    const res = await m.sendEachForMulticast({
      tokens,
      notification: { title: pick(msg.title, locale).slice(0, 120), body: pick(msg.body, locale).slice(0, 240) },
      data: msg.data,
      android: { priority: "high", notification: { channelId: msg.channel ?? "orders" } },
      apns: { payload: { aps: { sound: "default" } } },
    });
    // Forget tokens that belong to uninstalled apps
    const dead = res.responses
      .map((r, i) => (!r.success && isDeadToken(r.error?.code) ? tokens[i] : null))
      .filter((t): t is string => !!t);
    if (dead.length) await prisma.deviceToken.deleteMany({ where: { token: { in: dead } } });
  } catch (err: any) {
    logger.warn({ err: err?.message }, "Push send failed");
  }
}

function isDeadToken(code?: string) {
  return code === "messaging/registration-token-not-registered" || code === "messaging/invalid-registration-token";
}
