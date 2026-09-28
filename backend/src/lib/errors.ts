import { Response } from "express";
import pino from "pino";

const logger = pino({ name: "api" });

/** An error whose message is safe to show to the user, with the HTTP status to send. */
export class ApiError extends Error {
  constructor(message: string, public status = 400) {
    super(message);
  }
}

export function sendError(res: Response, e: any) {
  if (typeof e?.status === "number" && e.status < 500) return res.status(e.status).json({ ok: false, error: e.message });
  if (typeof e?.type === "string" && e.type.startsWith("Stripe")) {
    logger.error({ err: e?.message, code: e?.code }, "Stripe error");
    return res.status(502).json({ ok: false, error: "The payment provider did not respond. Please try again." });
  }
  logger.error({ err: e?.message, stack: e?.stack }, "Unhandled error");
  return res.status(e?.status === 503 ? 503 : 500).json({ ok: false, error: e?.status === 503 ? e.message : "Something went wrong" });
}

export function positiveId(value: unknown): number | null {
  const n = Number(value);
  return Number.isInteger(n) && n > 0 ? n : null;
}
