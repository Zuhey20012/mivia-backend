// Optional background worker: `node dist/worker.js` (a Render "background worker" with the same env vars as the API).
// Runs the queued jobs (push fan-out, emails, catalogue imports) and the scheduler (watchdog, payouts, reminders, …),
// so the web instances only serve requests. Needs REDIS_URL; set WORKER_MODE=api on the web service at the same time.
// Socket events from jobs reach the apps through the Redis emitter (lib/socket.ts).
import "dotenv/config";
import "./instrument";
import pino from "pino";
import { env } from "./config/env";
import { redisEnabled } from "./lib/redis";
import { startQueueWorker } from "./lib/queue";
import { installGracefulShutdown } from "./lib/lifecycle";
import { startLatencyLog } from "./lib/metrics";
import { startScheduler } from "./services/scheduler";
// Job definitions live in these modules; importing them registers the handlers
import "./lib/push";
import "./services/notificationDeliveryService";
import "./modules/imports/imports.service";

const logger = pino({ level: env.logLevel, name: "worker" });

if (!redisEnabled()) {
  logger.error("The worker needs REDIS_URL (without Redis the API runs background work itself). Exiting.");
  process.exit(1);
}

startQueueWorker();
if (process.env.DISABLE_SCHEDULER !== "true") startScheduler();
startLatencyLog();
installGracefulShutdown(null, logger);
logger.info("Malvoya worker started");
process.on("unhandledRejection", (reason: any) => logger.error({ reason: reason?.message ?? String(reason) }, "Unhandled promise rejection"));
