import { Response } from "express";
import { reportError } from "../../lib/sentry";
import { z } from "zod";
import { AuthRequest } from "../../middleware/auth";
import {
  createOrderSchema, quoteOrderSchema, createRentalSchema, createReturnSchema, updateReturnStatusSchema, updateOrderStatusSchema,
  collectOrderSchema, deliveryProblemSchema,
} from "./orders.schema";
import * as ordersService from "./orders.service";

function idParam(req: AuthRequest, name = "id") {
  const id = Number(req.params[name]);
  return Number.isInteger(id) && id > 0 ? id : null;
}

export function sendOrderError(res: Response, e: any) {
  if (e instanceof ordersService.PickupCodeError) {
    return res.status(e.status).json({ ok: false, error: e.message, attemptsLeft: e.attemptsLeft, ...(e.lockedUntil ? { lockedUntil: e.lockedUntil } : {}) });
  }
  if (e instanceof ordersService.OrderError) return res.status(e.status).json({ ok: false, error: e.message, ...(e.extra ?? {}) });
  if (typeof e?.status === "number") return res.status(e.status).json({ ok: false, error: e.message, ...(e.extra ?? {}) });
  console.error(e);
  reportError(e, { tags: { area: "orders" } });
  if (typeof e?.type === "string" && e.type.startsWith("Stripe")) {
    return res.status(502).json({ ok: false, error: "Payment could not be started. Please try again." });
  }
  return res.status(500).json({ ok: false, error: "Something went wrong" });
}

/** `?limit=` (capped per list) and `?before=<id>` (the `nextBefore` of the previous page). Both optional. */
function listPage(req: AuthRequest): ordersService.ListPage {
  const limit = Number(req.query.limit);
  const before = Number(req.query.before);
  return {
    ...(Number.isInteger(limit) && limit > 0 ? { limit } : {}),
    ...(Number.isInteger(before) && before > 0 ? { before } : {}),
  };
}
/** The id to pass as `before` for the next page, or null when this page was the last. */
function nextBefore(rows: { id: number }[], page: ordersService.ListPage, max: number) {
  const take = Math.min(page.limit ?? max, max);
  return rows.length >= take && rows.length ? rows[rows.length - 1].id : null;
}

// ─── ORDERS ──────────────────────────────────────────────────────────────────
export async function createOrder(req: AuthRequest, res: Response) {
  const result = createOrderSchema.safeParse(req.body);
  if (!result.success) return res.status(400).json({ ok: false, errors: result.error.flatten() });
  try {
    const data = await ordersService.createOrder(req.user!.id, result.data);
    res.status(201).json({ ok: true, ...data });
  } catch (e) { sendOrderError(res, e); }
}

export async function quoteOrder(req: AuthRequest, res: Response) {
  const result = quoteOrderSchema.safeParse(req.body);
  if (!result.success) return res.status(400).json({ ok: false, errors: result.error.flatten() });
  try {
    res.json({ ok: true, quote: await ordersService.quoteOrder(req.user!.id, result.data) });
  } catch (e) { sendOrderError(res, e); }
}

export async function listOrders(req: AuthRequest, res: Response) {
  try {
    const page = listPage(req);
    const orders = await ordersService.listOrdersFor(req.user!, page);
    res.json({ ok: true, orders, nextBefore: nextBefore(orders, page, req.user!.role === "COURIER" ? 100 : 200) });
  } catch (e) { sendOrderError(res, e); }
}

export async function getOrder(req: AuthRequest, res: Response) {
  const id = idParam(req);
  if (!id) return res.status(404).json({ ok: false, error: "Order not found" });
  try {
    res.json({ ok: true, order: await ordersService.getOrder(id, req.user!) });
  } catch (e) { sendOrderError(res, e); }
}

export async function cancelOrder(req: AuthRequest, res: Response) {
  const id = idParam(req);
  if (!id) return res.status(404).json({ ok: false, error: "Order not found" });
  try {
    res.json({ ok: true, order: await ordersService.cancelOrderByCustomer(id, req.user!.id) });
  } catch (e) { sendOrderError(res, e); }
}

export async function updateOrderStatus(req: AuthRequest, res: Response) {
  const id = idParam(req);
  const result = updateOrderStatusSchema.safeParse(req.body);
  if (!id) return res.status(404).json({ ok: false, error: "Order not found" });
  if (!result.success) return res.status(400).json({ ok: false, errors: result.error.flatten() });
  try {
    res.json({ ok: true, order: await ordersService.updateOrderStatus(id, req.user!, result.data.status, { reason: result.data.reason }) });
  } catch (e) { sendOrderError(res, e); }
}

/** Reserve & collect: the store enters the customer's pickup code to hand the order over. */
export async function collectOrder(req: AuthRequest, res: Response) {
  const id = idParam(req);
  const result = collectOrderSchema.safeParse(req.body);
  if (!id) return res.status(404).json({ ok: false, error: "Order not found" });
  if (!result.success) return res.status(400).json({ ok: false, error: "Enter the customer's 6-digit pickup code", errors: result.error.flatten() });
  try {
    res.json({ ok: true, order: await ordersService.collectOrder(id, req.user!.id, result.data.code) });
  } catch (e) { sendOrderError(res, e); }
}

