"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
require("dotenv/config");
const express_1 = __importDefault(require("express"));
const http_1 = __importDefault(require("http"));
const cors_1 = __importDefault(require("cors"));
const pino_1 = __importDefault(require("pino"));
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
const logger = (0, pino_1.default)({ level: env_1.env.logLevel });
const app = (0, express_1.default)();
const server = http_1.default.createServer(app);
(0, socket_1.initSocket)(server);
// Middleware
app.use((0, cors_1.default)({ origin: "*" }));
app.use(express_1.default.json());
app.use(rateLimiter_1.globalLimiter);
// Health check
app.get("/health", (_req, res) => res.json({ ok: true, status: "healthy", version: "2.0.0" }));
// API routes
app.use("/api/v1/auth", auth_routes_1.default);
app.use("/api/v1/stores", stores_routes_1.default);
app.use("/api/v1", products_routes_1.default);
app.use("/api/v1", orders_routes_1.default);
// Error handling
app.use(notFound_1.notFound);
app.use(errorHandler_1.errorHandler);
const port = env_1.env.port;
server.listen(port, () => {
    logger.info(`Ã°Å¸Å¡â‚¬ MALVOYA backend v2.0 listening on port ${port}`);
});
