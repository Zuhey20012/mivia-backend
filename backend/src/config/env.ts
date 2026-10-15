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

/** Any positive number of hours (decimals allowed); anything else falls back to the default. */
const hours = minutes;

/** Non-negative whole cents from the environment; anything else falls back to the default (0 = off). */
function cents(name: string, fallback = 0) {
  const v = Number(process.env[name]);
  return Number.isInteger(v) && v >= 0 ? v : fallback;
}

/** Non-negative kilometres (decimals allowed) from the environment; anything else falls back to the default. */
function km(name: string, fallback: number) {
  const raw = process.env[name];
  const v = Number(raw);
  return raw !== undefined && raw !== "" && Number.isFinite(v) && v >= 0 && v <= 100 ? v : fallback;
}

/** Fee settings. Every lever is off (0) unless the owner sets it on Render. */
function pricingConfig() {
  const pct = Number(process.env.SERVICE_FEE_PERCENT);
  return {
    // Service fee: a percentage of the item subtotal, clamped to min/max (max 0 = no cap)
    serviceFeePercent:        Number.isFinite(pct) && pct > 0 ? Math.min(pct, 50) : 0,
    serviceFeeMinCents:       cents("SERVICE_FEE_MIN_CENTS"),
    serviceFeeMaxCents:       cents("SERVICE_FEE_MAX_CENTS"),
    // Small-order fee: charged when the item subtotal is below the threshold (threshold 0 = off)
    smallOrderThresholdCents: cents("SMALL_ORDER_THRESHOLD_CENTS"),
    smallOrderFeeCents:       cents("SMALL_ORDER_FEE_CENTS"),
  };
}
export type PricingConfig = ReturnType<typeof pricingConfig>;

/**
 * Courier pay per job (EU Platform Work Directive: pay must be explainable before a job is accepted).
 * Separate from what the customer pays for delivery. Defaults follow the October 2026 market research and
 * can be changed on Render (never in the apps); utils/courierPay.ts computes and explains the pay.
 *  formula:   base + per km × route km (straight line × road factor, rounded to 0.1 km), at least the
 *             minimum; plus the ride to the shop beyond the free km (set on acceptance); plus waiting at
 *             the shop beyond the free minutes (capped, set at pickup); plus the tip in full.
 *  fee_share: the old rule — COURIER_FEE_SHARE of the customer's delivery fee, plus the tip.
 */
function courierPayConfig() {
  const road = Number(process.env.COURIER_ROAD_FACTOR);
  const share = Number(process.env.COURIER_FEE_SHARE ?? 1);
  return {
    mode:              (process.env.COURIER_PAY_MODE === "fee_share" ? "fee_share" : "formula") as "formula" | "fee_share",
    baseCents:         cents("COURIER_PAY_BASE_CENTS", 450),     // pickup + drop-off
    perKmCents:        cents("COURIER_PAY_PER_KM_CENTS", 110),   // per km of the shop → customer route
    minCents:          cents("COURIER_PAY_MIN_CENTS", 650),      // guaranteed minimum for base + distance
    roadFactor:        Number.isFinite(road) && road >= 1 && road <= 3 ? road : 1.3, // straight line → road distance
    // Ride to the shop: the courier's position when accepting → shop (route km), paid beyond the free km
    approachFreeKm:    km("COURIER_APPROACH_FREE_KM", 2),
    approachPerKmCents: cents("COURIER_APPROACH_PER_KM_CENTS", 50),
    // Couriers further than this (straight line, from a fresh position) cannot accept a job; the paid ride is
    // capped at this distance too. Default = the dispatch radius.
    approachMaxKm:     km("COURIER_APPROACH_MAX_KM", 7.5),
    // Waiting at the shop, measured from "arrived at shop" to pickup
    waitFreeMinutes:   cents("COURIER_WAIT_FREE_MINUTES", 5),    // not paid
    waitPerMinCents:   cents("COURIER_WAIT_PER_MIN_CENTS", 20),  // per whole minute beyond the free minutes
    waitMaxCents:      cents("COURIER_WAIT_MAX_CENTS", 400),     // cap per job (400 = 20 paid minutes)
    feeShare:          Number.isFinite(share) ? Math.min(1, Math.max(0, share)) : 1, // fee_share mode only
  };
}
export type CourierPayConfig = ReturnType<typeof courierPayConfig>;

/**
 * Customer delivery fee by straight-line distance (utils/pricing.ts#deliveryFeeForDistance): the base fee
 * covers the first DELIVERY_FEE_BASE_KM, then per km, capped. Defaults keep the pre-2.7 prices; the owner
 * decides on new customer prices. Independent of courier pay.
 */
function deliveryFeeConfig() {
  return {
    baseCents:    cents("DELIVERY_FEE_BASE_CENTS", 190),
    baseKm:       km("DELIVERY_FEE_BASE_KM", 1.5),
    perKmCents:   cents("DELIVERY_FEE_PER_KM_CENTS", 50),
    maxCents:     cents("DELIVERY_FEE_MAX_CENTS", 690),
  };
}
export type DeliveryFeeConfig = ReturnType<typeof deliveryFeeConfig>;

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

  // Catalogue import: hosts ("host:port") the Shopify import may reach over plain http without the
  // public-address checks. TEST ONLY (the e2e suite's local mock); always empty in production.
  importAllowHosts: isProduction
    ? []
    : (process.env.IMPORT_ALLOW_HOSTS || "").split(",").map((h) => h.trim().toLowerCase()).filter(Boolean),

  // Push notifications: a Firebase service-account key (raw JSON or base64 of it)
  firebaseServiceAccount: process.env.FIREBASE_SERVICE_ACCOUNT || "",

  deliveryFeeCents:  299, // €2.99, VAT included: flat fee when the distance is unknown
  // Customer delivery fee by distance (DELIVERY_FEE_* env vars); see deliveryFeeConfig above
  deliveryFee:       deliveryFeeConfig(),
  returnWindowDays:  14,  // statutory withdrawal period, counted from delivery
  // Courier pay per job (formula or the old share of the delivery fee); see courierPayConfig above
  courierPay:        courierPayConfig(),
  // Service and small-order fees (all off by default)
  pricing: pricingConfig(),
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

  // Reserve & collect (hours, counted from when the store marked the order ready): the customer is reminded,
  // then an order nobody collected is cancelled with a full refund and its items go back into stock.
  pickupTimers: {
    reminderHours: hours("PICKUP_REMINDER_HOURS", 24),
    holdHours:     hours("PICKUP_HOLD_HOURS", 72),
    // Accepted pickup orders the store never marks ready are refunded after this
    readyHours:    hours("PICKUP_READY_HOURS", 24),
  },

  // Referrals: off while REFERRAL_DISCOUNT_CENTS is 0. The new customer gets the discount on their first order
  // (platform-funded, like a promo code); the referrer gets a one-time code worth REFERRAL_REWARD_CENTS once that
  // order is delivered (0 = no reward).
  referral: {
    discountCents: cents("REFERRAL_DISCOUNT_CENTS"),
    rewardCents:   cents("REFERRAL_REWARD_CENTS"),
  },

  // Android App Links: SHA-256 fingerprints of the customer app's signing certificates (comma-separated),
  // published at /.well-known/assetlinks.json. Empty = no verified links.
  androidAppSha256: (process.env.ANDROID_APP_SHA256 || "")
    .split(",")
    .map((f) => f.trim().toUpperCase())
    .filter((f) => /^([0-9A-F]{2}:){31}[0-9A-F]{2}$/.test(f)),
  androidCustomerPackage: "com.malvoya.customer",
};
