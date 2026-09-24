import { Response } from "express";
import { AuthRequest } from "../../middleware/auth";
import {
  createOrderSchema, createRentalSchema, createReturnSchema, updateReturnStatusSchema, updateOrderStatusSchema,
} from "./orders.schema";
import * as ordersService from "./orders.service";

function idParam(req: AuthRequest, name = "id") {
  const id = Number(req.params[name]);
  return Number.isInteger(id) && id > 0 ? id : null;
}

export function sendOrderError(res: Response, e: any) {
  if (e instanceof ordersService.OrderError) return res.status(e.status).json({ ok: false, error: e.message });
  if (typeof e?.status === "number") return res.status(e.status).json({ ok: false, error: e.message });
  console.error(e);
  if (typeof e?.type === "string" && e.type.startsWith("Stripe")) {
    return res.status(502).json({ ok: false, error: "Payment could not be started. Please try again." });
  }
  return res.status(500).json({ ok: false, error: "Something went wrong" });
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

export async function listOrders(req: AuthRequest, res: Response) {
  try {
    res.json({ ok: true, orders: await ordersService.listOrdersFor(req.user!) });
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
    res.json({ ok: true, order: await ordersService.updateOrderStatus(id, req.user!, result.data.status) });
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
    res.json({ ok: true, rentals: await ordersService.listRentals(req.user!.id) });
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
    res.json({ ok: true, returns: await ordersService.listReturns(req.user!.id) });
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
