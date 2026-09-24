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

  deliveryFeeCents:  299, // €2.99, VAT included
  returnWindowDays:  14,  // statutory withdrawal period, counted from delivery
};
