import { Router } from "express";
import { listProducts, getProduct, createProduct, updateProduct, deleteProduct } from "./products.controller";
import { auth, requireRole } from "../../middleware/auth";

const router = Router({ mergeParams: true });

router.get("/stores/:storeId/products", listProducts);
router.get("/products/:id",             getProduct);
router.post("/products",                auth, requireRole("VENDOR","ADMIN"), createProduct);
router.patch("/products/:id",           auth, requireRole("VENDOR","ADMIN"), updateProduct);
router.delete("/products/:id",          auth, requireRole("VENDOR","ADMIN"), deleteProduct);

export default router;
