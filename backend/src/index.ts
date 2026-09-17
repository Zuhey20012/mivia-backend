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
import adminRoutes    from "./modules/admin/admin.routes";

const logger = pino({ level: env.logLevel });
const app    = express();
const server = http.createServer(app);
initSocket(server);

// Middleware
app.use(cors({
  origin: env.allowedOrigins.includes("*") ? "*" : env.allowedOrigins,
  credentials: true,
}));
app.use(express.json());
app.use(globalLimiter);

// Health check
app.get("/health", (_req, res) => res.json({ ok: true, status: "healthy", version: "2.0.0" }));

// API routes
app.use("/api/v1/auth",     authRoutes);
app.use("/api/v1/stores",   storesRoutes);
app.use("/api/v1",          productsRoutes);
app.use("/api/v1",          ordersRoutes);
app.use("/api/v1/admin",    adminRoutes);

// Real launch database cleanup (purges fake seed demo stores, products, couriers)
app.all("/api/v1/admin/purge-seed", async (req, res) => {
  const purgeKey = req.headers["x-purge-key"] || req.query.key;
  if (purgeKey !== "malvoya-purge-secret-2026") {
    return res.status(403).json({ error: "Invalid purge key" });
  }
  try {
    const { prisma } = await import("./lib/prisma");
    await prisma.orderItem.deleteMany({});
    await prisma.order.deleteMany({});
    await prisma.product.deleteMany({});
    await prisma.store.deleteMany({});
    await prisma.courier.deleteMany({});
    await prisma.user.deleteMany({
      where: {
        email: {
          in: ["sarah.crochet@malvoya.app", "leo.vintage@malvoya.app", "elena.green@malvoya.app", "customer@malvoya.app"]
        }
      }
    });
    return res.json({
      ok: true,
      message: "Successfully purged all seed stores, demo products, demo couriers, and test vendors from database."
    });
  } catch (err: any) {
    return res.status(500).json({ error: err.message });
  }
});

// Auto-purge demo data on startup to guarantee clean production state
async function autoPurgeDemoData() {
  try {
    const { prisma } = await import("./lib/prisma");
    const demoStores = await prisma.store.findMany({
      where: {
        name: { in: ["Sarah's Crochet Studio", "Leo's Retro Finds", "Elena's Eco Home"] }
      }
    });
    if (demoStores.length > 0) {
      const demoIds = demoStores.map(s => s.id);
      await prisma.product.deleteMany({ where: { storeId: { in: demoIds } } });
      await prisma.store.deleteMany({ where: { id: { in: demoIds } } });
      await prisma.user.deleteMany({
        where: { email: { in: ["sarah.crochet@malvoya.app", "leo.vintage@malvoya.app", "elena.green@malvoya.app"] } }
      });
      await prisma.courier.deleteMany({
        where: { name: { in: ["Mikael K.", "Aisha R."] } }
      });
      console.log("🧹 Auto-purged all demo seed stores and couriers successfully.");
    }
  } catch (e) {
    console.error("Auto-purge demo check:", e);
  }
}
autoPurgeDemoData();

// Error handling
app.use(notFound);
app.use(errorHandler);

const port = env.port;
server.listen(port, () => {
  logger.info(`Ã°Å¸Å¡â‚¬ MALVOYA backend v2.0 listening on port ${port}`);
});
