import { Router } from "express";
import { register, login, refresh, logout } from "./auth.controller";
import { authLimiter } from "../../middleware/rateLimiter";

const router = Router();

router.post("/register", authLimiter, register);
router.post("/login",    authLimiter, login);
router.post("/refresh",  refresh);
router.post("/logout",   logout);

export default router;
