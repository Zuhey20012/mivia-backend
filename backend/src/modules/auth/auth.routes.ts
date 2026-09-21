import { Router } from "express";
import { register, login, refresh, logout, googleLogin, phoneLogin, appleLogin, sendOtpHandler, verifyOtpHandler, deleteMe, exportMyData } from "./auth.controller";
import { authLimiter } from "../../middleware/rateLimiter";
import { auth } from "../../middleware/auth";

const router = Router();

router.post("/register",   authLimiter, register);
router.post("/login",      authLimiter, login);
router.post("/otp/send",   authLimiter, sendOtpHandler);
router.post("/otp/verify", authLimiter, verifyOtpHandler);
router.post("/google",     authLimiter, googleLogin);
router.post("/phone",      authLimiter, phoneLogin);
router.post("/apple",      authLimiter, appleLogin);
router.post("/refresh",    refresh);
router.post("/logout",     logout);

router.delete("/me",       auth, deleteMe);
router.get("/me/data",     auth, exportMyData);

export default router;
