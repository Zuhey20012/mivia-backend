import { Router } from "express";
import { listStores, getStore, getMyStore, createStore, updateStore } from "./stores.controller";
import { auth, optionalAuth, requireRole } from "../../middleware/auth";

const router = Router();

router.get("/",        listStores);
router.get("/my",     auth, requireRole("VENDOR"), getMyStore);
router.get("/:id(\\d+)", optionalAuth, getStore);
router.post("/",       auth, requireRole("VENDOR"), createStore);
router.patch("/:id(\\d+)", auth, requireRole("VENDOR"), updateStore);

export default router;
