import pino from "pino";
import { prisma } from "../lib/prisma";
import { env } from "../config/env";
import { mediaConfigured } from "../lib/cloudinary";
import { processDuePayouts } from "../modules/payouts/payouts.service";
import { checkProcessingDrops } from "../modules/drops/drops.service";
import { checkProcessingProductVideos } from "../modules/products/productVideos";
import { purgeOldDeliveryProofs } from "../modules/orders/orders.service";
import { runOrderWatchdog } from "./orderWatchdog";

const logger = pino({ name: "scheduler" });

type Job = { name: string; everyMs: number; enabled: () => boolean; run: () => Promise<unknown> };

const jobs: Job[] = [
  { name: "order-watchdog", everyMs: 60_000, enabled: () => true, run: runOrderWatchdog },
  { name: "payouts", everyMs: 10 * 60_000, enabled: () => !!env.stripeSecretKey, run: processDuePayouts },
  { name: "drop-processing", everyMs: 2 * 60_000, enabled: mediaConfigured, run: checkProcessingDrops },
  { name: "product-video-processing", everyMs: 2 * 60_000, enabled: mediaConfigured, run: checkProcessingProductVideos },
  { name: "delivery-proof-purge", everyMs: 6 * 60 * 60_000, enabled: mediaConfigured, run: purgeOldDeliveryProofs },
  {
    name: "expired-sign-in-codes", everyMs: 60 * 60_000, enabled: () => true,
    run: () => prisma.otpCode.deleteMany({ where: { expiresAt: { lt: new Date() } } }),
  },
];

/**
 * Takes a time-limited lease on the job. A row lock survives connection pooling (unlike
 * session advisory locks), and a crashed instance's lease simply expires.
 */
async function acquire(name: string, leaseMs: number) {
  const until = new Date(Date.now() + leaseMs);
  const rows = await prisma.$queryRaw<{ name: string }[]>`
    INSERT INTO "JobLease" ("name", "lockedUntil") VALUES (${name}, ${until})
    ON CONFLICT ("name") DO UPDATE SET "lockedUntil" = ${until}
    WHERE "JobLease"."lockedUntil" < NOW()
    RETURNING "name"`;
  return rows.length > 0;
}

/** Keeps the lease until just before the next run, so a fleet of instances runs each job about once per interval. */
async function release(name: string, everyMs: number) {
  const until = new Date(Date.now() + everyMs * 0.9);
  await prisma.$executeRaw`UPDATE "JobLease" SET "lockedUntil" = ${until}, "lastRunAt" = NOW() WHERE "name" = ${name}`;
}

const timers: NodeJS.Timeout[] = [];

export function startScheduler() {
  for (const job of jobs) {
    const tick = async () => {
      if (!job.enabled()) return;
      try {
        if (!(await acquire(job.name, Math.max(job.everyMs, 5 * 60_000)))) return;
        try {
          await job.run();
        } finally {
          await release(job.name, job.everyMs);
        }
      } catch (err: any) {
        logger.error({ job: job.name, err: err?.message }, "Background job failed");
      }
    };
    // Spread the first runs out a little after start-up
    timers.push(setTimeout(tick, 15_000 + Math.random() * 30_000).unref() as unknown as NodeJS.Timeout);
    timers.push(setInterval(tick, job.everyMs).unref() as unknown as NodeJS.Timeout);
  }
}

export function stopScheduler() {
  for (const t of timers) clearTimeout(t);
}
