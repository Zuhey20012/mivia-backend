import { Router } from "express";
import { register, login, refresh, logout, firebaseLogin, firebaseLink } from "./auth.controller";
import { authLimiter } from "../../middleware/rateLimiter";
import { auth } from "../../middleware/auth";

const router = Router();

router.post("/register", authLimiter, register);
router.post("/login",    authLimiter, login);
router.post("/refresh",  refresh);
router.post("/logout",   logout);
router.post("/firebase",      authLimiter, firebaseLogin);
router.post("/firebase/link", authLimiter, auth, firebaseLink);

export default router;
