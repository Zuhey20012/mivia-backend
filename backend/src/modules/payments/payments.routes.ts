import express, { Router, Request, Response } from "express";
import pino from "pino";
import { env } from "../../config/env";
import { prisma } from "../../lib/prisma";
import { getStripe } from "../../lib/stripe";
import { markOrderPaid, markOrderPaymentFailed, markRentalPaid } from "../orders/orders.service";

const logger = pino({ name: "stripe-webhook" });
const router = Router();

/**
 * Stripe → Malvoya. This is the ONLY place an order becomes paid; the app's PaymentSheet result is
 * never trusted on its own. Mounted with a raw body parser because the signature covers the raw bytes.
 */
router.post("/payments/webhook", express.raw({ type: "application/json", limit: "1mb" }), async (req: Request, res: Response) => {
  if (!env.stripeWebhookSecret) {
    logger.error("STRIPE_WEBHOOK_SECRET is not set; refusing webhook");
    return res.status(503).send("Webhook not configured");
  }

  let event: ReturnType<ReturnType<typeof getStripe>["webhooks"]["constructEvent"]>;
  try {
    event = getStripe().webhooks.constructEvent(req.body, req.headers["stripe-signature"] as string, env.stripeWebhookSecret);
  } catch (err: any) {
    logger.warn({ err: err?.message }, "Invalid Stripe signature");
    return res.status(400).send("Invalid signature");
  }

  // Idempotency: Stripe retries, so each event is handled once.
  const seen = await prisma.stripeEvent.findUnique({ where: { id: event.id } });
  if (seen) return res.json({ received: true, duplicate: true });

  try {
    if (event.type === "payment_intent.succeeded" || event.type === "payment_intent.payment_failed") {
      const intent = event.data.object as { id: string; amount_received: number; metadata?: Record<string, string> };
      const { type, orderId, rentalId } = intent.metadata ?? {};

      if (event.type === "payment_intent.succeeded") {
        if (type === "ORDER" && orderId) await markOrderPaid(Number(orderId), intent.id, intent.amount_received);
        if (type === "RENTAL" && rentalId) await markRentalPaid(Number(rentalId), intent.id, intent.amount_received);
      } else if (type === "ORDER" && orderId) {
        await markOrderPaymentFailed(Number(orderId), intent.id);
      }
    }
    await prisma.stripeEvent.create({ data: { id: event.id, type: event.type } });
    res.json({ received: true });
  } catch (err: any) {
    logger.error({ err: err?.message, eventId: event.id, type: event.type }, "Webhook handling failed");
    // 500 → Stripe retries later
    res.status(500).send("Handler error");
  }
});

export default router;
