import { Response } from "express";
import pino from "pino";
import { reportError } from "./sentry";
import { currentRequestId } from "./requestContext";
import { localeFromHeader } from "./i18n";

const logger = pino({ name: "api" });

/** An error whose message is safe to show to the user, with the HTTP status to send. */
export class ApiError extends Error {
  /** Extra fields for the error body, e.g. { code: "PRODUCT_LOCKED" } or field-level issues */
  extra?: Record<string, unknown>;
  constructor(message: string, public status = 400) {
    super(message);
  }
}

export function sendError(res: Response, e: any) {
  if (typeof e?.status === "number" && e.status < 500) {
    // Field-level errors (catalog FieldsError) build their own body in the request's language
    if (typeof e.body === "function") return res.status(e.status).json(e.body(localeFromHeader(res.req?.headers["accept-language"]) ?? "en"));
    return res.status(e.status).json({ ok: false, error: e.message, ...(e.extra ?? {}) });
  }
  // A feature switched off on this server (e.g. live video without LiveKit, 503 LIVE_OFF): safe to show, not a bug
  if (e instanceof ApiError && e.status === 503) return res.status(503).json({ ok: false, error: e.message, ...(e.extra ?? {}) });
  if (typeof e?.type === "string" && e.type.startsWith("Stripe")) {
    logger.error({ reqId: currentRequestId(), err: e?.message, code: e?.code }, "Stripe error");
    reportError(e, { tags: { area: "stripe" } });
    return res.status(502).json({ ok: false, error: "The payment provider did not respond. Please try again." });
  }
  logger.error({ reqId: currentRequestId(), err: e?.message, stack: e?.stack }, "Unhandled error");
  if (e?.status !== 503) reportError(e);
  return res.status(e?.status === 503 ? 503 : 500).json({ ok: false, error: e?.status === 503 ? e.message : "Something went wrong" });
}

export function positiveId(value: unknown): number | null {
  const n = Number(value);
  return Number.isInteger(n) && n > 0 ? n : null;
}
