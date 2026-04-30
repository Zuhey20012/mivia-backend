import { Queue } from "bullmq";
import { env } from "../config/env";

let assignmentQueue: Queue | null = null;

try {
  if (env.redisUrl && env.redisUrl !== "redis://127.0.0.1:6379" && env.nodeEnv !== "production") {
    const redisConnection = {
      host: new URL(env.redisUrl).hostname,
      port: Number(new URL(env.redisUrl).port) || 6379,
    };

    assignmentQueue = new Queue("assignments", {
      connection: redisConnection,
      defaultJobOptions: {
        attempts: 5,
        backoff: { type: "exponential", delay: 30_000 },
        removeOnComplete: 100,
        removeOnFail: 50,
      },
    });
  } else {
    console.log("⚠️  Redis not configured — courier assignment queue disabled (non-critical)");
  }
} catch (e) {
  console.log("⚠️  Redis connection failed — courier assignment queue disabled (non-critical)");
}

export { assignmentQueue };
