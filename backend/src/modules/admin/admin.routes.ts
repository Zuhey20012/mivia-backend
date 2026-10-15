import { Router } from "express";
import { auth, requireRole } from "../../middleware/auth";
import {
  getStats, getUsers, banUser,
  getVendors, approveVendor, rejectVendor, setVendorCommission, vendorCommissionHistory,
  getCouriers, approveCourier, suspendCourier,
  getOrders,
} from "./admin.controller";
import moderationRoutes from "./moderation.routes";
import promoRoutes from "../promos/promos.routes";
import { getSystemStatus } from "./system";
import { launchDemand } from "../me/launchAlerts";
import { getAnalytics } from "./analytics";
import { adminDac7, adminDac7Csv, adminStoreStatement } from "../sellers/admin.sellers";

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
router.patch("/vendors/:id/commission",  setVendorCommission);     // { commissionRate: 0–0.5 }, new orders only, audited
router.get("/vendors/:id/commission-history", vendorCommissionHistory);
router.get("/couriers",               getCouriers);
router.patch("/couriers/:id/approve", approveCourier);
router.patch("/couriers/:id/suspend", suspendCourier);
router.get("/orders",                 getOrders);
router.get("/analytics",              getAnalytics);          // ?from=YYYY-MM-DD&to=YYYY-MM-DD (Finnish days; default last 28)
router.get("/dac7",                   adminDac7);             // ?year=YYYY: DAC7 seller report (TIN decrypted, admin only)
router.get("/dac7.csv",               adminDac7Csv);
router.get("/stores/:id(\\d+)/statements", adminStoreStatement); // ?month=YYYY-MM
router.use(moderationRoutes);
router.use(promoRoutes); // /promo-codes

export default router;
