import pino from "pino";
import { prisma } from "../lib/prisma";
import { env } from "../config/env";
import { mediaConfigured } from "../lib/cloudinary";
import { processDuePayouts } from "../modules/payouts/payouts.service";
import { checkProcessingDrops } from "../modules/drops/drops.service";
import { checkProcessingProductVideos } from "../modules/products/productVideos";
import { purgeOldDeliveryProofs } from "../modules/orders/orders.service";
import { runOrderWatchdog } from "./orderWatchdog";
import { failStaleImports } from "../modules/imports/imports.service";
import { purgeOldMessages } from "../modules/orders/chat";
import { sendTaxInfoReminders } from "../modules/sellers/taxReminders";
import { reportError } from "../lib/sentry";

const logger = pino({ name: "scheduler" });

type Job = { name: string; everyMs: number; enabled: () => boolean; run: () => Promise<unknown> };

const jobs: Job[] = [
  { name: "order-watchdog", everyMs: 60_000, enabled: () => true, run: runOrderWatchdog },
  { name: "payouts", everyMs: 10 * 60_000, enabled: () => !!env.stripeSecretKey, run: processDuePayouts },
  { name: "drop-processing", everyMs: 2 * 60_000, enabled: mediaConfigured, run: checkProcessingDrops },
  { name: "product-video-processing", everyMs: 2 * 60_000, enabled: mediaConfigured, run: checkProcessingProductVideos },
  { name: "delivery-proof-purge", everyMs: 6 * 60 * 60_000, enabled: mediaConfigured, run: purgeOldDeliveryProofs },
  { name: "import-watchdog", everyMs: 5 * 60_000, enabled: () => true, run: failStaleImports },
  // Order chat is kept 30 days after the order is completed or cancelled
  { name: "chat-purge", everyMs: 6 * 60 * 60_000, enabled: () => true, run: purgeOldMessages },
  // DAC7: stores with sales and no tax details are reminded (every 30 days at most, 2 a year)
  { name: "dac7-reminders", everyMs: 6 * 60 * 60_000, enabled: () => true, run: () => sendTaxInfoReminders() },
  // Agreement acceptance records are kept for the life of the account + 10 years (contract proof), then deleted
  {
    name: "agreement-retention", everyMs: 24 * 60 * 60_000, enabled: () => true,
    run: () => prisma.agreementAcceptance.deleteMany({ where: { user: { deletedAt: { lt: new Date(Date.now() - 10 * 365.25 * 86_400_000) } } } }),
  },
  {
    name: "expired-sign-in-codes", everyMs: 60 * 60_000, enabled: () => true,
    run: () => prisma.otpCode.deleteMany({ where: { expiresAt: { lt: new Date() } } }),
  },
];

/**
 * Takes a time-limited lease on the job. A row lock survives connection pooling (unlike
 * session advisory locks), and a crashed instance's lease simply expires.
 */
export async function acquireLease(name: string, leaseMs: number) {
  return acquire(name, leaseMs);
}

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
        const leaseMs = Math.max(job.everyMs, 5 * 60_000);
        if (!(await acquire(job.name, leaseMs))) return;
        // A run that takes longer than its lease keeps renewing it, so no other instance starts the same job meanwhile
        const renew = setInterval(() => {
          prisma.$executeRaw`UPDATE "JobLease" SET "lockedUntil" = ${new Date(Date.now() + leaseMs)} WHERE "name" = ${job.name}`.catch(() => {});
        }, Math.floor(leaseMs / 3));
        renew.unref();
        try {
          await job.run();
        } finally {
          clearInterval(renew);
          await release(job.name, job.everyMs);
        }
      } catch (err: any) {
        logger.error({ job: job.name, err: err?.message }, "Background job failed");
        reportError(err, { tags: { job: job.name } });
      }
    };
    // Spread the first runs out a little after start-up
    timers.push(setTimeout(tick, 15_000 + Math.random() * 30_000).unref() as unknown as NodeJS.Timeout);
    timers.push(setInterval(tick, job.everyMs).unref() as unknown as NodeJS.Timeout);
  }
}

export function stopScheduler() {
  for (const t of timers) clearTimeout(t);
  timers.length = 0;
}
