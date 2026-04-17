"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.createServer = createServer;
const express_1 = __importDefault(require("express"));
const cors_1 = __importDefault(require("cors"));
const health_1 = __importDefault(require("./routes/health"));
const products_1 = __importDefault(require("./routes/products"));
const vendors_1 = __importDefault(require("./routes/vendors"));
const orders_1 = __importDefault(require("./routes/orders"));
const rentals_1 = __importDefault(require("./routes/rentals"));
const couriers_1 = __importDefault(require("./routes/couriers"));
async function createServer() {
    const app = (0, express_1.default)();
    app.use((0, cors_1.default)());
    app.use(express_1.default.json());
    app.use('/health', health_1.default);
    app.use('/products', products_1.default);
    app.use('/vendors', vendors_1.default);
    app.use('/orders', orders_1.default);
    app.use('/rentals', rentals_1.default);
    app.use('/couriers', couriers_1.default);
    return app;
}
