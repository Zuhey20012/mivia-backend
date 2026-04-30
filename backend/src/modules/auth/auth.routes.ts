import { Router } from "express";
import { register, login, refresh, logout, googleLogin, phoneLogin, appleLogin } from "./auth.controller";
import { authLimiter } from "../../middleware/rateLimiter";

const router = Router();

router.post("/register", authLimiter, register);
router.post("/login",    authLimiter, login);
router.post("/google",   authLimiter, googleLogin);
router.post("/phone",    authLimiter, phoneLogin);
router.post("/apple",    authLimiter, appleLogin);
router.post("/refresh",  refresh);
router.post("/logout",   logout);

export default router;
