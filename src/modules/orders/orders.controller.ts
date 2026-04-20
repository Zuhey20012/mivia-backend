import { Response } from "express";
import { AuthRequest } from "../../middleware/auth";
import { createOrderSchema, createRentalSchema, createReturnSchema, updateReturnStatusSchema } from "./orders.schema";
import * as ordersService from "./orders.service";

// ─── ORDERS ──────────────────────────────────────────────────────────────────
export async function createOrder(req: AuthRequest, res: Response) {
  const result = createOrderSchema.safeParse(req.body);
  if (!result.success) return res.status(400).json({ ok: false, errors: result.error.flatten() });
  try {
    const data = await ordersService.createOrder(req.user!.id, result.data);
    res.status(201).json({ ok: true, ...data });
  } catch (e: any) { res.status(400).json({ ok: false, error: e.message }); }
}

export async function listOrders(req: AuthRequest, res: Response) {
  const orders = await ordersService.listOrders(req.user!.id);
  res.json({ ok: true, orders });
}

export async function getOrder(req: AuthRequest, res: Response) {
  try {
    const order = await ordersService.getOrder(Number(req.params.id), req.user!.id);
    res.json({ ok: true, order });
  } catch (e: any) {
    res.status(e.message === "Forbidden" ? 403 : 404).json({ ok: false, error: e.message });
  }
}

// ─── RENTALS ─────────────────────────────────────────────────────────────────
export async function createRental(req: AuthRequest, res: Response) {
  const result = createRentalSchema.safeParse(req.body);
  if (!result.success) return res.status(400).json({ ok: false, errors: result.error.flatten() });
  try {
    const data = await ordersService.createRental(req.user!.id, result.data);
    res.status(201).json({ ok: true, ...data });
  } catch (e: any) { res.status(400).json({ ok: false, error: e.message }); }
}

export async function listRentals(req: AuthRequest, res: Response) {
  const rentals = await ordersService.listRentals(req.user!.id);
  res.json({ ok: true, rentals });
}

export async function getRental(req: AuthRequest, res: Response) {
  try {
    const rental = await ordersService.getRental(Number(req.params.id), req.user!.id);
    res.json({ ok: true, rental });
  } catch (e: any) {
    res.status(e.message === "Forbidden" ? 403 : 404).json({ ok: false, error: e.message });
  }
}

// ─── RETURNS ─────────────────────────────────────────────────────────────────
export async function createReturn(req: AuthRequest, res: Response) {
  const result = createReturnSchema.safeParse(req.body);
  if (!result.success) return res.status(400).json({ ok: false, errors: result.error.flatten() });
  try {
    const ret = await ordersService.createReturn(req.user!.id, result.data as any);
    res.status(201).json({ ok: true, return: ret });
  } catch (e: any) { res.status(400).json({ ok: false, error: e.message }); }
}

export async function getReturn(req: AuthRequest, res: Response) {
  try {
    const ret = await ordersService.getReturn(Number(req.params.id), req.user!.id);
    res.json({ ok: true, return: ret });
  } catch (e: any) {
    res.status(e.message === "Forbidden" ? 403 : 404).json({ ok: false, error: e.message });
  }
}

export async function updateReturnStatus(req: AuthRequest, res: Response) {
  const result = updateReturnStatusSchema.safeParse(req.body);
  if (!result.success) return res.status(400).json({ ok: false, errors: result.error.flatten() });
  try {
    const ret = await ordersService.updateReturnStatus(Number(req.params.id), result.data as any);
    res.json({ ok: true, return: ret });
  } catch (e: any) { res.status(400).json({ ok: false, error: e.message }); }
}
