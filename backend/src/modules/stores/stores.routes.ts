import { Router } from "express";
import { listStores, getStore, createStore, updateStore } from "./stores.controller";
import { auth, requireRole } from "../../middleware/auth";

const router = Router();

router.get("/",        listStores);
router.get("/:id",     getStore);
router.post("/",       auth, requireRole("VENDOR", "ADMIN"), createStore);
router.patch("/:id",   auth, requireRole("VENDOR", "ADMIN"), updateStore);

export default router;