/** "Complete payment": the PaymentSheet secret of the customer's own unpaid order (409 when it can no longer be paid). */
export async function getOrderPayment(req: AuthRequest, res: Response) {
  const id = idParam(req);
  if (!id) return res.status(404).json({ ok: false, error: "Order not found" });
  try {
    res.json({ ok: true, ...(await ordersService.getOrderPayment(id, req.user!.id)) });
  } catch (e) { sendOrderError(res, e); }
}

export async function reportDeliveryProblem(req: AuthRequest, res: Response) {
  const id = idParam(req);
  const result = deliveryProblemSchema.safeParse(req.body);
  if (!id) return res.status(404).json({ ok: false, error: "Order not found" });
  if (!result.success) return res.status(400).json({ ok: false, error: "Choose why you cannot deliver", errors: result.error.flatten() });
  try {
    res.json({ ok: true, ...(await ordersService.reportDeliveryProblem(id, req.user!.id, result.data)) });
  } catch (e) { sendOrderError(res, e); }
}

export async function returnToStore(req: AuthRequest, res: Response) {
  const id = idParam(req);
  if (!id) return res.status(404).json({ ok: false, error: "Order not found" });
  try {
    res.json({ ok: true, order: await ordersService.returnToStore(id, req.user!.id) });
  } catch (e) { sendOrderError(res, e); }
}

export async function confirmReturnReceived(req: AuthRequest, res: Response) {
  const id = idParam(req);
  if (!id) return res.status(404).json({ ok: false, error: "Order not found" });
  try {
    res.json({ ok: true, order: await ordersService.confirmReturnReceived(id, req.user!.id) });
  } catch (e) { sendOrderError(res, e); }
}

// ─── RENTALS ─────────────────────────────────────────────────────────────────
export async function createRental(req: AuthRequest, res: Response) {
  const result = createRentalSchema.safeParse(req.body);
  if (!result.success) return res.status(400).json({ ok: false, errors: result.error.flatten() });
  try {
    const data = await ordersService.createRental(req.user!.id, result.data);
    res.status(201).json({ ok: true, ...data });
  } catch (e) { sendOrderError(res, e); }
}

export async function listRentals(req: AuthRequest, res: Response) {
  try {
    const page = listPage(req);
    const rentals = await ordersService.listRentals(req.user!.id, page);
    res.json({ ok: true, rentals, nextBefore: nextBefore(rentals, page, 200) });
  } catch (e) { sendOrderError(res, e); }
}

export async function getRental(req: AuthRequest, res: Response) {
  const id = idParam(req);
  if (!id) return res.status(404).json({ ok: false, error: "Rental not found" });
  try {
    res.json({ ok: true, rental: await ordersService.getRental(id, req.user!.id) });
  } catch (e) { sendOrderError(res, e); }
}

// ─── RETURNS ─────────────────────────────────────────────────────────────────
export async function createReturn(req: AuthRequest, res: Response) {
  const result = createReturnSchema.safeParse(req.body);
  if (!result.success) return res.status(400).json({ ok: false, errors: result.error.flatten() });
  try {
    const ret = await ordersService.createReturn(req.user!.id, result.data);
    res.status(201).json({ ok: true, return: ret });
  } catch (e) { sendOrderError(res, e); }
}

export async function listReturns(req: AuthRequest, res: Response) {
  try {
    const page = listPage(req);
    const returns = await ordersService.listReturns(req.user!, page);
    res.json({ ok: true, returns, nextBefore: nextBefore(returns, page, 100) });
  } catch (e) { sendOrderError(res, e); }
}

export async function getReturn(req: AuthRequest, res: Response) {
  const id = idParam(req);
  if (!id) return res.status(404).json({ ok: false, error: "Return not found" });
  try {
    res.json({ ok: true, return: await ordersService.getReturn(id, req.user!) });
  } catch (e) { sendOrderError(res, e); }
}

export async function updateReturnStatus(req: AuthRequest, res: Response) {
  const id = idParam(req);
  const result = updateReturnStatusSchema.safeParse(req.body);
  if (!id) return res.status(404).json({ ok: false, error: "Return not found" });
  if (!result.success) return res.status(400).json({ ok: false, errors: result.error.flatten() });
  try {
    res.json({ ok: true, return: await ordersService.updateReturnStatus(id, req.user!, result.data) });
  } catch (e) { sendOrderError(res, e); }
}

// ─── DELIVERY HANDOVER ───────────────────────────────────────────────────────
const deliverSchema = z.object({
  method: z.enum(["IN_PERSON", "PHOTO"]),
  latitude: z.number().min(-90).max(90).optional(),
  longitude: z.number().min(-180).max(180).optional(),
  upload: z.object({
    publicId: z.string().min(5).max(200),
    version: z.union([z.string().max(20), z.number().int()]),
    signature: z.string().length(40),
  }).optional(),
});

export async function deliverOrder(req: AuthRequest, res: Response) {
  const id = idParam(req);
  const result = deliverSchema.safeParse(req.body);
  if (!id) return res.status(404).json({ ok: false, error: "Order not found" });
  if (!result.success) return res.status(400).json({ ok: false, errors: result.error.flatten() });
  try {
    res.json({ ok: true, order: await ordersService.deliverOrder(id, req.user!.id, result.data) });
  } catch (e) { sendOrderError(res, e); }
}

export async function getDeliveryProof(req: AuthRequest, res: Response) {
  const id = idParam(req);
  if (!id) return res.status(404).json({ ok: false, error: "Order not found" });
  try {
    res.json({ ok: true, proof: await ordersService.getDeliveryProof(id, req.user!) });
  } catch (e) { sendOrderError(res, e); }
}
