"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const bullmq_1 = require("bullmq");
const ioredis_1 = __importDefault(require("ioredis"));
const assignment_1 = require("../services/assignment");
const eta_1 = require("../services/eta");
const connection = new ioredis_1.default(process.env.REDIS_URL || 'redis://localhost:6379');
new bullmq_1.Worker('assignments', async (job) => {
    try {
        const { orderId } = job?.data ?? {};
        if (!orderId) {
            console.warn('assignmentWorker: missing orderId in job', job?.id);
            return;
        }
        const courier = await (0, assignment_1.assignCourierToOrder)(Number(orderId));
        const eta = (0, eta_1.calculateETA)(3.2);
        console.log('Worker assigned courier', courier, 'ETA', eta);
    }
    catch (err) {
        console.error('assignmentWorker error', err);
    }
}, { connection });
console.log('Assignment worker started');
