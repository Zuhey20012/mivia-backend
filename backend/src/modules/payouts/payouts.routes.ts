import { Router, Response, Request } from "express";
import { auth, requireRole, AuthRequest } from "../../middleware/auth";
import { sendError } from "../../lib/errors";
import * as payouts from "./payouts.service";
import { requireRecentAuth } from "../auth/accountSecurity";
import { prisma } from "../../lib/prisma";
import { localeOfUser } from "../../lib/i18n";
import { sendPayoutLinkEmail } from "../../services/notificationDeliveryService";

/** The owner hears about every payout link (2.16): a stolen session should not change bank details unnoticed. */
function tellOwner(userId: number, kind: "onboarding" | "dashboard") {
  prisma.user.findUnique({ where: { id: userId }, select: { email: true } })
    .then(async (u) => { if (u) await sendPayoutLinkEmail(u.email, kind, await localeOfUser(userId)); })
    .catch(() => {});
}

const router = Router();
const partners = [auth, requireRole("VENDOR", "COURIER")];

// Payout links need the password again within 10 minutes (or a two-step session): 403 REAUTH_REQUIRED (2.16)
router.post("/payouts/onboarding", ...partners, requireRecentAuth, async (req: AuthRequest, res: Response) => {
  try {
    const link = await payouts.startOnboarding(req.user!);
    tellOwner(req.user!.id, "onboarding");
    res.json({ ok: true, ...link });
  } catch (e) { sendError(res, e); }
});

router.get("/payouts/status", ...partners, async (req: AuthRequest, res: Response) => {
  try {
    res.json({ ok: true, ...(await payouts.refreshStatus(req.user!)) });
  } catch (e) { sendError(res, e); }
});

router.post("/payouts/dashboard", ...partners, requireRecentAuth, async (req: AuthRequest, res: Response) => {
  try {
    const link = await payouts.dashboardLink(req.user!);
    tellOwner(req.user!.id, "dashboard");
    res.json({ ok: true, ...link });
  } catch (e) { sendError(res, e); }
});

router.get("/payouts", ...partners, async (req: AuthRequest, res: Response) => {
  try {
    res.json({ ok: true, ...(await payouts.listFor(req.user!)) });
  } catch (e) { sendError(res, e); }
});

// Pages Stripe sends people back to after onboarding (opened in the phone's browser)
function page(res: Response, title: string, body: string) {
  res.set("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'");
  res.type("html").send(`<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${title}</title></head>
<body style="margin:0;font-family:-apple-system,system-ui,sans-serif;background:#F6F3EE;color:#17131C;display:flex;min-height:100vh;align-items:center;justify-content:center">
<main style="max-width:380px;padding:28px;text-align:center"><h1 style="font-size:22px">${title}</h1><p style="color:#5b5360;line-height:1.5">${body}</p></main></body></html>`);
}

router.get("/payouts/return", (_req: Request, res: Response) =>
  page(res, "All set", "Your payout details were sent to Stripe. Go back to the Malvoya app — it shows when payouts are switched on."));

router.get("/payouts/refresh", (_req: Request, res: Response) =>
  page(res, "This link has expired", "Go back to the Malvoya app and tap <b>Set up payouts</b> again to continue."));

export default router;
