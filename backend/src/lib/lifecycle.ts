import type { Server } from "http";
import type { Logger } from "pino";
import { scale } from "../config/scale";
import { prisma, pgPool } from "./prisma";
import { getIo } from "./socket";
import { closeRedis } from "./redis";
import { stopQueue } from "./queue";
import { flushSentry } from "./sentry";
import { stopLatencyLog, rollWindow } from "./metrics";
import { stopScheduler } from "../services/scheduler";
import { markDraining } from "../modules/ops/ops.routes";

/**
 * Graceful shutdown (SIGTERM from Render on every deploy, scale-down or restart):
 *  1. readiness turns 503 and the scheduler stops starting jobs;
 *  2. the HTTP server stops accepting connections; idle keep-alive connections are closed, requests in flight finish;
 *  3. sockets are disconnected (the apps reconnect to another instance);
 *  4. the queue worker finishes its running jobs, then Redis, the database pool and Sentry are closed.
 * After SHUTDOWN_TIMEOUT_MS (25 s; Render waits 30 s) whatever is left is cut and the process exits 1.
 */
let shuttingDown = false;

export function installGracefulShutdown(server: Server | null, logger: Logger) {
  const shutdown = (signal: string) => {
    if (shuttingDown) return;
    shuttingDown = true;
    logger.info({ signal }, "Shutting down gracefully");
    markDraining();
    stopScheduler();
    const hardStop = setTimeout(() => {
      logger.warn("Shutdown timed out; closing remaining connections");
      server?.closeAllConnections?.();
      process.exit(1);
    }, scale.shutdownTimeoutMs);
    hardStop.unref();

    const closeRest = async () => {
      stopLatencyLog();
      rollWindow(); // last latency summary of this instance
      await stopQueue().catch(() => {});
      await closeRedis().catch(() => {});
      await prisma.$disconnect().catch(() => {});
      await pgPool.end().catch(() => {});
      await flushSentry();
      logger.info("Shutdown complete");
      process.exit(0);
    };

    if (!server) { closeRest(); return; }
    // Stop accepting; the callback runs once every in-flight request has finished. Keep-alive connections are closed
    // as soon as they go idle (a response sent while draining also says Connection: close).
    server.on("request", (_req, res) => res.setHeader("Connection", "close"));
    server.close(() => { clearInterval(sweep); closeRest(); });
    server.closeIdleConnections?.();
    const sweep = setInterval(() => server.closeIdleConnections?.(), 250);
    sweep.unref();
    // Disconnects every socket (does not wait for the HTTP server, which is already closing)
    const io = getIo();
    if (io) { io.disconnectSockets(true); (io as any).engine?.close?.(); }
  };
  process.on("SIGTERM", () => shutdown("SIGTERM"));
  process.on("SIGINT", () => shutdown("SIGINT"));
}
