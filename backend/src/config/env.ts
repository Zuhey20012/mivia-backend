import dotenv from "dotenv";
dotenv.config();

const nodeEnv = process.env.NODE_ENV || "development";
const isProduction = nodeEnv === "production";

function required(name: string, minLength = 1): string {
  const value = process.env[name] || "";
  if (value.length < minLength) {
    throw new Error(`Missing or too short environment variable ${name} (min ${minLength} chars)`);
  }
  return value;
}

// Secrets must be real in every environment; a blank JWT secret would let anyone forge tokens.
const jwtSecret = required("JWT_SECRET", 32);
const jwtRefreshSecret = required("JWT_REFRESH_SECRET", 32);
if (jwtSecret === jwtRefreshSecret) {
  throw new Error("JWT_SECRET and JWT_REFRESH_SECRET must be different");
}

const allowedOrigins = (process.env.ALLOWED_ORIGINS || "")
  .split(",")
  .map((o) => o.trim())
  .filter(Boolean);
if (isProduction && allowedOrigins.includes("*")) {
  throw new Error("ALLOWED_ORIGINS must list explicit origins in production (not *)");
}

function minutes(name: string, fallback: number) {
  const v = Number(process.env[name]);
  return Number.isFinite(v) && v > 0 ? v : fallback;
}

export const env = {
  port:         Number(process.env.PORT)          || 4000,
  nodeEnv,
  isProduction,
  databaseUrl:  process.env.DATABASE_URL          || "",
  redisUrl:     process.env.REDIS_URL             || "",
  jwtSecret,
  jwtRefreshSecret,
  jwtExpiresIn: process.env.JWT_EXPIRES_IN        || "15m",
  jwtRefreshExpiresIn: process.env.JWT_REFRESH_EXPIRES_IN || "7d",
  logLevel:     process.env.LOG_LEVEL             || "info",

  stripeSecretKey:      process.env.STRIPE_SECRET_KEY       || "",
  stripeWebhookSecret:  process.env.STRIPE_WEBHOOK_SECRET   || "",

  // Social Auth
  googleClientId:       process.env.GOOGLE_CLIENT_ID        || "",

  // CORS (browser clients only — the mobile apps are not subject to CORS)
  allowedOrigins,

  // Public address of this API (share links, Stripe onboarding return pages, media webhooks)
  publicApiUrl: (process.env.PUBLIC_API_URL || "https://malvoya-api-eu.onrender.com").replace(/\/+$/, ""),
  playStoreUrl: "https://play.google.com/store/apps/details?id=com.malvoya.customer",

  // Media (photos and videos). Without these, uploads are switched off and say so.
  cloudinary: {
    cloudName: process.env.CLOUDINARY_CLOUD_NAME || "",
    apiKey:    process.env.CLOUDINARY_API_KEY    || "",
    apiSecret: process.env.CLOUDINARY_API_SECRET || "",
  },

  // Push notifications: a Firebase service-account key (raw JSON or base64 of it)
  firebaseServiceAccount: process.env.FIREBASE_SERVICE_ACCOUNT || "",

  deliveryFeeCents:  299, // €2.99, VAT included
  returnWindowDays:  14,  // statutory withdrawal period, counted from delivery
  // Share of the delivery fee paid to the courier (1 = the whole fee)
  courierFeeShare:   Math.min(1, Math.max(0, Number(process.env.COURIER_FEE_SHARE ?? 1))),
  // Store payouts are released once the return window has passed
  storePayoutHoldDays: 15,

  // Order watchdog (minutes). Nobody waits forever: unpaid checkouts release their stock, stores
  // that do not answer and orders no courier takes are cancelled with a full refund.
  orderTimers: {
    checkoutHold:       minutes("CHECKOUT_HOLD_MINUTES", 30),
    storeReminder:      minutes("STORE_REMINDER_MINUTES", 3),
    storeAccept:        minutes("STORE_ACCEPT_MINUTES", 10),
    courierReoffer:     minutes("COURIER_REOFFER_MINUTES", 2),
    courierDelayNotice: minutes("COURIER_DELAY_NOTICE_MINUTES", 15),
    courierSearch:      minutes("COURIER_SEARCH_MINUTES", 45),
  },
};
