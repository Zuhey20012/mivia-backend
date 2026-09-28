import { Response } from "express";
import { AuthRequest } from "../../middleware/auth";
import { createStoreSchema, updateStoreSchema, storeQuerySchema } from "./stores.schema";
import * as storesService from "./stores.service";
import { sendError, positiveId } from "../../lib/errors";

export async function listStores(req: AuthRequest, res: Response) {
  try {
    const query = storeQuerySchema.parse(req.query);
    const data  = await storesService.getStores(query);
    res.json({ ok: true, ...data });
  } catch (e: any) {
    res.status(400).json({ ok: false, error: e.message });
  }
}

export async function getMyStore(req: AuthRequest, res: Response) {
  const store = await storesService.getMyStore(req.user!.id);
  if (!store) return res.status(404).json({ ok: false, error: "You have not created a store yet" });
  res.json({ ok: true, store });
}

export async function getStore(req: AuthRequest, res: Response) {
  const id = positiveId(req.params.id);
  if (!id) return res.status(404).json({ ok: false, error: "Store not found" });
  const lat = req.query.lat !== undefined ? Number(req.query.lat) : null;
  const lng = req.query.lng !== undefined ? Number(req.query.lng) : null;
  try {
    res.json({ ok: true, store: await storesService.getStoreById(id, req.user?.id, lat, lng) });
  } catch (e) { sendError(res, e); }
}

export async function createStore(req: AuthRequest, res: Response) {
  const result = createStoreSchema.safeParse(req.body);
  if (!result.success) return res.status(400).json({ ok: false, errors: result.error.flatten() });
  try {
    const store = await storesService.createStore(req.user!.id, result.data);
    res.status(201).json({ ok: true, store });
  } catch (e) { sendError(res, e); }
}

export async function updateStore(req: AuthRequest, res: Response) {
  const result = updateStoreSchema.safeParse(req.body);
  if (!result.success) return res.status(400).json({ ok: false, errors: result.error.flatten() });
  try {
    const store = await storesService.updateStore(Number(req.params.id), req.user!.id, result.data);
    res.json({ ok: true, store });
  } catch (e) { sendError(res, e); }
}
