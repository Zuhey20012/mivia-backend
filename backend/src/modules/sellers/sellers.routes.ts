import { Router, Response } from "express";
import { auth, requireRole, AuthRequest } from "../../middleware/auth";
import { sendError } from "../../lib/errors";
import { getMyTaxInfo, putMyTaxInfo, taxInfoSchema } from "./taxInfo";
import { currentMonth, myStoreId, statementHtml, storeStatement } from "./statements";
import { checkStatementLink, statementLink } from "./statementLinks";

/** The store's own tax data (DAC7) and monthly statements. Mounted at /api/v1/stores. */
const router = Router();
const owner = [auth, requireRole("VENDOR")];

router.get("/my/tax-info", ...owner, async (req: AuthRequest, res: Response) => {
  try {
    res.json({ ok: true, ...(await getMyTaxInfo(req.user!.id)) });
  } catch (e) { sendError(res, e); }
});

router.put("/my/tax-info", ...owner, async (req: AuthRequest, res: Response) => {
  const body = taxInfoSchema.safeParse(req.body);
  if (!body.success) {
    return res.status(400).json({ ok: false, error: body.error.issues[0]?.message ?? "Check the details", errors: body.error.flatten() });
  }
  try {
    res.json({ ok: true, ...(await putMyTaxInfo(req.user!.id, body.data)) });
  } catch (e) { sendError(res, e); }
});

router.get("/my/statements", ...owner, async (req: AuthRequest, res: Response) => {
  try {
    const month = typeof req.query.month === "string" && req.query.month ? req.query.month : currentMonth();
    res.json({ ok: true, ...(await storeStatement(await myStoreId(req.user!.id), month)) });
  } catch (e) { sendError(res, e); }
});

// Printable statement (the app fetches it with its bearer token and shows or prints it)
router.get("/my/statements/:month(\\d{4}-\\d{2}).html", ...owner, async (req: AuthRequest, res: Response) => {
  try {
    const html = await statementHtml(await myStoreId(req.user!.id), req.params.month);
    res.set("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'");
    res.set("Cache-Control", "private, no-store");
    res.type("html").send(html);
  } catch (e) { sendError(res, e); }
});

// A 10-minute signed link to the printable statement, for opening it in a normal browser
router.get("/my/statements/:month(\\d{4}-\\d{2})/link", ...owner, async (req: AuthRequest, res: Response) => {
  try {
    res.json({ ok: true, ...statementLink(await myStoreId(req.user!.id), req.params.month) });
  } catch (e) { sendError(res, e); }
});

// The signed link itself (no token: the HMAC signature and expiry in the query are the permission)
router.get("/statements/:storeId(\\d+)/:month(\\d{4}-\\d{2}).html", async (req: AuthRequest, res: Response) => {
  const storeId = Number(req.params.storeId);
  const check = checkStatementLink(storeId, req.params.month, req.query.exp, req.query.sig);
  res.set("Cache-Control", "private, no-store");
  res.set("Referrer-Policy", "no-referrer");
  if (check !== "ok") {
    return res.status(403).type("text").send(check === "expired"
      ? "This link has expired. Open the statement again from Malvoya Store. / Linkki on vanhentunut. Avaa raportti uudelleen Malvoya Storesta."
      : "This link is not valid. / Linkki ei kelpaa.");
  }
  try {
    const html = await statementHtml(storeId, req.params.month);
    res.set("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'");
    res.type("html").send(html);
  } catch (e) { sendError(res, e); }
});

export default router;
