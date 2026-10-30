import { Router, Request, Response, urlencoded } from "express";
import rateLimit from "express-rate-limit";
import { z } from "zod";
import { prisma } from "../../lib/prisma";
import { escapeHtml, sendEmail, sendSupportAck } from "../../services/notificationDeliveryService";
import { localeFromHeader, Locale } from "../../lib/i18n";
import { rateLimitStore } from "../../middleware/rateLimiter";

/**
 * Public contact form at /contact (since 2.13.0): the address the legal texts give for privacy requests, withdrawal
 * notices, seller complaints and the Digital Services Act point of contact, while Malvoya has no mailbox on its own
 * domain. Server-rendered, no scripts; requests land in the same queue as in-app support (admin panel → Support,
 * app "web") and are emailed to SUPPORT_EMAIL when it is set.
 */
export const contactRoutes = Router();

const CSP = "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'";
const SUPPORT_EMAIL = process.env.SUPPORT_EMAIL || "";

const TOPICS = {
  general: { en: "Question or problem", fi: "Kysymys tai ongelma" },
  withdrawal: { en: "Withdrawal or return of an order", fi: "Tilauksen peruminen tai palautus" },
  privacy: { en: "Privacy (GDPR) request", fi: "Tietosuojapyyntö (GDPR)" },
  illegal: { en: "Report illegal content or an unsafe product", fi: "Ilmoitus laittomasta sisällöstä tai vaarallisesta tuotteesta" },
  seller: { en: "Seller complaint", fi: "Myyjän valitus" },
  authority: { en: "Authority contact (Digital Services Act)", fi: "Viranomaisyhteys (digipalvelusäädös)" },
} as const;
type Topic = keyof typeof TOPICS;

const limiter = rateLimit({ windowMs: 60 * 60 * 1000, max: 8, standardHeaders: true, legacyHeaders: false, ...rateLimitStore("contact") });

const formSchema = z.object({
  topic: z.enum(Object.keys(TOPICS) as [Topic, ...Topic[]]),
  email: z.string().trim().email().max(200),
  message: z.string().trim().min(5).max(4000),
  orderId: z.string().trim().regex(/^\d{0,9}$/).optional(),
  lang: z.enum(["en", "fi"]).optional(),
});

const pick = (locale: Locale, en: string, fi: string) => (locale === "fi" ? fi : en);

function page(locale: Locale, body: string) {
  const title = pick(locale, "Contact Malvoya", "Ota yhteyttä Malvoyaan");
  return `<!DOCTYPE html><html lang="${locale}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${title}</title><style>
body{margin:0;background:#F6F3EE;color:#17131C;font:16px/1.5 system-ui,-apple-system,Segoe UI,Roboto,sans-serif}
main{max-width:560px;margin:0 auto;padding:32px 16px}h1{font-size:26px;margin:0 0 8px}p{margin:0 0 16px}
label{display:block;font-weight:600;margin:16px 0 6px}select,input,textarea{width:100%;box-sizing:border-box;padding:12px;border:1px solid #d8d2c8;border-radius:12px;font:inherit;background:#fff}
textarea{min-height:160px}button{margin-top:20px;background:#6D2E8C;color:#fff;border:0;border-radius:999px;padding:14px 24px;font:inherit;font-weight:600;cursor:pointer}
.muted{color:#6E6E73;font-size:14px}.err{background:#FDECEA;color:#D93025;padding:12px;border-radius:12px}a{color:#6D2E8C}
</style></head><body><main>${body}</main></body></html>`;
}

