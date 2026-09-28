import { Response } from "express";
import { AuthRequest } from "../../middleware/auth";
import { sendError, positiveId } from "../../lib/errors";
import { createProductSchema, updateProductSchema, productQuerySchema, searchQuerySchema } from "./products.schema";
import * as productsService from "./products.service";

export async function listProducts(req: AuthRequest, res: Response) {
  const query = productQuerySchema.safeParse(req.query);
  const storeId = positiveId(req.params.storeId);
  if (!query.success || !storeId) return res.status(400).json({ ok: false, error: "Invalid request" });
  try {
    res.json({ ok: true, ...(await productsService.getProductsByStore(storeId, query.data as any, req.user?.id)) });
  } catch (e) { sendError(res, e); }
}

export async function searchProducts(req: AuthRequest, res: Response) {
  const query = searchQuerySchema.safeParse(req.query);
  if (!query.success) return res.status(400).json({ ok: false, errors: query.error.flatten() });
  try {
    res.json({ ok: true, ...(await productsService.searchProducts(query.data)) });
  } catch (e) { sendError(res, e); }
}

export async function getProduct(req: AuthRequest, res: Response) {
  const id = positiveId(req.params.id);
  if (!id) return res.status(404).json({ ok: false, error: "Product not found" });
  try {
    res.json({ ok: true, product: await productsService.getProductById(id, req.user?.id) });
  } catch (e) { sendError(res, e); }
}

export async function createProduct(req: AuthRequest, res: Response) {
  const result = createProductSchema.safeParse(req.body);
  if (!result.success) return res.status(400).json({ ok: false, errors: result.error.flatten() });
  try {
    res.status(201).json({ ok: true, product: await productsService.createProduct(req.user!.id, result.data) });
  } catch (e) { sendError(res, e); }
}

export async function updateProduct(req: AuthRequest, res: Response) {
  const id = positiveId(req.params.id);
  const result = updateProductSchema.safeParse(req.body);
  if (!id || !result.success) return res.status(400).json({ ok: false, errors: result.success ? undefined : result.error.flatten() });
  try {
    res.json({ ok: true, product: await productsService.updateProduct(id, req.user!.id, result.data) });
  } catch (e) { sendError(res, e); }
}

export async function deleteProduct(req: AuthRequest, res: Response) {
  const id = positiveId(req.params.id);
  if (!id) return res.status(404).json({ ok: false, error: "Product not found" });
  try {
    await productsService.deleteProduct(id, req.user!.id);
    res.json({ ok: true });
  } catch (e) { sendError(res, e); }
}
