import rateLimit from "express-rate-limit";

export const globalLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 600,                 // per client IP (requires app.set("trust proxy") behind Render)
  standardHeaders: true,
  legacyHeaders: false,
  message: { ok: false, error: "Too many requests, please try again later." },
});

export const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 20, // stricter for login / register / OTP
  standardHeaders: true,
  legacyHeaders: false,
  message: { ok: false, error: "Too many attempts, please try again later." },
});
