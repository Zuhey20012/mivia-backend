import { Router, Response } from "express";
import { escapeHtml } from "../../services/notificationDeliveryService";
import { env } from "../../config/env";
import { positiveId } from "../../lib/errors";
import { getStoreById } from "../stores/stores.service";
import { inviteForCode } from "../referrals/referrals.service";

/**
 * Public share pages and Android App Links, mounted outside /api/v1 (like the drop page /d/:id).
 * Pages are server-rendered with every value escaped, no scripts, and a CSP that only allows Cloudinary
 * images and inline styles. Once the customer app declares intent filters for /d/*, /s/* and /r/* on this
 * host, Android opens these links straight in the app (verified through assetlinks.json).
 */
export const shareRoutes = Router();

const CSP = "default-src 'none'; img-src https://res.cloudinary.com; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'";

/** Digital Asset Links: lets the customer app (com.malvoya.customer) open this host's links. */
shareRoutes.get("/.well-known/assetlinks.json", (_req, res) => {
  const body = env.androidAppSha256.length
    ? [{
        relation: ["delegate_permission/common.handle_all_urls"],
        target: { namespace: "android_app", package_name: env.androidCustomerPackage, sha256_cert_fingerprints: env.androidAppSha256 },
      }]
    : [];
  res.set("Cache-Control", "public, max-age=3600");
  res.type("application/json").send(JSON.stringify(body));
});

/**
 * Apple universal links for the customer app (iOS): the share, invite and drop pages open in the app. Served as JSON,
 * 200, no redirect. APPLE_TEAM_ID (the Apple Developer Team ID) unset = no apps listed.
 */
shareRoutes.get("/.well-known/apple-app-site-association", (_req, res) => {
  const team = (process.env.APPLE_TEAM_ID || "").trim();
  const details = /^[A-Z0-9]{10}$/.test(team)
    ? [{ appIDs: [`${team}.com.malvoya.customer`], components: [{ "/": "/s/*" }, { "/": "/r/*" }, { "/": "/d/*" }] }]
    : [];
  res.set("Cache-Control", "public, max-age=3600");
  res.type("application/json").send(JSON.stringify({ applinks: { details } }));
});

