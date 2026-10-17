import { Router, Response } from "express";
import { z } from "zod";
import { listStores, getStore, getMyStore, createStore, updateStore } from "./stores.controller";
import { auth, optionalAuth, requireRole, AuthRequest } from "../../middleware/auth";
import { sendError } from "../../lib/errors";
import { listMyProducts } from "../products/products.service";

const router = Router();

const myProductsQuery = z.object({
  page: z.coerce.number().int().min(1).max(10_000).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(30),
  q: z.string().trim().max(100).optional(),
  filter: z.enum(["all", "visible", "drafts", "soldout"]).default("all"),
});

router.get("/",        listStores);
router.get("/my",     auth, requireRole("VENDOR"), getMyStore);
// The store's own catalogue, paged: ?page=1&limit=30&q=&filter=all|visible|drafts|soldout
router.get("/my/products", auth, requireRole("VENDOR"), async (req: AuthRequest, res: Response) => {
  const q = myProductsQuery.safeParse(req.query);
  if (!q.success) return res.status(400).json({ ok: false, error: "Invalid page, limit or filter" });
  try {
    res.json({ ok: true, ...(await listMyProducts(req.user!.id, { ...q.data, q: q.data.q || undefined })) });
  } catch (e) { sendError(res, e); }
});
router.get("/:id(\\d+)", optionalAuth, getStore);
router.post("/",       auth, requireRole("VENDOR"), createStore);
router.patch("/:id(\\d+)", auth, requireRole("VENDOR"), updateStore);

export default router;
