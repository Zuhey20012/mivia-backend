"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.FirebaseNotConfiguredError = void 0;
exports.isFirebaseConfigured = isFirebaseConfigured;
exports.verifyFirebaseIdToken = verifyFirebaseIdToken;
const app_1 = require("firebase-admin/app");
const auth_1 = require("firebase-admin/auth");
const env_1 = require("../config/env");
class FirebaseNotConfiguredError extends Error {
    constructor() {
        super("Firebase auth is not configured");
    }
}
exports.FirebaseNotConfiguredError = FirebaseNotConfiguredError;
let app = null;
function parseServiceAccount(raw) {
    const json = raw.trim().startsWith("{") ? raw : Buffer.from(raw, "base64").toString("utf8");
    return JSON.parse(json);
}
function isFirebaseConfigured() {
    return Boolean(env_1.env.firebaseProjectId || env_1.env.firebaseServiceAccount);
}
function getFirebaseApp() {
    if (app)
        return app;
    if (!isFirebaseConfigured())
        throw new FirebaseNotConfiguredError();
    const existing = (0, app_1.getApps)().find((a) => a.name === "mivia-auth");
    if (existing)
        return (app = existing);
    app = env_1.env.firebaseServiceAccount
        ? (0, app_1.initializeApp)({
            credential: (0, app_1.cert)(parseServiceAccount(env_1.env.firebaseServiceAccount)),
            projectId: env_1.env.firebaseProjectId || undefined,
        }, "mivia-auth")
        : (0, app_1.initializeApp)({ projectId: env_1.env.firebaseProjectId }, "mivia-auth");
    return app;
}
// Verifies signature, expiry, issuer and audience (project ID) of a Firebase ID token.
// Revocation is only checked when a service account is configured, since it needs Admin API access.
async function verifyFirebaseIdToken(idToken) {
    const checkRevoked = Boolean(env_1.env.firebaseServiceAccount);
    return (0, auth_1.getAuth)(getFirebaseApp()).verifyIdToken(idToken, checkRevoked);
}
