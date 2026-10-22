import crypto from "crypto";
import { AsyncLocalStorage } from "async_hooks";
import type { IncomingMessage, ServerResponse } from "http";
import type { Request, Response, NextFunction } from "express";

/** The request being handled, available to any code running for it (logs and error reports carry its id). */
const storage = new AsyncLocalStorage<{ requestId: string }>();

export function currentRequestId(): string | undefined {
  return storage.getStore()?.requestId;
}

// A caller's X-Request-Id is reused only when it is a plain token (no spaces or control characters: no log injection)
const VALID_ID = /^[A-Za-z0-9._:-]{8,128}$/;

/** pino-http genReqId: the incoming X-Request-Id when well-formed, else a new UUID; echoed as X-Request-Id. */
export function genReqId(req: IncomingMessage, res: ServerResponse): string {
  const incoming = req.headers["x-request-id"];
  const id = typeof incoming === "string" && VALID_ID.test(incoming) ? incoming : crypto.randomUUID();
  res.setHeader("X-Request-Id", id);
  return id;
}

/** Runs the rest of the request inside its context (after pino-http has assigned req.id). */
export function requestContextMiddleware(req: Request, _res: Response, next: NextFunction) {
  storage.run({ requestId: String((req as any).id ?? "") }, next);
}
