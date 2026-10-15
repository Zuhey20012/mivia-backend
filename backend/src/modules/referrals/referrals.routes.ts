import { Router, Response } from "express";
import { auth, requireRole, AuthRequest } from "../../middleware/auth";
import { sendError } from "../../lib/errors";
import { referralInfo } from "./referrals.service";

const router = Router();

// The customer's invite code (created on first call), its share link, what both sides get, and how many
// friends have used it. `enabled: false` while referrals are switched off (REFERRAL_DISCOUNT_CENTS = 0).
router.get("/me/referral", auth, requireRole("CUSTOMER"), async (req: AuthRequest, res: Response) => {
  try {
    res.json({ ok: true, ...(await referralInfo(req.user!.id)) });
  } catch (e) { sendError(res, e); }
});

export default router;
