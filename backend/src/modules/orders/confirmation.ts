import crypto from "crypto";
import { Router, Request, Response } from "express";
import { prisma } from "../../lib/prisma";
import { env } from "../../config/env";
import { auth, AuthRequest } from "../../middleware/auth";
import { ApiError, positiveId, sendError } from "../../lib/errors";
import { asLocale, localeFromHeader } from "../../lib/i18n";
import { legalState } from "../legal/legalDocs";
import { orderConfirmationHtml } from "../../services/notificationDeliveryService";

/**
 * The order confirmation as a page (since 2.17.0), for accounts without a deliverable email (phone sign-in) and for
 * anyone who wants it again: the customer asks for a 10-minute signed link (no bearer token in a browser), like the
 * store statements. HMAC-SHA256 with a key derived from JWT_SECRET under its own label; constant-time compare.
 */
const TTL_SECONDS = 10 * 60;
const key = crypto.createHmac("sha256", env.jwtSecret).update("malvoya:order-confirmation-link:v1").digest();
const sign = (orderId: number, exp: number) => crypto.createHmac("sha256", key).update(`confirmation|${orderId}|${exp}`).digest("base64url");

export function confirmationLink(orderId: number) {
  const exp = Math.floor(Date.now() / 1000) + TTL_SECONDS;
  return { url: `${env.publicApiUrl}/api/v1/orders/${orderId}/confirmation.html?exp=${exp}&sig=${sign(orderId, exp)}`, expiresAt: new Date(exp * 1000) };
}

function checkLink(orderId: number, expRaw: unknown, sigRaw: unknown) {
  const exp = Number(expRaw);
  if (typeof sigRaw !== "string" || !Number.isInteger(exp)) return "invalid";
  const a = Buffer.from(sign(orderId, exp)), b = Buffer.from(sigRaw);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return "invalid";
  return exp * 1000 < Date.now() ? "expired" : "ok";
}

export const confirmationRoutes = Router();

confirmationRoutes.get("/orders/:id(\\d+)/confirmation/link", auth, async (req: AuthRequest, res: Response) => {
  try {
    const id = positiveId(req.params.id)!;
    const o = await prisma.order.findUnique({ where: { id }, select: { userId: true, paymentStatus: true } });
    if (!o || o.userId !== req.user!.id) throw new ApiError("Order not found", 404);
    if (o.paymentStatus === "PENDING" || o.paymentStatus === "FAILED") throw new ApiError("The order has not been paid", 409);
    res.json({ ok: true, ...confirmationLink(id) });
  } catch (e) { sendError(res, e); }
});

confirmationRoutes.get("/orders/:id(\\d+)/confirmation.html", async (req: Request, res: Response) => {
  const id = positiveId(req.params.id);
  res.set("Cache-Control", "private, no-store");
  res.set("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'");
  res.set("Referrer-Policy", "no-referrer");
  if (!id) return res.status(404).type("text").send("Not found");
  const check = checkLink(id, req.query.exp, req.query.sig);
  if (check !== "ok") return res.status(403).type("text").send(check === "expired" ? "This link has expired. Open the order in the app again." : "Invalid link");
  try {
    const o = await prisma.order.findUnique({
      where: { id },
      include: {
        user: { select: { name: true, locale: true } },
        store: { select: { name: true, sellerType: true, address: true, businessId: true, email: true, phone: true } },
        items: { include: { product: { select: { name: true } } } },
        promoCode: { select: { code: true } },
      },
    });
    if (!o) return res.status(404).type("text").send("Not found");
    const L = req.query.lang === "fi" || req.query.lang === "en" ? req.query.lang : o.user.locale ? asLocale(o.user.locale) : localeFromHeader(req.headers["accept-language"]) ?? "en";
    const { html } = await orderConfirmationHtml({
      orderId: o.id, customerName: o.user.name, storeName: o.store.name,
      items: o.items.map((i) => ({ name: i.product.name, quantity: i.quantity, unitCents: i.unitCents, hygieneSealed: i.hygieneSealed })),
      subtotalCents: o.subtotalCents, deliveryFeeCents: o.deliveryFeeCents, serviceFeeCents: o.serviceFeeCents, smallOrderFeeCents: o.smallOrderFeeCents,
      discountCents: o.discountCents, promoCode: o.promoCode?.code ?? null, tipCents: o.tipCents, totalCents: o.totalCents,
      deliveryAddress: o.deliveryAddress,
      // The buyer's own counterparty: name, address and contact are shown to them (as in the email)
      seller: { type: o.store.sellerType, address: o.store.address, businessId: o.store.businessId, email: o.store.email, phone: o.store.phone },
      fulfilment: o.fulfilment,
      termsVersion: (await legalState("terms").catch(() => null))?.current?.version ?? null,
    }, L);
    res.type("html").send(html);
  } catch (e) { sendError(res, e); }
});
