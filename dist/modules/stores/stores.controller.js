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
exports.listStores = listStores;
exports.getStore = getStore;
exports.createStore = createStore;
exports.updateStore = updateStore;
const stores_schema_1 = require("./stores.schema");
const storesService = __importStar(require("./stores.service"));
async function listStores(req, res) {
    try {
        const query = stores_schema_1.storeQuerySchema.parse(req.query);
        const data = await storesService.getStores(query);
        res.json({ ok: true, ...data });
    }
    catch (e) {
        res.status(400).json({ ok: false, error: e.message });
    }
}
async function getStore(req, res) {
    try {
        const store = await storesService.getStoreById(Number(req.params.id));
        res.json({ ok: true, store });
    }
    catch {
        res.status(404).json({ ok: false, error: "Store not found" });
    }
}
async function createStore(req, res) {
    const result = stores_schema_1.createStoreSchema.safeParse(req.body);
    if (!result.success)
        return res.status(400).json({ ok: false, errors: result.error.flatten() });
    try {
        const store = await storesService.createStore(req.user.id, result.data);
        res.status(201).json({ ok: true, store });
    }
    catch (e) {
        res.status(409).json({ ok: false, error: e.message });
    }
}
async function updateStore(req, res) {
    const result = stores_schema_1.updateStoreSchema.safeParse(req.body);
    if (!result.success)
        return res.status(400).json({ ok: false, errors: result.error.flatten() });
    try {
        const store = await storesService.updateStore(Number(req.params.id), req.user.id, result.data);
        res.json({ ok: true, store });
    }
    catch (e) {
        res.status(e.message === "Forbidden" ? 403 : 404).json({ ok: false, error: e.message });
    }
}
