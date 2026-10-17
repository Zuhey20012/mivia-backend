import { Router } from "express";
import { register, login, refresh, logout, googleLogin, googleLink, googleUnlink, phoneLogin, appleLogin, sendOtpHandler, verifyOtpHandler, deleteMe, exportMyData, forgotPasswordHandler, resetPasswordHandler, changePasswordHandler } from "./auth.controller";
import { authLimiter, passwordForgotIpLimiter, passwordForgotEmailLimiter, passwordResetLimiter } from "../../middleware/rateLimiter";
import { auth } from "../../middleware/auth";

const router = Router();

router.post("/register",   authLimiter, register);
router.post("/login",      authLimiter, login);
router.post("/otp/send",   authLimiter, sendOtpHandler);
router.post("/otp/verify", authLimiter, verifyOtpHandler);
router.post("/google",     authLimiter, googleLogin);
router.post("/google/link",   authLimiter, auth, googleLink);
router.delete("/google/link", auth, googleUnlink);
router.post("/phone",      authLimiter, phoneLogin);
router.post("/apple",      authLimiter, appleLogin);
// Forgot password: a 6-digit code by email (15 min, 5 tries), limited per client and per address
router.post("/password/forgot", passwordForgotIpLimiter, passwordForgotEmailLimiter, forgotPasswordHandler);
router.post("/password/reset",  passwordResetLimiter, resetPasswordHandler);
// Signed-in change; keeps this session and ends the others
router.post("/password/change", passwordResetLimiter, auth, changePasswordHandler);
router.post("/refresh",    refresh);
router.post("/logout",     logout);

router.delete("/me",       auth, deleteMe);
router.get("/me/data",     auth, exportMyData);

export default router;
