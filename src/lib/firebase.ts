import { App, cert, getApps, initializeApp, ServiceAccount } from "firebase-admin/app";
import { getAuth, DecodedIdToken } from "firebase-admin/auth";
import { env } from "../config/env";

export class FirebaseNotConfiguredError extends Error {
  constructor() {
    super("Firebase auth is not configured");
  }
}

let app: App | null = null;

function parseServiceAccount(raw: string): ServiceAccount {
  const json = raw.trim().startsWith("{") ? raw : Buffer.from(raw, "base64").toString("utf8");
  return JSON.parse(json) as ServiceAccount;
}

export function isFirebaseConfigured(): boolean {
  return Boolean(env.firebaseProjectId || env.firebaseServiceAccount);
}

function getFirebaseApp(): App {
  if (app) return app;
  if (!isFirebaseConfigured()) throw new FirebaseNotConfiguredError();

  const existing = getApps().find((a) => a.name === "mivia-auth");
  if (existing) return (app = existing);

  app = env.firebaseServiceAccount
    ? initializeApp(
        {
          credential: cert(parseServiceAccount(env.firebaseServiceAccount)),
          projectId: env.firebaseProjectId || undefined,
        },
        "mivia-auth",
      )
    : initializeApp({ projectId: env.firebaseProjectId }, "mivia-auth");
  return app;
}

// Verifies signature, expiry, issuer and audience (project ID) of a Firebase ID token.
// Revocation is only checked when a service account is configured, since it needs Admin API access.
export async function verifyFirebaseIdToken(idToken: string): Promise<DecodedIdToken> {
  const checkRevoked = Boolean(env.firebaseServiceAccount);
  return getAuth(getFirebaseApp()).verifyIdToken(idToken, checkRevoked);
}
