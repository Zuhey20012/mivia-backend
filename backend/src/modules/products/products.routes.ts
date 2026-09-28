import { Router } from "express";
import { listProducts, searchProducts, getProduct, createProduct, updateProduct, deleteProduct } from "./products.controller";
import { auth, optionalAuth, requireRole } from "../../middleware/auth";

const router = Router({ mergeParams: true });

router.get("/stores/:storeId(\\d+)/products", optionalAuth, listProducts);
router.get("/products/search",                searchProducts);
router.get("/products/:id(\\d+)",             optionalAuth, getProduct);
router.post("/products",                      auth, requireRole("VENDOR"), createProduct);
router.patch("/products/:id(\\d+)",           auth, requireRole("VENDOR"), updateProduct);
router.delete("/products/:id(\\d+)",          auth, requireRole("VENDOR"), deleteProduct);

export default router;
