import { Router } from "express";
import { listProducts, searchProducts, getProduct, createProduct, updateProduct, deleteProduct } from "./products.controller";
import { auth, optionalAuth, requireRole } from "../../middleware/auth";
import { productVideoRoutes } from "./productVideos";
import { requireAgreement } from "../legal/agreements";

// Publishing (a visible new product, or making one visible) needs the Seller Terms in force to be accepted; drafts do not
const publishing = requireAgreement((req) => (req.method === "POST" ? req.body?.isAvailable !== false : req.body?.isAvailable === true));

const router = Router({ mergeParams: true });

router.get("/stores/:storeId(\\d+)/products", optionalAuth, listProducts);
router.get("/products/search",                searchProducts);
router.get("/products/:id(\\d+)",             optionalAuth, getProduct);
router.post("/products",                      auth, requireRole("VENDOR"), publishing, createProduct);
router.patch("/products/:id(\\d+)",           auth, requireRole("VENDOR"), publishing, updateProduct);
router.delete("/products/:id(\\d+)",          auth, requireRole("VENDOR"), deleteProduct);
router.use(productVideoRoutes);

export default router;
