import "dotenv/config";
import express from "express";
import http from "http";
import crypto from "crypto";
import cors from "cors";
import pino from "pino";
import pinoHttp from "pino-http";
import helmet from "helmet";
import compression from "compression";
import { env } from "./config/env";
import { errorHandler } from "./middleware/errorHandler";
import { notFound } from "./middleware/notFound";
import { globalLimiter } from "./middleware/rateLimiter";
import { initSocket, getIo } from "./lib/socket";
import { prisma } from "./lib/prisma";

// Routes
import authRoutes     from "./modules/auth/auth.routes";
import storesRoutes   from "./modules/stores/stores.routes";
import productsRoutes from "./modules/products/products.routes";
import ordersRoutes   from "./modules/orders/orders.routes";
import courierRoutes  from "./modules/orders/courier.routes";
import adminRoutes    from "./modules/admin/admin.routes";
import paymentsRoutes from "./modules/payments/payments.routes";

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
  genReqId: (req, res) => {
    const id = (req.headers["x-request-id"] as string) || crypto.randomUUID();
    res.setHeader("x-request-id", id);
    return id;
  },
  redact: ["req.headers.authorization", "req.headers.cookie", "req.headers['stripe-signature']"],
  serializers: { req: (req) => ({ id: req.id, method: req.method, url: req.url?.split("?")[0] }) },
  autoLogging: { ignore: (req) => req.url === "/health" },
}));

app.use(helmet());
app.use(cors({
  // Mobile apps send no Origin header and are unaffected; browsers must be on the allow-list.
  origin: env.allowedOrigins.length ? env.allowedOrigins : false,
  credentials: true,
}));
app.use(compression());

// Stripe webhook needs the raw body, so it is mounted before the JSON parser.
app.use("/api/v1", paymentsRoutes);

app.use(express.json({ limit: "100kb" }));
app.use(globalLimiter);

// Liveness: the process is up. Readiness: it can also reach the database.
app.get("/health", (_req, res) => res.json({ ok: true, status: "healthy", version: "2.2.0" }));
app.get("/health/ready", async (_req, res) => {
  try {
    await prisma.$queryRaw`SELECT 1`;
    res.json({ ok: true, database: "up" });
  } catch {
    res.status(503).json({ ok: false, database: "down" });
  }
});

// API routes. Courier routes come before orders so /orders/available etc. are matched first.
app.use("/api/v1/auth",   authRoutes);
app.use("/api/v1/stores", storesRoutes);
app.use("/api/v1",        productsRoutes);
app.use("/api/v1",        courierRoutes);
app.use("/api/v1",        ordersRoutes);
app.use("/api/v1/admin",  adminRoutes);

app.use(notFound);
app.use(errorHandler);

server.keepAliveTimeout = 65_000; // longer than typical load-balancer idle timeouts
server.headersTimeout = 66_000;
server.listen(env.port, () => {
  logger.info(`Malvoya API v2.2 listening on port ${env.port} (${env.nodeEnv})`);
});

// Zero-downtime deploys: stop taking new work, let in-flight requests finish, then exit.
let shuttingDown = false;
function shutdown(signal: string) {
  if (shuttingDown) return;
  shuttingDown = true;
  logger.info({ signal }, "Shutting down gracefully");
  getIo()?.close();
  server.close(async () => {
    await prisma.$disconnect().catch(() => {});
    process.exit(0);
  });
  setTimeout(() => process.exit(1), 25_000).unref();
}
process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT", () => shutdown("SIGINT"));
process.on("unhandledRejection", (reason) => logger.error({ reason }, "Unhandled promise rejection"));
