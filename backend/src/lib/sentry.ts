import { scale } from "../config/scale";
import { currentRequestId } from "./requestContext";

/**
 * Optional error tracking (SENTRY_DSN). Without the DSN the SDK is never even loaded. Everything sent is scrubbed of
 * personal data and secrets first: no email addresses, phone numbers, tokens, sign-in/pickup codes, request bodies,
 * cookies or IP addresses (GDPR data minimisation; Sentry's EU region is recommended, see the scaling plan).
 */
type SentryModule = typeof import("@sentry/node");
let sentry: SentryModule | null = null;

const EMAIL = /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g;
const JWT = /\beyJ[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{5,}\b/g;
const BEARER = /\b(Bearer|Basic)\s+[A-Za-z0-9._~+/=-]+/gi;
const STRIPE_SECRET = /\b(sk|rk|whsec|pk)_(live|test)_[A-Za-z0-9]+\b|\bwhsec_[A-Za-z0-9]+\b/g;
const PHONE = /\+?\d[\d\s().-]{7,}\d/g;
const CODE = /\b\d{4,8}\b/g; // one-time codes, pickup codes (also blurs long numbers, which is fine for error reports)
const SENSITIVE_KEY = /pass|secret|token|authorization|cookie|signature|email|phone|code|otp|pin|tin|iban|address|consumerkey|consumersecret|clientsecret|apikey|api_key|dsn/i;
const SAFE_KEYS = new Set(["statusCode", "status_code", "errorCode", "code_location"]);

export function scrubString(value: string): string {
  return value
    .replace(JWT, "[token]")
    .replace(BEARER, "$1 [token]")
    .replace(STRIPE_SECRET, "[secret]")
    .replace(EMAIL, "[email]")
    .replace(PHONE, "[phone]")
    .replace(CODE, "[number]");
}

/** Deep copy with sensitive keys removed and personal data in strings masked. */
export function scrub<T>(value: T, depth = 0): T {
  if (depth > 8) return "[depth]" as unknown as T;
  if (typeof value === "string") return scrubString(value) as unknown as T;
  if (Array.isArray(value)) return value.map((v) => scrub(v, depth + 1)) as unknown as T;
  if (value && typeof value === "object") {
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
      out[k] = SENSITIVE_KEY.test(k) && !SAFE_KEYS.has(k) && typeof v !== "number" ? "[Filtered]" : scrub(v, depth + 1);
    }
    return out as T;
  }
  return value;
}

function scrubUrl(url: string | undefined) {
  if (!url) return url;
  // Query strings carry signed-link signatures, cursors and search terms: drop them
  return scrubString(url.split("?")[0]);
}

function packageVersion() {
  try { return JSON.parse(require("fs").readFileSync(require("path").join(__dirname, "..", "..", "package.json"), "utf8")).version; } catch { return "unknown"; }
}

export function initSentry() {
  if (!scale.sentry.dsn || sentry) return;
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const S: SentryModule = require("@sentry/node");
  S.init({
    dsn: scale.sentry.dsn,
    environment: scale.sentry.environment,
    release: `malvoya-api@${packageVersion()}`,
    sendDefaultPii: false,
    tracesSampleRate: scale.sentry.tracesSampleRate,
    maxBreadcrumbs: 30,
    beforeSend(event) {
      if (event.user) event.user = event.user.id !== undefined ? { id: event.user.id } : undefined;
      if (event.request) {
        const headers = event.request.headers || {};
        event.request = {
          method: event.request.method,
          url: scrubUrl(event.request.url),
          headers: Object.fromEntries(Object.entries(headers).filter(([k]) => ["user-agent", "content-type", "x-request-id"].includes(k.toLowerCase()))),
        };
      }
      if (event.message) event.message = scrubString(event.message);
      for (const ex of event.exception?.values ?? []) {
        if (ex.value) ex.value = scrubString(ex.value);
        for (const frame of ex.stacktrace?.frames ?? []) delete frame.vars;
      }
      if (event.extra) event.extra = scrub(event.extra);
      if (event.contexts) event.contexts = scrub(event.contexts);
      if (event.breadcrumbs) event.breadcrumbs = event.breadcrumbs.map((b) => ({ ...b, message: b.message ? scrubString(b.message) : b.message, data: b.data ? scrubBreadcrumbData(b.data) : b.data }));
      return event;
    },
    beforeBreadcrumb(b) {
      if (b.category === "console") return null; // console lines may contain anything
      return { ...b, message: b.message ? scrubString(b.message) : b.message, data: b.data ? scrubBreadcrumbData(b.data) : b.data };
    },
  });
  sentry = S;
}

function scrubBreadcrumbData(data: Record<string, any>) {
  const copy = scrub({ ...data });
  if (typeof data.url === "string") copy.url = scrubUrl(data.url);
  return copy;
}

export function sentryEnabled() {
  return !!sentry;
}

/** Reports an unexpected error (5xx, failed job). No-op without SENTRY_DSN. */
export function reportError(err: unknown, context: { tags?: Record<string, string>; extra?: Record<string, unknown> } = {}) {
  if (!sentry) return;
  const requestId = currentRequestId();
  sentry.withScope((scope) => {
    if (requestId) scope.setTag("request_id", requestId);
    for (const [k, v] of Object.entries(context.tags ?? {})) scope.setTag(k, v);
    if (context.extra) scope.setExtras(scrub(context.extra));
    sentry!.captureException(err);
  });
}

/** Express error handler that reports to Sentry (mounted before ours). */
export function setupSentryErrorHandler(app: import("express").Express) {
  if (sentry) sentry.setupExpressErrorHandler(app);
}

export async function flushSentry(timeoutMs = 2_000) {
  if (sentry) await sentry.flush(timeoutMs).catch(() => false);
}
