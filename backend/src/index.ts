import "dotenv/config";
import "./instrument"; // optional Sentry (SENTRY_DSN), loaded before express and http
import express from "express";
import http from "http";
import cors from "cors";
import pino from "pino";
import pinoHttp from "pino-http";
import helmet from "helmet";
import compression from "compression";
import { env } from "./config/env";
import { errorHandler } from "./middleware/errorHandler";
import { notFound } from "./middleware/notFound";
import { globalLimiter } from "./middleware/rateLimiter";
import { initSocket } from "./lib/socket";
import { genReqId, requestContextMiddleware } from "./lib/requestContext";
import { metricsMiddleware, startLatencyLog } from "./lib/metrics";
import { setupSentryErrorHandler } from "./lib/sentry";
import { installGracefulShutdown } from "./lib/lifecycle";
import { startQueueWorker } from "./lib/queue";
import { idempotencyRoutes } from "./middleware/idempotency";
import { publicCacheRoutes } from "./middleware/httpCache";
import { opsRoutes } from "./modules/ops/ops.routes";
import { scale } from "./config/scale";

// Routes
import authRoutes     from "./modules/auth/auth.routes";
import storesRoutes   from "./modules/stores/stores.routes";
import sellerRoutes   from "./modules/sellers/sellers.routes";
import productsRoutes from "./modules/products/products.routes";
import ordersRoutes   from "./modules/orders/orders.routes";
import courierRoutes  from "./modules/orders/courier.routes";
import adminRoutes    from "./modules/admin/admin.routes";
import paymentsRoutes from "./modules/payments/payments.routes";
import mediaRoutes    from "./modules/media/media.routes";
import dropsRoutes, { shareRouter } from "./modules/drops/drops.routes";
import meRoutes       from "./modules/me/me.routes";
import { launchAlertRoutes } from "./modules/me/launchAlerts";
import { safetyRoutes } from "./modules/me/safety";
import referralRoutes from "./modules/referrals/referrals.routes";
import { shareRoutes } from "./modules/share/share.routes";
import appConfigRoutes from "./modules/appConfig/appConfig.routes";
import { integrationStatus } from "./modules/admin/system";
import payoutsRoutes  from "./modules/payouts/payouts.routes";
import legalRoutes    from "./modules/legal/legal.routes";
import { ensureLegalVersions } from "./modules/legal/legalDocs";
import supportRoutes  from "./modules/support/support.routes";
import importRoutes, { csvBodyParser } from "./modules/imports/imports.routes";
import { failStaleImports } from "./modules/imports/imports.service";
import { startScheduler } from "./services/scheduler";

const logger = pino({ level: env.logLevel });
const app    = express();
const server = http.createServer(app);
initSocket(server);

// Render (and most PaaS) sit behind one proxy hop; needed for per-client rate limiting.
app.set("trust proxy", 1);
app.disable("x-powered-by");

// One log line per request with a request id; tokens, cookies and bodies are never logged.
app.use(pinoHttp({
  logger,
  genReqId, // X-Request-Id in (when well-formed) and out
  redact: ["req.headers.authorization", "req.headers.cookie", "req.headers['stripe-signature']"],
  // Status code only: response headers are the same on every request and only bloat the logs
  serializers: {
    req: (req) => ({ id: req.id, method: req.method, url: req.url?.split("?")[0] }),
    res: (res) => ({ statusCode: res.statusCode }),
  },
  autoLogging: { ignore: (req) => req.url === "/health" },
}));
app.use(requestContextMiddleware); // logs and error reports of this request carry its id
app.use(metricsMiddleware);        // per-route counts and latency (GET /api/v1/admin/metrics, 5-minute log summary)

app.use(helmet());
app.use(cors({
  // Mobile apps send no Origin header and are unaffected; browsers must be on the allow-list.
  origin: env.allowedOrigins.length ? env.allowedOrigins : false,
  credentials: true,
}));
app.use(compression()); // br or gzip, whichever the client accepts

