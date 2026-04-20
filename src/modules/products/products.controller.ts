import { Response } from "express";
import { AuthRequest } from "../../middleware/auth";
import { createProductSchema, updateProductSchema, productQuerySchema } from "./products.schema";
import * as productsService from "./products.service";

export async function listProducts(req: AuthRequest, res: Response) {
  try {
    const query = productQuerySchema.parse(req.query);
    const data  = await productsService.getProductsByStore(Number(req.params.storeId), query as any);
    res.json({ ok: true, ...data });
  } catch (e: any) { res.status(400).json({ ok: false, error: e.message }); }
}

export async function getProduct(req: AuthRequest, res: Response) {
  try {
    const product = await productsService.getProductById(Number(req.params.id));
    res.json({ ok: true, product });
  } catch { res.status(404).json({ ok: false, error: "Product not found" }); }
}

export async function createProduct(req: AuthRequest, res: Response) {
  const result = createProductSchema.safeParse(req.body);
  if (!result.success) return res.status(400).json({ ok: false, errors: result.error.flatten() });
  try {
    const store = await import("../../lib/prisma").then(m =>
      m.prisma.store.findUnique({ where: { ownerId: req.user!.id } })
    );
    if (!store) return res.status(404).json({ ok: false, error: "Create your store first" });
    const product = await productsService.createProduct(store.id, result.data);
    res.status(201).json({ ok: true, product });
  } catch (e: any) { res.status(400).json({ ok: false, error: e.message }); }
}

export async function updateProduct(req: AuthRequest, res: Response) {
  const result = updateProductSchema.safeParse(req.body);
  if (!result.success) return res.status(400).json({ ok: false, errors: result.error.flatten() });
  try {
    const product = await productsService.updateProduct(Number(req.params.id), req.user!.id, result.data);
    res.json({ ok: true, product });
  } catch (e: any) {
    res.status(e.message === "Forbidden" ? 403 : 404).json({ ok: false, error: e.message });
  }
}

export async function deleteProduct(req: AuthRequest, res: Response) {
  try {
    await productsService.deleteProduct(Number(req.params.id), req.user!.id);
    res.json({ ok: true });
  } catch (e: any) {
    res.status(e.message === "Forbidden" ? 403 : 404).json({ ok: false, error: e.message });
  }
}
