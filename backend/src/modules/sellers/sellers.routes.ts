import { Router, Response } from "express";
import { auth, requireRole, AuthRequest } from "../../middleware/auth";
import { sendError } from "../../lib/errors";
import { getMyTaxInfo, putMyTaxInfo, taxInfoSchema } from "./taxInfo";
import { currentMonth, myStoreId, statementHtml, storeStatement } from "./statements";

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

export default router;