// Stripe and Cloudinary webhooks need the raw body, so they are mounted before the JSON parser.
app.use("/api/v1", paymentsRoutes);
app.use("/api/v1", mediaRoutes);

// CSV catalogue import: up to 1 MB of CSV text, so this one route gets its own larger body limit
app.use("/api/v1/products/import/csv", ...csvBodyParser);
app.use(express.json({ limit: "100kb" }));
app.use(globalLimiter);

// /health (liveness), /health/ready (database + Redis when configured) and /api/v1/admin/metrics
app.use(opsRoutes);
// Idempotency-Key on order, handover, refund and payout routes; Cache-Control on public GETs
app.use("/api/v1", idempotencyRoutes);
app.use(publicCacheRoutes);

// API routes. Courier routes come before orders so /orders/available etc. are matched first.
app.use("/api/v1/auth",   authRoutes);
app.use("/api/v1/stores", storesRoutes);
app.use("/api/v1/stores", sellerRoutes); // /stores/my/tax-info, /stores/my/statements
app.use("/api/v1",        importRoutes); // /products/import/* (before /products/:id routes)
app.use("/api/v1",        productsRoutes);
app.use("/api/v1",        courierRoutes);
app.use("/api/v1",        ordersRoutes);
app.use("/api/v1",        dropsRoutes);
app.use("/api/v1",        meRoutes);
app.use("/api/v1",        launchAlertRoutes);
app.use("/api/v1",        safetyRoutes); // /me/blocks, /reviews/:id/report, /admin/reviews/reported (before /admin)
app.use("/api/v1",        referralRoutes); // /me/referral
app.use("/api/v1",        appConfigRoutes);
app.use("/api/v1",        payoutsRoutes);
app.use("/api/v1",        supportRoutes);
app.use("/api/v1/admin",  adminRoutes);
app.use(shareRouter); // public share pages: /d/:id
app.use(shareRoutes); // /s/:storeId, /r/:code and /.well-known/assetlinks.json
app.use(legalRoutes); // public legal pages: /legal/privacy, /legal/terms, …

app.use(notFound);
setupSentryErrorHandler(app); // no-op without SENTRY_DSN
app.use(errorHandler);

server.keepAliveTimeout = 65_000; // longer than typical load-balancer idle timeouts
server.headersTimeout = 66_000;
server.listen(env.port, () => {
  logger.info(`Malvoya API v2.11 listening on port ${env.port} (${env.nodeEnv})`);
  // Yes/no per integration (never secrets), so the deploy log shows at a glance what is switched on
  const on = integrationStatus();
  logger.info({ integrations: Object.fromEntries(Object.entries(on).map(([k, v]) => [k, "mode" in v ? v.mode : v.configured ? "on" : "off"])) }, "Integrations");
  // WORKER_MODE=api (with Redis): a separate `node dist/worker.js` runs the scheduler and the queued jobs
  if (process.env.DISABLE_SCHEDULER !== "true" && scale.workerMode === "inline") startScheduler();
  if (scale.workerMode === "inline") startQueueWorker(); // only does something with REDIS_URL
  if (scale.workerModeRequested === "api" && scale.workerMode !== "api") logger.warn("WORKER_MODE=api needs REDIS_URL; running background work in this process");
  startLatencyLog();
  // Imports interrupted by a restart: marked FAILED once they have made no progress for 15 minutes
  failStaleImports().catch(() => {});
  // First version of each legal text (later changes take effect only when an admin publishes them)
  ensureLegalVersions().catch((e) => logger.error({ err: e?.message }, "Legal versions not recorded"));
});

// Zero-downtime deploys: stop taking new work, let in-flight requests finish, close sockets, queue, Redis and DB.
installGracefulShutdown(server, logger);
process.on("unhandledRejection", (reason) => logger.error({ reason }, "Unhandled promise rejection"));
