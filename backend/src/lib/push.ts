import { initializeApp, cert } from "firebase-admin/app";
import { getMessaging as firebaseMessaging, Messaging } from "firebase-admin/messaging";
import pino from "pino";
import { env } from "../config/env";
import { prisma } from "./prisma";

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
  title: string;
  body: string;
  /** Deep-link data for the app, e.g. { type: "order", orderId: "12" }. Values must be strings. */
  data?: Record<string, string>;
};

export async function pushToUser(userId: number, msg: PushMessage) {
  return pushToUsers([userId], msg);
}

export async function pushToUsers(userIds: number[], msg: PushMessage) {
  const m = pushClient();
  if (!m || !userIds.length) return;
  const devices = await prisma.deviceToken.findMany({ where: { userId: { in: userIds } }, select: { token: true } });
  if (!devices.length) return;

  const tokens = devices.map((d) => d.token);
  try {
    const res = await m.sendEachForMulticast({
      tokens,
      notification: { title: msg.title.slice(0, 120), body: msg.body.slice(0, 240) },
      data: msg.data,
      android: { priority: "high", notification: { channelId: "orders" } },
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
