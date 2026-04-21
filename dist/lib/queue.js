"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.assignmentQueue = void 0;
const bullmq_1 = require("bullmq");
const env_1 = require("../config/env");
const redisConnection = {
    host: new URL(env_1.env.redisUrl).hostname,
    port: Number(new URL(env_1.env.redisUrl).port) || 6379,
};
exports.assignmentQueue = new bullmq_1.Queue("assignments", {
    connection: redisConnection,
    defaultJobOptions: {
        attempts: 5,
        backoff: { type: "exponential", delay: 30000 },
        removeOnComplete: 100,
        removeOnFail: 50,
    },
});
