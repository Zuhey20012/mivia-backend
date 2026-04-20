import { Response } from "express";
import { AuthRequest } from "../../middleware/auth";
import { createStoreSchema, updateStoreSchema, storeQuerySchema } from "./stores.schema";
import * as storesService from "./stores.service";

export async function listStores(req: AuthRequest, res: Response) {
  try {
    const query = storeQuerySchema.parse(req.query);
    const data  = await storesService.getStores(query);
    res.json({ ok: true, ...data });
  } catch (e: any) {
    res.status(400).json({ ok: false, error: e.message });
  }
}

export async function getStore(req: AuthRequest, res: Response) {
  try {
    const store = await storesService.getStoreById(Number(req.params.id));
    res.json({ ok: true, store });
  } catch {
    res.status(404).json({ ok: false, error: "Store not found" });
  }
}

export async function createStore(req: AuthRequest, res: Response) {
  const result = createStoreSchema.safeParse(req.body);
  if (!result.success) return res.status(400).json({ ok: false, errors: result.error.flatten() });
  try {
    const store = await storesService.createStore(req.user!.id, result.data);
    res.status(201).json({ ok: true, store });
  } catch (e: any) {
    res.status(409).json({ ok: false, error: e.message });
  }
}

export async function updateStore(req: AuthRequest, res: Response) {
  const result = updateStoreSchema.safeParse(req.body);
  if (!result.success) return res.status(400).json({ ok: false, errors: result.error.flatten() });
  try {
    const store = await storesService.updateStore(Number(req.params.id), req.user!.id, result.data);
    res.json({ ok: true, store });
  } catch (e: any) {
    res.status(e.message === "Forbidden" ? 403 : 404).json({ ok: false, error: e.message });
  }
}
