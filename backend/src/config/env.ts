import dotenv from "dotenv";
dotenv.config();

export const env = {
  port:         Number(process.env.PORT)          || 4000,
  nodeEnv:      process.env.NODE_ENV              || "development",
  databaseUrl:  process.env.DATABASE_URL          || "",
  redisUrl:     process.env.REDIS_URL             || "redis://127.0.0.1:6379",
  jwtSecret:    process.env.JWT_SECRET            || "",
  jwtRefreshSecret: process.env.JWT_REFRESH_SECRET || "",
  jwtExpiresIn: process.env.JWT_EXPIRES_IN        || "15m",
  jwtRefreshExpiresIn: process.env.JWT_REFRESH_EXPIRES_IN || "7d",
  logLevel:     process.env.LOG_LEVEL             || "info",

  cloudinaryCloud:  process.env.CLOUDINARY_CLOUD_NAME  || "",
  cloudinaryKey:    process.env.CLOUDINARY_API_KEY      || "",
  cloudinarySecret: process.env.CLOUDINARY_API_SECRET   || "",

  stripeSecretKey:      process.env.STRIPE_SECRET_KEY       || "",
  stripeWebhookSecret:  process.env.STRIPE_WEBHOOK_SECRET   || "",

  // Social Auth
  googleClientId:       process.env.GOOGLE_CLIENT_ID        || "",

  // CORS
  allowedOrigins:       (process.env.ALLOWED_ORIGINS || "*").split(","),

  deliveryFeeCents:  299, // $2.99
  commissionRate:    0.10, // 10%
  returnWindowDays:  7,
};