function form(locale: Locale, error?: string, values: Partial<Record<"topic" | "email" | "message" | "orderId", string>> = {}) {
  const other = locale === "fi" ? "en" : "fi";
  const options = (Object.keys(TOPICS) as Topic[])
    .map((k) => `<option value="${k}"${values.topic === k ? " selected" : ""}>${escapeHtml(TOPICS[k][locale])}</option>`).join("");
  return page(locale, `<h1>${pick(locale, "Contact Malvoya", "Ota yhteyttä Malvoyaan")}</h1>
<p>${pick(locale,
    "Write to us in English or Finnish. We reply by email, usually within 2 working days (privacy requests within one month). Signed-in users can also use Support in the app.",
    "Kirjoita meille suomeksi tai englanniksi. Vastaamme sähköpostitse yleensä 2 arkipäivän kuluessa (tietosuojapyyntöihin kuukauden kuluessa). Kirjautuneena voit käyttää myös sovelluksen Tuki-osiota.")}</p>
<p class="muted"><a href="/contact?lang=${other}">${other === "fi" ? "Suomeksi" : "In English"}</a></p>
${error ? `<p class="err">${escapeHtml(error)}</p>` : ""}
<form method="post" action="/contact">
<input type="hidden" name="lang" value="${locale}">
<label for="topic">${pick(locale, "Topic", "Aihe")}</label><select id="topic" name="topic">${options}</select>
<label for="email">${pick(locale, "Your email address", "Sähköpostiosoitteesi")}</label><input id="email" name="email" type="email" required maxlength="200" value="${escapeHtml(values.email ?? "")}">
<label for="orderId">${pick(locale, "Order number (if any)", "Tilausnumero (jos on)")}</label><input id="orderId" name="orderId" inputmode="numeric" maxlength="9" value="${escapeHtml(values.orderId ?? "")}">
<label for="message">${pick(locale, "Message", "Viesti")}</label><textarea id="message" name="message" required minlength="5" maxlength="4000">${escapeHtml(values.message ?? "")}</textarea>
<button type="submit">${pick(locale, "Send", "Lähetä")}</button>
</form>
<p class="muted" style="margin-top:24px">${pick(locale,
    "We use what you send only to answer you and keep it as the privacy policy says.",
    "Käytämme lähettämiäsi tietoja vain vastataksemme sinulle ja säilytämme ne tietosuojaselosteen mukaisesti.")} <a href="/legal/privacy">${pick(locale, "Privacy policy", "Tietosuojaseloste")}</a></p>`);
}

function localeOf(req: Request, explicit?: string): Locale {
  if (explicit === "fi" || explicit === "en") return explicit;
  return localeFromHeader(req.headers["accept-language"]) ?? "en";
}

contactRoutes.get("/contact", (req, res) => {
  const locale = localeOf(req, typeof req.query.lang === "string" ? req.query.lang : undefined);
  res.set("Content-Security-Policy", CSP).set("Cache-Control", "public, max-age=300").type("html").send(form(locale));
});

contactRoutes.post("/contact", limiter, urlencoded({ extended: false, limit: "16kb" }), async (req: Request, res: Response) => {
  res.set("Content-Security-Policy", CSP).set("Cache-Control", "no-store");
  const raw = (req.body ?? {}) as Record<string, string>;
  const locale = localeOf(req, raw.lang);
  const body = formSchema.safeParse(raw);
  if (!body.success) {
    return res.status(400).type("html").send(form(locale, pick(locale,
      "Choose a topic, give a valid email address and write a message of at least 5 characters.",
      "Valitse aihe, anna toimiva sähköpostiosoite ja kirjoita vähintään 5 merkin viesti."), raw));
  }
  try {
    const orderId = body.data.orderId ? Number(body.data.orderId) : null;
    const topic = TOPICS[body.data.topic].en;
    const request = await prisma.supportRequest.create({
      data: { userId: null, email: body.data.email, app: "web", topic, message: body.data.message, orderId: orderId || null },
    });
    const text = `Contact form #${request.id}\nFrom: ${body.data.email}\n${orderId ? `Order: #${orderId}\n` : ""}Topic: ${topic}\n\n${body.data.message}`;
    if (SUPPORT_EMAIL) sendEmail(SUPPORT_EMAIL, `Malvoya contact #${request.id}: ${topic}`, `<pre style="font-family:inherit;white-space:pre-wrap">${escapeHtml(text)}</pre>`, text, { kind: "internal" }).catch(() => {});
    sendSupportAck(body.data.email, request.id, locale).catch(() => {});
    res.status(201).type("html").send(page(locale, `<h1>${pick(locale, "Thank you", "Kiitos")}</h1>
<p>${pick(locale, `We received your message (#${request.id}) and will reply to ${escapeHtml(body.data.email)}.`,
      `Saimme viestisi (#${request.id}) ja vastaamme osoitteeseen ${escapeHtml(body.data.email)}.`)}</p>
<p><a href="/contact?lang=${locale}">${pick(locale, "Send another message", "Lähetä toinen viesti")}</a></p>`));
  } catch {
    res.status(500).type("html").send(form(locale, pick(locale, "Sending failed. Please try again.", "Lähetys epäonnistui. Yritä uudelleen."), raw));
  }
});
