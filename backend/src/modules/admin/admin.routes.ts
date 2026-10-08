import { Router } from "express";
import { auth, requireRole } from "../../middleware/auth";
import {
  getStats, getUsers, banUser,
  getVendors, approveVendor, rejectVendor,
  getCouriers, approveCourier, suspendCourier,
  getOrders,
} from "./admin.controller";
import moderationRoutes from "./moderation.routes";
import { getSystemStatus } from "./system";
import { launchDemand } from "../me/launchAlerts";

const router = Router();

// All admin routes require authentication + ADMIN role
router.use(auth, requireRole("ADMIN"));

router.get("/stats",                  getStats);
router.get("/system",                 getSystemStatus);
router.get("/launch-demand",          launchDemand);
router.get("/users",                  getUsers);
router.delete("/users/:id",           banUser);
router.get("/vendors",                getVendors);
router.patch("/vendors/:id/approve",  approveVendor);
router.delete("/vendors/:id",         rejectVendor);
router.get("/couriers",               getCouriers);
router.patch("/couriers/:id/approve", approveCourier);
router.patch("/couriers/:id/suspend", suspendCourier);
router.get("/orders",                 getOrders);
router.use(moderationRoutes);

export default router;
