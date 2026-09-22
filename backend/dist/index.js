"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
require("dotenv/config");
const express_1 = __importDefault(require("express"));
const http_1 = __importDefault(require("http"));
const cors_1 = __importDefault(require("cors"));
const pino_1 = __importDefault(require("pino"));
const helmet_1 = __importDefault(require("helmet"));
const env_1 = require("./config/env");
const errorHandler_1 = require("./middleware/errorHandler");
const notFound_1 = require("./middleware/notFound");
const rateLimiter_1 = require("./middleware/rateLimiter");
const socket_1 = require("./lib/socket");
// Routes
const auth_routes_1 = __importDefault(require("./modules/auth/auth.routes"));
const stores_routes_1 = __importDefault(require("./modules/stores/stores.routes"));
const products_routes_1 = __importDefault(require("./modules/products/products.routes"));
const orders_routes_1 = __importDefault(require("./modules/orders/orders.routes"));
const admin_routes_1 = __importDefault(require("./modules/admin/admin.routes"));
const courier_routes_1 = __importDefault(require("./modules/orders/courier.routes"));
const raas_routes_1 = __importDefault(require("./modules/orders/raas.routes"));
const apparel_mcp_server_1 = require("./mcp/apparel_mcp_server");
const notificationDeliveryService_1 = require("./services/notificationDeliveryService");
const logger = (0, pino_1.default)({ level: env_1.env.logLevel });
const app = (0, express_1.default)();
const server = http_1.default.createServer(app);
(0, socket_1.initSocket)(server);
// Middleware
app.use((0, helmet_1.default)());
app.use((0, cors_1.default)({
    origin: env_1.env.allowedOrigins.includes("*") ? "*" : env_1.env.allowedOrigins,
    credentials: true,
}));
if (env_1.env.nodeEnv === "production" && env_1.env.allowedOrigins.includes("*")) {
    logger.warn("SECURITY WARNING: CORS is wide open (*) in production environment");
}
app.use(express_1.default.json());
app.use(rateLimiter_1.globalLimiter);
// Health check
app.get("/health", (_req, res) => res.json({ ok: true, status: "healthy", version: "2.0.0" }));
// API routes
app.use("/api/v1/auth", auth_routes_1.default);
app.use("/api/v1/stores", stores_routes_1.default);
app.use("/api/v1", products_routes_1.default);
app.use("/api/v1", orders_routes_1.default);
app.use("/api/v1", courier_routes_1.default);
app.use("/api/v1", raas_routes_1.default);
app.use("/api/v1", apparel_mcp_server_1.mcpRouter);
app.use("/api/v1/admin", admin_routes_1.default);
// Real multi-channel notification dispatch webhook (SMS & Email tracking)
app.post("/api/v1/notifications/dispatch", async (req, res) => {
    const { event, orderId, amount, paymentMethod, email, phone, name, address, items, code, channel } = req.body;
    logger.info({ event, orderId, amount, email, phone, code, channel }, "📨 Realtime Notification Webhook Received via Backend");
    const result = await (0, notificationDeliveryService_1.dispatchNotifications)({
        event: event || "ORDER_PAYMENT_CONFIRMED",
        orderId: orderId || `MLV-${Date.now().toString().slice(-6)}`,
        amount: Number(amount) || 0,
        paymentMethod: paymentMethod || "Bank-Grade Card / SEPA",
        email: email || "",
        phone: phone || "",
        name,
        address,
        items,
        code,
        channel,
    });
    return res.status(200).json(result);
});
// Real launch database cleanup (purges fake seed demo stores, products, couriers)
app.all("/api/v1/admin/purge-seed", async (req, res) => {
    const purgeKey = req.headers["x-purge-key"] || req.query.key;
    if (!process.env.ADMIN_PURGE_SECRET || purgeKey !== process.env.ADMIN_PURGE_SECRET) {
        return res.status(403).json({ error: "Invalid purge key" });
    }
    try {
        const { prisma } = await Promise.resolve().then(() => __importStar(require("./lib/prisma")));
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
    }
    catch (err) {
        return res.status(500).json({ error: err.message });
    }
});
// Auto-purge demo data on startup to guarantee clean production state
async function autoPurgeDemoData() {
    try {
        const { prisma } = await Promise.resolve().then(() => __importStar(require("./lib/prisma")));
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
    }
    catch (e) {
        console.error("Auto-purge demo check:", e);
    }
}
autoPurgeDemoData();
// Error handling
app.use(notFound_1.notFound);
app.use(errorHandler_1.errorHandler);
const port = env_1.env.port;
server.listen(port, () => {
    logger.info(`Ã°Å¸Å¡â‚¬ MALVOYA backend v2.0 listening on port ${port}`);
});
