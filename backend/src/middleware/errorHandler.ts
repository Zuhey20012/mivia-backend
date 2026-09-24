import { Request, Response, NextFunction } from "express";

export function errorHandler(err: any, _req: Request, res: Response, _next: NextFunction) {
  // Malformed JSON bodies and oversized payloads are client errors, not crashes
  if (err?.type === "entity.parse.failed") return res.status(400).json({ ok: false, error: "Invalid JSON body" });
  if (err?.type === "entity.too.large") return res.status(413).json({ ok: false, error: "Request body too large" });
  console.error(err);
  res.status(500).json({ ok: false, error: "Internal server error" });
}
