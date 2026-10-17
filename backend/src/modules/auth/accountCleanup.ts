import { initializeApp, cert, getApps, App } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import pino from "pino";
import { env } from "../../config/env";
import { deleteByPrefix, mediaConfigured } from "../../lib/cloudinary";

const logger = pino({ name: "account-cleanup" });

/**
 * Clean-up outside our database when an account is deleted. Each step is best effort: a failure is logged and
 * never blocks the deletion itself (the account is already anonymised by then).
 */

let adminApp: App | null | undefined;

/** Firebase Admin with the service-account key (FIREBASE_SERVICE_ACCOUNT); null when it is not configured. */
function firebaseAdmin(): App | null {
  if (adminApp !== undefined) return adminApp;
  adminApp = null;
  if (!env.firebaseServiceAccount) return adminApp;
  try {
    const existing = getApps().find((a) => a.name === "account-cleanup");
    const raw = env.firebaseServiceAccount.trim().startsWith("{")
      ? env.firebaseServiceAccount
      : Buffer.from(env.firebaseServiceAccount, "base64").toString("utf8");
    adminApp = existing ?? initializeApp({ credential: cert(JSON.parse(raw)) }, "account-cleanup");
  } catch (err: any) {
    logger.error({ err: err?.message }, "FIREBASE_SERVICE_ACCOUNT is invalid; Firebase users are not deleted");
  }
  return adminApp;
}

/** Deletes the Firebase Authentication user(s) behind a phone or email sign-in, when Firebase Admin is configured. */
export async function deleteFirebaseUser(identity: { email: string | null; phone: string | null }) {
  const app = firebaseAdmin();
  if (!app) return { configured: false, deleted: 0 };
  const auth = getAuth(app);
  const uids = new Set<string>();
  const lookups: Promise<void>[] = [];
  if (identity.phone && /^\+\d{7,15}$/.test(identity.phone)) {
    lookups.push(auth.getUserByPhoneNumber(identity.phone).then((u) => { uids.add(u.uid); }).catch(() => {}));
  }
  if (identity.email && !identity.email.endsWith("@phone.malvoya.app")) {
    lookups.push(auth.getUserByEmail(identity.email).then((u) => { uids.add(u.uid); }).catch(() => {}));
  }
  await Promise.all(lookups);
  let deleted = 0;
  for (const uid of uids) {
    try {
      await auth.deleteUser(uid);
      deleted++;
    } catch (err: any) {
      logger.error({ err: err?.code ?? err?.message }, "Could not delete the Firebase user");
    }
  }
  return { configured: true, deleted };
}

/** A deleted store's photos, videos, store pictures and drops on Cloudinary; plus the user's avatar folder. */
export async function deleteStoreMedia(storeId: number | null, userId: number) {
  if (!mediaConfigured()) return;
  const jobs: [string, "image" | "video"][] = [[`malvoya/avatars/u${userId}/`, "image"]];
  if (storeId) {
    jobs.push(
      [`malvoya/products/s${storeId}/`, "image"], [`malvoya/products/s${storeId}/`, "video"],
      [`malvoya/stores/s${storeId}/`, "image"],
      [`malvoya/drops/s${storeId}/`, "image"], [`malvoya/drops/s${storeId}/`, "video"],
    );
  }
  for (const [prefix, type] of jobs) {
    await deleteByPrefix(prefix, type).catch((err) => logger.error({ prefix, type, err: err?.message }, "Could not delete media"));
  }
}
