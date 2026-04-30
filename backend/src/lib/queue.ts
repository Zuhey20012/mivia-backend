import { Queue } from "bullmq";
import { env } from "../config/env";

const redisConnection = {
  host: new URL(env.redisUrl).hostname,
  port: Number(new URL(env.redisUrl).port) || 6379,
};

export const assignmentQueue = new Queue("assignments", {
  connection: redisConnection,
  defaultJobOptions: {
    attempts: 5,
    backoff: { type: "exponential", delay: 30_000 },
    removeOnComplete: 100,
    removeOnFail: 50,
  },
});