/** "Open in the app" on Android: the https link inside the app if installed, otherwise the Play Store. */
function openInAppLink(path: string) {
  const host = env.publicApiUrl.replace(/^https?:\/\//, "");
  return `intent://${host}${path}#Intent;scheme=https;package=${env.androidCustomerPackage};S.browser_fallback_url=${encodeURIComponent(env.playStoreUrl)};end`;
}

const euro = (cents: number) => `${(cents / 100).toFixed(2).replace(".", ",")} €`;

function sendPage(res: Response, page: { title: string; description: string; image?: string | null; body: string; status?: number }) {
  res.status(page.status ?? 200);
  res.set("Cache-Control", "public, max-age=300");
  res.set("Content-Security-Policy", CSP);
  res.type("html").send(`<!doctype html>
<html lang="fi"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${escapeHtml(page.title)}</title>
<meta property="og:type" content="website">
<meta property="og:title" content="${escapeHtml(page.title)}">
<meta property="og:description" content="${escapeHtml(page.description)}">
${page.image ? `<meta property="og:image" content="${escapeHtml(page.image)}">` : ""}
<meta name="robots" content="noindex">
</head>
<body style="margin:0;font-family:-apple-system,system-ui,sans-serif;background:#F6F3EE;color:#17131C;display:flex;min-height:100vh;align-items:center;justify-content:center">
<main style="max-width:420px;width:100%;padding:24px;text-align:center">
${page.body}
</main></body></html>`);
}

const button = (href: string, label: string) =>
  `<a href="${escapeHtml(href)}" style="display:block;background:#6D2E8C;color:#fff;text-decoration:none;padding:14px;border-radius:999px;font-weight:600;margin-bottom:10px">${escapeHtml(label)}</a>`;
const secondary = (href: string, label: string) =>
  `<a href="${escapeHtml(href)}" style="display:block;color:#17131C;text-decoration:none;padding:12px;border:1px solid #d9d2c7;border-radius:999px">${escapeHtml(label)}</a>`;

/** Store share page: name, logo, a few products, open in the app / get the app. */
shareRoutes.get("/s/:storeId", async (req, res) => {
  const id = positiveId(req.params.storeId);
  const store = id ? await getStoreById(id).catch(() => null) : null;
  if (!store) {
    return sendPage(res, {
      status: 404,
      title: "Malvoya",
      description: "Local fashion from stores near you.",
      body: `<h1 style="font-size:20px">Kauppaa ei löytynyt / Store not found</h1>${secondary(env.playStoreUrl, "Get the app")}`,
    });
  }
  const products = store.products.filter((p) => p.pricing?.priceCents != null).slice(0, 6);
  const tiles = products.map((p) => `<div style="text-align:left">
${p.images[0] ? `<img src="${escapeHtml(p.images[0])}" alt="" style="width:100%;aspect-ratio:4/5;object-fit:cover;border-radius:18px;background:#e9e3da">` : `<div style="width:100%;aspect-ratio:4/5;border-radius:18px;background:#e9e3da"></div>`}
<p style="margin:6px 0 0;font-size:14px">${escapeHtml(p.name)}</p>
<p style="margin:2px 0 0;font-size:14px;font-weight:600">${escapeHtml(euro(p.pricing.priceCents!))}</p>
</div>`).join("\n");
  const description = store.description || `${store.name} on Malvoya: local fashion, delivered or ready to collect.`;
  sendPage(res, {
    title: `${store.name} – Malvoya`,
    description,
    image: store.logoUrl ?? products[0]?.images[0] ?? null,
    body: `${store.logoUrl ? `<img src="${escapeHtml(store.logoUrl)}" alt="" style="width:88px;height:88px;border-radius:24px;object-fit:cover;background:#e9e3da">` : ""}
<h1 style="font-size:22px;margin:14px 0 4px">${escapeHtml(store.name)}</h1>
<p style="margin:0 0 18px;color:#5c5463">${escapeHtml(description)}</p>
${tiles ? `<div style="display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-bottom:20px">${tiles}</div>` : ""}
${button(openInAppLink(`/s/${store.id}`), "Avaa Malvoya-sovelluksessa / Open in the Malvoya app")}
${secondary(env.playStoreUrl, "Lataa sovellus / Get the app")}`,
  });
});

/** Invite landing page: explains the offer as it is, or says the invite is no longer valid. */
shareRoutes.get("/r/:code", async (req, res) => {
  const invite = await inviteForCode(String(req.params.code ?? "")).catch(() => null);
  if (!invite) {
    return sendPage(res, {
      status: 404,
      title: "Malvoya",
      description: "This invite is no longer valid.",
      body: `<h1 style="font-size:20px">Kutsu ei ole enää voimassa / This invite is no longer valid</h1>
<p style="color:#5c5463">Voit silti tilata Malvoyasta. / You can still shop on Malvoya.</p>
${secondary(env.playStoreUrl, "Lataa sovellus / Get the app")}`,
    });
  }
  const amount = euro(invite.discountCents);
  sendPage(res, {
    title: `${amount} off your first Malvoya order`,
    description: `A friend invited you to Malvoya. New customers get ${amount} off their first order with this code.`,
    body: `<h1 style="font-size:22px;margin:0 0 8px">Kaverisi kutsui sinut Malvoyaan / A friend invited you to Malvoya</h1>
<p style="margin:0 0 6px">Uutena asiakkaana saat <strong>${escapeHtml(amount)}</strong> alennuksen ensimmäisestä tilauksestasi.</p>
<p style="margin:0 0 16px">As a new customer you get <strong>${escapeHtml(amount)}</strong> off your first order.</p>
<p style="margin:0 0 6px;color:#5c5463">Kirjoita koodi kassalla / Enter the code at checkout:</p>
<p style="font-size:28px;font-weight:700;letter-spacing:4px;margin:0 0 16px;font-family:ui-monospace,Menlo,monospace">${escapeHtml(invite.code)}</p>
<p style="margin:0 0 20px;color:#5c5463;font-size:13px">Vain ensimmäiseen tilaukseen, yksi kutsu asiakasta kohden, ei rahallista arvoa. / First order only, one invite per new customer, no cash value. <a href="${escapeHtml(`${env.publicApiUrl}/legal/terms`)}" style="color:#6D2E8C">Terms</a></p>
${button(openInAppLink(`/r/${invite.code}`), "Avaa Malvoya-sovelluksessa / Open in the Malvoya app")}
${secondary(env.playStoreUrl, "Lataa sovellus / Get the app")}`,
  });
});
