import "dotenv/config";
import express from "express";
import http from "http";
import cors from "cors";
import pino from "pino";
import { env } from "./config/env";
import { errorHandler } from "./middleware/errorHandler";
import { notFound } from "./middleware/notFound";
import { globalLimiter } from "./middleware/rateLimiter";
import { initSocket } from "./lib/socket";

// Routes
import authRoutes     from "./modules/auth/auth.routes";
import storesRoutes   from "./modules/stores/stores.routes";
import productsRoutes from "./modules/products/products.routes";
import ordersRoutes   from "./modules/orders/orders.routes";

const logger = pino({ level: env.logLevel });
const app    = express();
const server = http.createServer(app);
initSocket(server);

// Middleware
app.use(cors({ origin: "*" }));
app.use(express.json());
app.use(globalLimiter);

// Health check
app.get("/health", (_req, res) => res.json({ ok: true, status: "healthy", version: "2.0.0" }));

// API routes
app.use("/api/v1/auth",     authRoutes);
app.use("/api/v1/stores",   storesRoutes);
app.use("/api/v1",          productsRoutes);
app.use("/api/v1",          ordersRoutes);

// Error handling
app.use(notFound);
app.use(errorHandler);

const port = env.port;
server.listen(port, () => {
  logger.info(`Ã°Å¸Å¡â‚¬ MALVOYA backend v2.0 listening on port ${port}`);
});
