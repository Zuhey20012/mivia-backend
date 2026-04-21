"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.redis = void 0;
const ioredis_1 = __importDefault(require("ioredis"));
const env_1 = require("../config/env");
exports.redis = env_1.env.redisUrl ? new ioredis_1.default(env_1.env.redisUrl) : new ioredis_1.default({ lazyConnect: true });
exports.redis.on("error", (err) => {
    console.warn("[redis] connection error (continuing without redis):", err?.message || err);
});
