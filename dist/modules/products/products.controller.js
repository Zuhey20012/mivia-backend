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
Object.defineProperty(exports, "__esModule", { value: true });
exports.listProducts = listProducts;
exports.getProduct = getProduct;
exports.createProduct = createProduct;
exports.updateProduct = updateProduct;
exports.deleteProduct = deleteProduct;
const products_schema_1 = require("./products.schema");
const productsService = __importStar(require("./products.service"));
async function listProducts(req, res) {
    try {
        const query = products_schema_1.productQuerySchema.parse(req.query);
        const data = await productsService.getProductsByStore(Number(req.params.storeId), query);
        res.json({ ok: true, ...data });
    }
    catch (e) {
        res.status(400).json({ ok: false, error: e.message });
    }
}
async function getProduct(req, res) {
    try {
        const product = await productsService.getProductById(Number(req.params.id));
        res.json({ ok: true, product });
    }
    catch {
        res.status(404).json({ ok: false, error: "Product not found" });
    }
}
async function createProduct(req, res) {
    const result = products_schema_1.createProductSchema.safeParse(req.body);
    if (!result.success)
        return res.status(400).json({ ok: false, errors: result.error.flatten() });
    try {
        const store = await Promise.resolve().then(() => __importStar(require("../../lib/prisma"))).then(m => m.prisma.store.findUnique({ where: { ownerId: req.user.id } }));
        if (!store)
            return res.status(404).json({ ok: false, error: "Create your store first" });
        const product = await productsService.createProduct(store.id, result.data);
        res.status(201).json({ ok: true, product });
    }
    catch (e) {
        res.status(400).json({ ok: false, error: e.message });
    }
}
async function updateProduct(req, res) {
    const result = products_schema_1.updateProductSchema.safeParse(req.body);
    if (!result.success)
        return res.status(400).json({ ok: false, errors: result.error.flatten() });
    try {
        const product = await productsService.updateProduct(Number(req.params.id), req.user.id, result.data);
        res.json({ ok: true, product });
    }
    catch (e) {
        res.status(e.message === "Forbidden" ? 403 : 404).json({ ok: false, error: e.message });
    }
}
async function deleteProduct(req, res) {
    try {
        await productsService.deleteProduct(Number(req.params.id), req.user.id);
        res.json({ ok: true });
    }
    catch (e) {
        res.status(e.message === "Forbidden" ? 403 : 404).json({ ok: false, error: e.message });
    }
}
