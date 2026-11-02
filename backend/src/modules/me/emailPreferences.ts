import { Router, Request, Response } from "express";
import pino from "pino";
import { prisma } from "../../lib/prisma";
import { verifyUnsubscribeToken } from "../../lib/unsubscribe";
import { escapeHtml } from "../../services/notificationDeliveryService";
import { forgetSessionState } from "../../middleware/auth";

const logger = pino({ name: "email-unsubscribe" });

/**
 * Unsubscribe from optional emails (since 2.16.0), from the link in every optional email:
 *  - GET  /email/unsubscribe?t=…  a small bilingual page with one button (GET never changes anything, because mail
 *    scanners open links);
 *  - POST /email/unsubscribe?t=…  the RFC 8058 one-click unsubscribe (the mail app posts "List-Unsubscribe=One-Click")
 *    and the page's button. Sets User.emailMarketingOptOutAt once; transactional emails are not affected.
 * The token is an HMAC of the user id (lib/unsubscribe.ts) and does not expire. Also under /api/v1.
 */
export const unsubscribeRoutes = Router();

const CSP = "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'";

function page(res: Response, status: number, body: string) {
  res.status(status);
  res.set("Cache-Control", "no-store");
  res.set("Content-Security-Policy", CSP);
  res.set("X-Robots-Tag", "noindex");
  res.set("Referrer-Policy", "no-referrer");
  res.type("html").send(`<!doctype html><html lang="fi"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Malvoya – Sähköpostit / Emails</title>
<style>
body{margin:0;background:#F6F3EE;color:#17131C;font:16px/1.6 -apple-system,system-ui,"Segoe UI",sans-serif}
main{max-width:560px;margin:0 auto;padding:40px 20px 64px}
h1{font-size:24px;line-height:1.25;margin:0 0 12px}
.card{background:#fff;border:1px solid #E6E1EA;border-radius:18px;padding:22px}
p{margin:0 0 12px}.en{color:#5b5363}
button{font:inherit;font-weight:700;background:#6D2E8C;color:#fff;border:0;border-radius:999px;padding:14px 22px;min-height:48px;cursor:pointer;width:100%}
</style></head><body><main><div class="card">${body}</div></main></body></html>`);
}

const INVALID = `<h1>Linkki ei kelpaa / This link is not valid</h1>
<p>Avaa linkki uudelleen sähköpostista tai muuta asetusta Malvoya-sovelluksessa: Profiili → Tietosuoja → Sähköpostiasetukset.</p>
<p class="en">Open the link from the email again, or change the setting in the Malvoya app: Profile → Privacy → Email preferences.</p>`;

const DONE = `<h1>Tilaus peruttu / You are unsubscribed</h1>
<p>Emme lähetä sinulle enää valinnaisia sähköposteja (kuten ilmoituksia Malvoyan avautumisesta lähelläsi). Tilauksiin, tiliisi ja sopimuksiin liittyvät palveluviestit tulevat edelleen.</p>
<p class="en">We will no longer send you optional emails (such as news that Malvoya opened near you). Service messages about your orders, account and agreements still arrive.</p>
<p>Voit ottaa ne takaisin käyttöön sovelluksessa: Profiili → Tietosuoja → Sähköpostiasetukset.</p>
<p class="en">You can switch them back on in the app: Profile → Privacy → Email preferences.</p>`;

async function userOf(req: Request) {
  const id = verifyUnsubscribeToken(req.query.t);
  if (!id) return null;
  return prisma.user.findUnique({ where: { id }, select: { id: true, emailMarketingOptOutAt: true } });
}

function getPage(path: string) {
  return async (req: Request, res: Response) => {
    try {
      const u = await userOf(req);
      if (!u) return page(res, 400, INVALID);
      if (u.emailMarketingOptOutAt) return page(res, 200, DONE);
      const action = `${path}?t=${encodeURIComponent(String(req.query.t))}`;
      page(res, 200, `<h1>Peru valinnaiset sähköpostit? / Unsubscribe from optional emails?</h1>
<p>Lopetamme valinnaiset sähköpostit (kuten ilmoitukset Malvoyan avautumisesta lähelläsi). Tilauksiin, tiliisi ja sopimuksiin liittyvät palveluviestit tulevat edelleen.</p>
<p class="en">We will stop optional emails (such as news that Malvoya opened near you). Service messages about your orders, account and agreements still arrive.</p>
<form method="post" action="${escapeHtml(action)}"><button type="submit">Peru tilaus / Unsubscribe</button></form>`);
    } catch (e: any) {
      logger.error({ err: e?.message }, "Unsubscribe page failed");
      page(res, 500, "<h1>Jokin meni vikaan / Something went wrong</h1><p>Yritä hetken päästä uudelleen. / Please try again in a moment.</p>");
    }
  };
}

/** One click (RFC 8058) or the page's button: the request body is not needed, the signed token says who. */
async function unsubscribe(req: Request, res: Response) {
  try {
    const u = await userOf(req);
    if (!u) return page(res, 400, INVALID);
    if (!u.emailMarketingOptOutAt) {
      await prisma.user.updateMany({ where: { id: u.id, emailMarketingOptOutAt: null }, data: { emailMarketingOptOutAt: new Date() } });
      forgetSessionState(u.id);
    }
    page(res, 200, DONE);
  } catch (e: any) {
    logger.error({ err: e?.message }, "Unsubscribe failed");
    page(res, 500, "<h1>Jokin meni vikaan / Something went wrong</h1><p>Yritä hetken päästä uudelleen. / Please try again in a moment.</p>");
  }
}

for (const path of ["/email/unsubscribe", "/api/v1/email/unsubscribe"]) {
  unsubscribeRoutes.get(path, getPage(path));
  unsubscribeRoutes.post(path, unsubscribe);
}
